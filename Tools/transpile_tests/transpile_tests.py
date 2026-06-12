# Copyright 2025 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""
Script to transpile (compile to FuzzIL and lift again to JS) multiple
tests in parallel with the Fuzzilli FuzzILTool. The output of the
script provides 1) the tests so that those can be used e.g. for execution
in the V8 test framework, and 2) statistics about the overall transpilation
state to track the progress of extending the compiler.
"""

import argparse
import importlib.machinery
import json
import multiprocessing
import os
import re
import subprocess
import sys

from collections import defaultdict, Counter
from pathlib import Path

BASE_DIR = Path(__file__).parent.parent.parent


def run_d8(d8_exec, harness_files, script_path, timeout=60):
  """Executes the given script in d8 with resolved harness files and a safety timeout."""
  cmd = [d8_exec, '--correctness-fuzzer-suppressions'] + harness_files + [script_path]
  try:
    # Explicitly decode as UTF-8 with replace error handling (instead of using locale-dependent text=True)
    # to prevent UnicodeDecodeError crashes on environments using non-UTF-8 default locales (e.g. ASCII).
    res = subprocess.run(
        cmd, capture_output=True, encoding='utf-8', errors='replace', timeout=timeout)
    return res.returncode, res.stdout + res.stderr
  except subprocess.TimeoutExpired as e:
    # Prior to Python 3.12, e.stdout/stderr might be bytes objects even under text=True.
    # We cleanly decode them to avoid TypeError crashes, using 'is not None' to bypass roundtrips on empty strings.
    stdout_bytes = e.stdout if e.stdout is not None else b""
    stderr_bytes = e.stderr if e.stderr is not None else b""
    stdout = stdout_bytes.decode('utf-8', errors='replace') if isinstance(stdout_bytes, bytes) else stdout_bytes
    stderr = stderr_bytes.decode('utf-8', errors='replace') if isinstance(stderr_bytes, bytes) else stderr_bytes
    timeout_msg = f"\n[EXEC_FAILURE: TIMEOUT EXPIRED after {timeout} seconds]"
    return -9, stdout + stderr + timeout_msg


class DefaultMetaDataParser:
  """Class instantiated once per test configuration/suite, providing a
  method to check for supported tests based on their metadata.
  """
  def __init__(self, _):
    pass

  def is_supported(self, abspath, relpath):
    return any(relpath.name.endswith(ext) for ext in ['.js', '.mjs'])

  def get_harness_files(self, abspath, harness_dir):
    return []


class Test262MetaDataParser(DefaultMetaDataParser):
  def __init__(self, base_dir):
    """Metadata parsing for Test262 analog to the V8 test suite definition."""
    tools_abs_path = base_dir / 'test/test262/data/tools/packaging'
    loader = importlib.machinery.SourceFileLoader(
        'parseTestRecord', f'{tools_abs_path}/parseTestRecord.py')
    self.parse = loader.load_module().parseTestRecord
    self.excluded_suffixes = ['_FIXTURE.js']

  def is_supported(self, abspath, relpath):
    if not super().is_supported(abspath, relpath):
      return False

    if any(relpath.name.endswith(suffix)
           for suffix in self.excluded_suffixes):
      return False

    with open(abspath, encoding='utf-8') as f:
      content = f.read()
    record = self.parse(content, relpath)
    # We don't support negative tests, which typically exhibit syntax errors.
    return 'negative' not in record

  def get_harness_files(self, abspath, harness_dir):
    with open(abspath, encoding='utf-8') as f:
      content = f.read()
    record = self.parse(content, abspath)
    harness_files = [
        os.path.join(harness_dir, "sta.js"),
        os.path.join(harness_dir, "assert.js")
    ]
    for inc in record.get('includes', []):
      harness_files.append(os.path.join(harness_dir, inc))
    return harness_files


TEST_CONFIGS = {
  'mjsunit': {
    'path': 'test/mjsunit',
    'excluded_suffixes': [],
    'levels': 2,
    'expand_level_paths': [],
    'metadata_parser': DefaultMetaDataParser,
  },
  'test262': {
    'path': 'test/test262/data/test',
    'harness_dir': 'test/test262/data/harness',
    'excluded_suffixes': ['_FIXTURE.js'],
    'levels': 2,
    'expand_level_paths': [
      'annexB/language',
      'built-ins/Object',
      'built-ins/RegExp',
      'built-ins/Temporal',
      'intl402/Temporal',
      'language/expressions',
      'language/expressions/class',
      'language/statements',
      'language/statements/class',
    ],
    'metadata_parser': Test262MetaDataParser,
  },
}


class TestCounter:
  """Class to count test results, keyed by a number of directories of each
  test's relative path.

  The number of levels per key is passed to the constructor. Then when
  counting tests, each tests goes into a results bucket for its key, e.g.:
  With level 2, test 'a/b/c/d/test1.js' will have key 'a/b'.

  With `expand_level_paths` we can configure those paths under which we
  should expand results beyond the configured level. Each listed path
  will create result keys with one level deeper than that path.

  The final results structure is a dict key -> results, where results
  is a dict:
  { 'num_tests': <all tests on that level>, 'failures': <list of failures>}

  Example for 2 tests with 1 failure under the a/b directory and 1 tests under
  a/c:
  {
    'a/b': {
      'num_tests': 2,
      'failures': [{'path': 'a/b/c/d/test1.js', 'output': 'stdout'}],
    },
    'a/c': {
      'num_tests': 1,
      'failures': [],
    },
  }
  """
  def __init__(self, levels, expand_level_paths, options):
    self.levels = levels
    # Cache the depth level of each expansion path
    self.expand_level_paths = [
      (p, p.count('/') + 1) for p in expand_level_paths]
    self.options = options
    self.num_tests = Counter()
    self.failures = defaultdict(list)
    self.total_tests = 0
    self.num_failures = 0

  @property
  def num_successes(self):
    return self.total_tests - self.num_failures

  def largest_expansion_level(self, relpath):
    """Returns the level until which relpath should be expanded, based on
    the configured expansion paths.
    """
    path_str = str(relpath)
    candidates = [-1]
    for path, count in self.expand_level_paths:
      if path_str.startswith(path):
        candidates.append(count)
    return max(candidates) + 1

  def level_key(self, relpath):
    parts = list(relpath.parts)
    assert parts
    assert parts[0] != '/'

    parts = parts[:-1]
    parts = parts[:max(self.levels, self.largest_expansion_level(relpath))]
    return '/'.join(parts)

  def count(self, exit_code, relpath, stdout):
    self.total_tests += 1
    key = self.level_key(relpath)
    self.num_tests[key] += 1
    if exit_code != 0:
      self.num_failures += 1
      if exit_code == 2:
        verbose_print(self.options, f'Failed to verify (exit code mismatch): {relpath}')
      elif exit_code == 3:
        verbose_print(self.options, f'Failed to verify (output mismatch): {relpath}')
      else:
        verbose_print(self.options, f'Failed to compile: {relpath}')
      self.failures[key].append({'path': str(relpath), 'output': stdout})
    if (self.total_tests + 1) % 500 == 0:
      print(f'Processed {self.total_tests + 1} test cases.')

  def results(self):
    return dict(
        (
          key,
          {
            'num_tests': self.num_tests[key],
            'failures': self.failures[key],
          },
        )
        for key in sorted(self.num_tests.keys())
    )


def list_test_filenames(test_root, is_supported_fun):
  """Walk directories and return all absolute test filenames for supported
  tests.
  """
  for dirname, dirs, files in os.walk(test_root, followlinks=True):
    dirs.sort()
    files.sort()
    for filename in files:
      abspath = Path(dirname) / filename
      if is_supported_fun(abspath, abspath.relative_to(test_root)):
        yield abspath


def run_transpile_tool(input_file, output_file):
  cmd = [
      BASE_DIR / '.build/debug/FuzzILTool',
      '--compile',
      input_file,
      f'--outputPathJS={output_file}',
  ]
  return subprocess.run(
      cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)


def transpile_test(args):
  """Transpile and optionally verify one test."""
  input_file, output_file, d8_path, harness = args
  os.makedirs(output_file.parent, exist_ok=True)

  # 1. Compile to Lifted JS
  process = run_transpile_tool(str(input_file), str(output_file))

  # Safe decode using errors='replace' to prevent UnicodeDecodeError on invalid chars
  compile_stdout = process.stdout.decode('utf-8', errors='replace')
  if process.returncode != 0:
    prefix = "[COMPILE_FAILURE]\n" if d8_path else ""
    return (
        process.returncode,
        input_file,
        prefix + compile_stdout
    )

  # 2. Optional Differential Verification Run
  if d8_path and harness is not None:

    # Run original and lifted JS
    orig_code, orig_output = run_d8(d8_path, harness, str(input_file))
    lifted_code, lifted_output = run_d8(d8_path, harness, str(output_file))

    test_filename = input_file.name
    # 1. Clean up absolute path references in outputs
    orig_output_cleaned = orig_output.replace(str(input_file), test_filename)
    lifted_output_cleaned = lifted_output.replace(str(output_file), test_filename)

    # 2. Normalize outputs to avoid false-positive mismatches when both scripts throw identical exceptions:
    # A. Strip out the offending source code line and the caret (^) printed on the following line in stderr
    #    as the source code differs between original and lifted files.
    orig_output_cleaned = re.sub(r'\n[^\n]+\n\s*\^\s*(?=\n|$)', '\n', orig_output_cleaned)
    lifted_output_cleaned = re.sub(r'\n[^\n]+\n\s*\^\s*(?=\n|$)', '\n', lifted_output_cleaned)

    # B. Strip out line and column numbers (e.g. ":25:3" and ":25" at word boundaries) in stderr stack traces
    #    as the line counts differ between original and lifted files.
    orig_output_cleaned = re.sub(r':\d+(:\d+)?\b', '', orig_output_cleaned)
    lifted_output_cleaned = re.sub(r':\d+(:\d+)?\b', '', lifted_output_cleaned)

    # Assert exit code & logs
    if orig_code != lifted_code:
      mismatch_report = (
          f"[EXEC_FAILURE: EXIT CODE MISMATCH]\n"
          f"Original Exit Code: {orig_code}, Lifted Exit Code: {lifted_code}\n"
          f"Original Output:\n{orig_output_cleaned.strip()}\n"
          f"Lifted Output:\n{lifted_output_cleaned.strip()}"
      )
      return 2, input_file, mismatch_report

    if orig_output_cleaned != lifted_output_cleaned:
      mismatch_report = (
          f"[EXEC_FAILURE: CONSOLE OUTPUT MISMATCH]\n"
          f"Original Output:\n{orig_output_cleaned.strip()}\n"
          f"Lifted Output:\n{lifted_output_cleaned.strip()}"
      )
      return 3, input_file, mismatch_report

  return 0, input_file, compile_stdout


def verbose_print(options, text):
  if options.verbose:
    print(text)

def supports_index_on_shard(options, index):
  """If the task is distributed over multiple shards (bots), this returns if
  a particular deterministic test index is part of the current run.

  The test list must be equal and have a deterministic order across shards.

  With the default options, this function returns always True, e.g.:
  index % 1 == 0.
  """
  return index % options.num_shards == options.shard_index


def transpile_suite(options, base_dir, output_dir):
  """Transpile and verify all tests from one suite configuration in parallel."""
  test_config = TEST_CONFIGS[options.config]
  test_input_dir_root = base_dir / test_config['path']

  if options.test_dir:
    test_input_dir = test_input_dir_root / options.test_dir
  else:
    test_input_dir = test_input_dir_root

  metadata_parser = test_config['metadata_parser'](base_dir)

  # Prepare inputs as a generator over tuples of (input_path, output_path, d8_path, harness_dir)
  verbose_print(options, f'Listing tests in {test_input_dir}')

  harness_dir_config = test_config.get('harness_dir')
  harness_dir = str(base_dir / harness_dir_config) if options.d8_path and harness_dir_config else None

  def test_input_gen():
    for index, abspath in enumerate(list_test_filenames(
        test_input_dir, metadata_parser.is_supported)):
      if supports_index_on_shard(options, index):
        # We must provide relpath relative to the base_dir to preserve V8 folder layout for testing
        rel_p_output = abspath.relative_to(base_dir)
        yield (
            abspath,
            output_dir / rel_p_output,
            options.d8_path,
            metadata_parser.get_harness_files(abspath, harness_dir) if harness_dir else None
        )

  # Iterate over all tests in parallel and collect stats.
  counter = TestCounter(
      test_config['levels'], test_config['expand_level_paths'], options)
  with multiprocessing.Pool(multiprocessing.cpu_count()) as pool:
    for exit_code, abspath, stdout in pool.imap_unordered(
        transpile_test, test_input_gen()):
      # Get relpath relative to the root for grouping keys
      relpath = abspath.relative_to(test_input_dir_root)
      counter.count(exit_code, relpath, stdout)

  # Render and return results.
  assert counter.total_tests, 'Failed to find any tests.'
  ratio = float(counter.num_successes) / counter.total_tests * 100
  print(f'Successfully compiled {ratio:.2f}% '
        f'({counter.num_successes} of {counter.total_tests}) test cases.')
  return counter.results()


def write_json_output(path, results):
  with open(path, 'w') as f:
    json.dump(results, f, sort_keys=True, indent=2)


def parse_args(args):
  parser = argparse.ArgumentParser()
  parser.add_argument(
    '--base-dir', required=True,
    help='Absolute path to the V8 checkout.')
  parser.add_argument(
    '--config', required=True, choices=TEST_CONFIGS.keys(),
    help='Name of the supported test configuration.')
  parser.add_argument(
    '--output-dir', required=True,
    help='Absolute path pointing to an empty directory, '
         'where this script will place the output files.')
  parser.add_argument(
    '--json-output',
    help='Optional absolute path to a json file, '
         'where this script will write its stats to.')
  parser.add_argument(
    '--d8-path',
    help='Optional absolute path to the d8 executable. If provided, '
         'the script will run differential execution validation in d8.')
  parser.add_argument(
    '--test-dir',
    help='Optional relative path to a subdirectory inside the test suite '
         '(e.g. "language/statements/for-of"). Limits the run to this folder.')
  parser.add_argument(
    '--num-shards', type=int, default=1, choices=range(1, 9),
    help='Overall number of shards to split this task into.')
  parser.add_argument(
    '--shard-index', type=int, default=0, choices=range(0, 8),
    help='Index of the current shard for doing a part of the '
         'overall task.')
  parser.add_argument(
    '-v', '--verbose', default=False, action='store_true',
    help='Print more verbose output.')
  options = parser.parse_args(args)
  # Validate that differential execution is only enabled for test262 configuration
  if options.d8_path and options.config != 'test262':
    parser.error("--d8-path option is currently only supported for test262 configuration.")
  return options


def main(args):
  options = parse_args(args)
  assert options.shard_index < options.num_shards
  base_dir = Path(options.base_dir)
  output_dir = Path(options.output_dir)
  results = transpile_suite(options, base_dir, output_dir)
  if options.json_output:
    write_json_output(options.json_output, results)


if __name__ == '__main__':
  main(sys.argv[1:])
