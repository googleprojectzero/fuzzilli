#!/usr/bin/env python3

# Copyright 2026 Google LLC
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

import json
import sys
import os
import subprocess
import tempfile

def run_tests_and_parse():
    if len(sys.argv) < 2:
        print("Usage: ./run_tests.py <expected_failures_file> [swift_test_args...]")
        return 1

    expected_file_path = sys.argv[1]
    test_args = sys.argv[2:]

    with tempfile.TemporaryDirectory() as temp_dir:
        temp_path = os.path.join(temp_dir, "event_stream.json")
        cmd = ["swift", "test", "--event-stream-output-path", temp_path] + test_args
        print(f"Running command: {' '.join(cmd)}\n", flush=True)

        try:
            result = subprocess.run(cmd)
        except KeyboardInterrupt:
            print("\nTest run interrupted by user.")
            return 130

        if not os.path.exists(temp_path):
            print(f"\nError: Event stream file was not created (swift test exited with code {result.returncode}).")
            return 1

        tests_metadata = {}
        actual_failures = set()
        started_tests = set()
        ended_tests = set()
        run_ended = False

        for line in open(temp_path, "r"):
            line = line.strip()
            if not line:
                continue
            data = json.loads(line)
            kind = data.get("kind")
            payload = data.get("payload", {})

            if kind == "test" and payload.get("kind") != "suite":
                test_id = payload.get("id")
                if test_id:
                    tests_metadata[test_id] = payload.get("name", test_id)
            elif kind == "event":
                event_kind = payload.get("kind")
                test_id = payload.get("testID")

                if event_kind == "testStarted" and test_id:
                    started_tests.add(test_id)
                elif event_kind == "testEnded" and test_id:
                    ended_tests.add(test_id)
                elif event_kind == "runEnded":
                    run_ended = True
                if event_kind == "issueRecorded":
                    issue = payload.get("issue", {})
                    if issue.get("isFailure", False) and test_id:
                        actual_failures.add(test_id)

    # Read expected failures.
    try:
        expected_failures = {
            line.strip()
            for line in open(expected_file_path, "r")
            if line.strip() and not line.strip().startswith("#")
        }
    except FileNotFoundError:
        print(f"Error: Expected failures file '{expected_file_path}' not found.")
        return 1

    # Map test IDs to their simple names.
    run_names = {tests_metadata[tid] for tid in started_tests if tid in tests_metadata}
    actual_failing_names = {tests_metadata[tid] for tid in actual_failures if tid in tests_metadata}
    crashed_names = {tests_metadata[tid] for tid in (started_tests - ended_tests) if tid in tests_metadata}

    # Calculate and print results.
    unexpected_failures = actual_failing_names - expected_failures
    # Only include tests that were actually run, so that `--filter=SomeSubSet` doesn't fail because
    # of tests being skipped that are expected to fail.
    expected_failures = expected_failures & run_names
    unexpected_passes = expected_failures - actual_failing_names - crashed_names

    aborted = not run_ended or (result.returncode != 0 and not actual_failing_names)

    if not unexpected_failures and not unexpected_passes and not crashed_names and not aborted:
        print(f"\nAll run tests matched expectations ({len(expected_failures)} expected failure(s))")
        return 0

    for (title, unexpected) in ("Crashes", crashed_names), ("Failures", unexpected_failures), ("Passes", unexpected_passes):
        if unexpected:
            print(f"\nUnexpected {title}:\n{'\n'.join(map(lambda name: f'  • {name}', sorted(unexpected)))}")

    if aborted:
        print(f"\nError: Test runner exited abnormally with code {result.returncode}.")

    return 1

if __name__ == "__main__":
    sys.exit(run_tests_and_parse())
