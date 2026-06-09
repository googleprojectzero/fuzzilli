#!/usr/bin/env python3

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

import argparse
import os
import shutil
import subprocess

from pathlib import Path

BASE_DIR = Path(__file__).parent.parent.resolve()
PROTO_DIR = BASE_DIR / "Sources/Fuzzilli/Protobuf"

KNOWN_PROTO_FILES = [
    "program.proto",
    "operations.proto",
    "sync.proto",
    "ast.proto"
]

def check_git_clean(info):
    """Check that the git repository does not have any uncommitted changes."""
    result = subprocess.run(
        ["git", "diff", "--name-only"],
        cwd=BASE_DIR,
        capture_output=True,
        check=True)
    output = result.stdout.decode().strip()
    if output != "":
        diff_result = subprocess.run(["git", "diff"], cwd=BASE_DIR, capture_output=True, check=True)
        assert False, f"Unexpected modified files {info}: {output}\n== Diff ==\n{diff_result.stdout.decode()}"

def regenerate_opcodes():
    subprocess.run(["python3", "./gen_programproto.py"], cwd=PROTO_DIR, check=True)

def regenerate_proto():
    if not shutil.which("protoc"):
        print("Skipping protobuf validation as protoc is not available.")
        return

    swift_protobuf_path = BASE_DIR / ".build/checkouts/swift-protobuf"
    assert swift_protobuf_path.exists(), \
        "The presubmit requires a swift-protobuf checkout, e.g. via \"swift build\""
    # Build swift-protobuf (for simplicity reuse the fetched repository from the swift-protobuf library).
    # Use a debug build as running it is very quick while building it with reelase might be slow.
    subprocess.run(["swift", "build", "-c", "debug"], cwd=swift_protobuf_path, check=True)
    env = os.environ.copy()
    env["PATH"] = f"{swift_protobuf_path}/.build/debug:" + env["PATH"]
    cmd = ["protoc", "--swift_opt=Visibility=Public", "--swift_out=."] + KNOWN_PROTO_FILES
    subprocess.run(cmd, cwd=PROTO_DIR, check=True, env=env)

def check_proto():
    """Check that program.proto is up-to-date."""
    print("Checking generated protobuf files...")
    regenerate_opcodes()
    check_git_clean("after running gen_programproto.py")
    regenerate_proto()
    check_git_clean("after regenerating protobuf files")

def run_formatting():
    subprocess.run(["swift", "format", BASE_DIR, "--recursive", "--parallel", "--in-place"], check=True)

def check_formatting():
    run_formatting()
    check_git_clean("after auto-formatting")

def check_all():
    check_git_clean("before any checks")
    check_proto()
    check_formatting()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--format", action="store_true", help="Run auto-formatting.")
    parser.add_argument("--regenerate-proto", action="store_true", help="Regenerate OpCodes.swift protobuf files.")
    args = parser.parse_args()

    if args.format or args.regenerate_proto:
        if args.regenerate_proto:
            regenerate_opcodes()
            regenerate_proto()
        if args.format:
            run_formatting()
    else:
        check_all()

if __name__ == '__main__':
  main()
