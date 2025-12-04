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

import contextlib
import glob
import io
import json
import os
import unittest

from collections import namedtuple
from mock import patch
from pathlib import Path
from pyfakefs import fake_filesystem_unittest

import transpile_tests


TEST_DATA = Path(__file__).parent / 'testdata'


# Mock out the FuzzIL tool, but mimick writing the desired output file.
# Simulate one compilation failure for the test with "fail" in its name.
Process = namedtuple('Process', 'returncode stdout')
def fake_transpile(input_file, output_file):
  if 'fail' in str(output_file):
    return Process(1, 'Failed!'.encode('utf-8'))
  with open(output_file, 'w') as f:
    f.write('')
  return Process(0, b'')


# Replace the multiprocessing Pool with a fake that doesn't mess with the
# fake file system.
class FakePool:
  def __init__(self, _):
    pass

  def __enter__(self):
    return self

  def __exit__(self, *_):
    pass

  def imap_unordered(self, *args):
    return map(*args)


class TestTranspileTests(fake_filesystem_unittest.TestCase):

  @fake_filesystem_unittest.patchfs(allow_root_user=True)
  def test_full_run(self, fs):
    base_dir = TEST_DATA / 'transpile_full_run' / 'v8'
    fs.create_dir('/output')
    fs.add_real_directory(base_dir)

    f = io.StringIO()
    with contextlib.redirect_stdout(f):
      with patch(
          'transpile_tests.run_transpile_tool', fake_transpile):
        with patch(
            'multiprocessing.Pool', FakePool):
          transpile_tests.main([
              '--config', 'test262',
              '--base-dir', str(base_dir),
              '--output-dir', '/output',
              '--json-output', '/output.json',
          ])

    # Verify the output.
    self.assertEqual(
        'Successfully compiled 75.00% (3 of 4) test cases.',
        f.getvalue().strip())

    # Verify the written output files.
    expected_files = [
      '/output/test/test262/data/test/folder1/subfolder1/Test1.js',
      '/output/test/test262/data/test/folder1/subfolder1/Test2.js',
      '/output/test/test262/data/test/folder2/Test3.js',
    ]
    self.assertEqual(
        expected_files, glob.glob('/output/**/*.*', recursive=True))

    # Verify the results written to the json output file.
    with open('/output.json') as f:
      actual_results = json.load(f)

    expected_results = {
      'num_tests': 4,
      'num_successes': 3,
      'percent_successes': 75.0,
      'failures': [
        {
          'output': 'Failed!',
          'path': 'test/test262/data/test/folder2/Test4_fail.js',
        },
      ],
    }
    self.assertEqual(expected_results, actual_results)

  @fake_filesystem_unittest.patchfs(allow_root_user=True)
  def test_shard_run(self, fs):
    base_dir = TEST_DATA / 'transpile_full_run' / 'v8'
    fs.create_dir('/output')
    fs.add_real_directory(base_dir)

    f = io.StringIO()
    with contextlib.redirect_stdout(f):
      with patch(
          'transpile_tests.run_transpile_tool', fake_transpile):
        with patch(
            'multiprocessing.Pool', FakePool):
          transpile_tests.main([
              '--config', 'test262',
              '--base-dir', str(base_dir),
              '--output-dir', '/output',
              '--json-output', '/output.json',
              '--num-shards', '2',
              '--shard-index', '1',
          ])

    # Verify the output.
    self.assertEqual(
        'Successfully compiled 50.00% (1 of 2) test cases.',
        f.getvalue().strip())

    # Verify the written output files.
    expected_files = [
      '/output/test/test262/data/test/folder1/subfolder1/Test2.js',
    ]
    self.assertEqual(
        expected_files, glob.glob('/output/**/*.*', recursive=True))

    # Verify the results written to the json output file.
    with open('/output.json') as f:
      actual_results = json.load(f)

    expected_results = {
      'num_tests': 2,
      'num_successes': 1,
      'percent_successes': 50.0,
      'failures': [
        {
          'output': 'Failed!',
          'path': 'test/test262/data/test/folder2/Test4_fail.js',
        },
      ],
    }
    self.assertEqual(expected_results, actual_results)

if __name__ == '__main__':
  unittest.main()
