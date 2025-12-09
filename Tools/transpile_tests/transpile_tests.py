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
import subprocess
import sys

from pathlib import Path

BASE_DIR = Path(__file__).parent.parent.parent


class DefaultMetaDataParser:
  """Class instantiated once per test configuration/suite, providing a
  method to check for supported tests based on their metadata.
  """
  def is_supported(self, abspath, relpath):
    return any(relpath.name.endswith(ext) for ext in ['.js', '.mjs'])


class Test262MetaDataParser(DefaultMetaDataParser):
  def __init__(self, base_dir):
    """Metadata parsing for Test262 analog to the V8 test suite definition."""
    tools_abs_path = base_dir / 'test/test262/data/tools/packaging'
    loader = importlib.machinery.SourceFileLoader(
        'parseTestRecord', f'{tools_abs_path}/parseTestRecord.py')
    self.parse = loader.load_module().parseTestRecord
    self.excluded_suffixes = ['_FIXTURE.js']
    self.excluded_dirs = ['staging']

  def is_supported(self, abspath, relpath):
    if not super().is_supported(abspath, relpath):
      return False

    if any(relpath.name.endswith(suffix)
           for suffix in self.excluded_suffixes):
      return False

    if any(str(relpath).startswith(directory)
           for directory in self.excluded_dirs):
      return False

    with open(abspath, encoding='utf-8') as f:
      content = f.read()
    record = self.parse(content, relpath)
    # We don't support negative tests, which typically exhibit syntax errors.
    return 'negative' not in record


TEST_CONFIGS = {
  'test262': {
    'path': 'test/test262/data/test',
    'excluded_suffixes': ['_FIXTURE.js'],
    # TODO(https://crbug.com/442444727): We might want to track the staging
    # tests separately. Those typically address in-progress JS features with
    # a high import-failure rate.
    'excluded_dirs': ['staging'],
    'metadata_parser': Test262MetaDataParser,
  }
}


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
  """Transpile one test from JS -> JS with Fuzzilli.

  This method is to be called via the multi-process boundary.

  We rebuild the original directory structure on the output side.
  """
  input_file, output_file = args
  os.makedirs(output_file.parent, exist_ok=True)
  process = run_transpile_tool(input_file, output_file)
  return process.returncode, input_file, process.stdout.decode('utf-8')


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
  """Transpile all tests from one suite configuration in parallel."""
  test_config = TEST_CONFIGS[options.config]
  test_input_dir = base_dir / test_config['path']
  metadata_parser = test_config['metadata_parser'](base_dir)

  # Prepare inputs as a generator over tuples of input/output path.
  verbose_print(options, f'Listing tests in {test_input_dir}')
  def test_input_gen():
    for index, abspath in enumerate(list_test_filenames(
        test_input_dir, metadata_parser.is_supported)):
      if supports_index_on_shard(options, index):
        yield (abspath, output_dir / abspath.relative_to(base_dir))

  # Iterate over all tests in parallel and collect stats.
  num_tests = 0
  failures = []
  with multiprocessing.Pool(multiprocessing.cpu_count()) as pool:
    for exit_code, abspath, stdout in pool.imap_unordered(
        transpile_test, test_input_gen()):
      num_tests += 1
      if exit_code != 0:
        relpath = abspath.relative_to(base_dir)
        failures.append({'path': str(relpath), 'output': stdout})
        verbose_print(options, f'Failed to compile {relpath}')
      if (num_tests + 1) % 500 == 0:
        print(f'Processed {num_tests + 1} test cases.')

  # Render and return results.
  assert num_tests, 'Failed to find any tests.'
  num_successes = num_tests - len(failures)
  ratio = float(num_successes) / num_tests * 100
  print(f'Successfully compiled {ratio:.2f}% '
        f'({num_successes} of {num_tests}) test cases.')
  return {
    'num_tests': num_tests,
    'failures': failures,
  }


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
    '--num-shards', type=int, default=1, choices=range(1, 9),
    help='Overall number of shards to split this task into.')
  parser.add_argument(
    '--shard-index', type=int, default=0, choices=range(0, 8),
    help='Index of the current shard for doing a part of the '
         'overall task.')
  parser.add_argument(
    '-v', '--verbose', default=False, action='store_true',
    help='Print more verbose output.')
  return parser.parse_args(args)


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
