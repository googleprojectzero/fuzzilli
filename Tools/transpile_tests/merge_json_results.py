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
Script to merge multiple output json files from transpile_tests.py into one.
"""

import argparse
import json
import sys


def merge_test_results(inputs):
  num_tests = 0
  failures = []
  for result in inputs:
    num_tests += result["num_tests"]
    failures += result["failures"]

  return {
    'num_tests': num_tests,
    'failures': failures,
  }


def parse_args(args):
  parser = argparse.ArgumentParser()
  parser.add_argument(
    '--json-input', action='append', required=True,
    help='Path to a json results file from transpile_tests.py.')
  parser.add_argument(
    '--json-output', required=True,
    help='Path to the merged json results file.')
  return parser.parse_args(args)


def main(args):
  options = parse_args(args)

  inputs = []
  for input_path in options.json_input:
    with open(input_path) as f:
      inputs.append(json.load(f))

  result = merge_test_results(inputs)
  with open(options.json_output, 'w') as f:
    json.dump(result, f, sort_keys=True, indent=2)

  print(f'Merged results for {result["num_tests"]} tests '
        f'and {len(result["failures"])} failures.')


if __name__ == '__main__':
  main(sys.argv[1:])
