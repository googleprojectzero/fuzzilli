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
import io
import json
import unittest

from pyfakefs import fake_filesystem_unittest

import merge_json_results


class TestMergeResults(fake_filesystem_unittest.TestCase):

  @fake_filesystem_unittest.patchfs(allow_root_user=True)
  def test_full_run(self, fs):
    with open('/in1.json', 'w') as f:
      json.dump({
        'a/a': {
          'num_tests': 2,
          'failures': [],
        },
        'a/b': {
          'num_tests': 2,
          'failures': [
            {'path': 'a/b/c/failure1', 'output': 'foo'},
          ],
        },
      }, f)

    with open('/in2.json', 'w') as f:
      json.dump({
        'a': {
          'num_tests': 1,
          'failures': [
            {'path': 'a/failure4', 'output': 'foo'},
          ],
        },
        'a/a': {
          'num_tests': 1,
          'failures': [],
        },
        'a/b': {
          'num_tests': 3,
          'failures': [
            {'path': 'a/b/c/failure2', 'output': 'bar 42\nbar 43'},
            {'path': 'a/b/d/failure3', 'output': 'baz'},
          ]
        },
      }, f)

    f = io.StringIO()
    with contextlib.redirect_stdout(f):
      merge_json_results.main([
          '--json-input', '/in1.json',
          '--json-input', '/in2.json',
          '--json-output', '/output.json',
      ])

    # Verify the output.
    self.assertEqual(
        'Successfully merged results.',
        f.getvalue().strip())

    # Verify the results written to the json output file.
    with open('/output.json') as f:
      actual_results = json.load(f)

    expected_results = {
      'a': {
        'failures': [{'output': 'foo', 'path': 'a/failure4'}],
        'num_tests': 1,
      },
      'a/a': {
        'failures': [],
        'num_tests': 3,
      },
      'a/b': {
        'failures': [
          {'output': 'foo', 'path': 'a/b/c/failure1'},
          {'output': 'bar 42\nbar 43', 'path': 'a/b/c/failure2'},
          {'output': 'baz', 'path': 'a/b/d/failure3'},
        ],
        'num_tests': 5,
      },
    }

    self.assertEqual(expected_results, actual_results)


if __name__ == '__main__':
  unittest.main()
