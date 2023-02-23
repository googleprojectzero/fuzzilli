#!/bin/bash
#
# Copyright 2019 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# https:#www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

if [ "$(uname)" == "Linux" ]; then
    # See https://v8.dev/docs/compile-arm64 for instructions on how to build on Arm64
    gn gen out/fuzzbuild --args='is_debug=false dcheck_always_on=true v8_static_library=true v8_enable_verify_heap=true v8_fuzzilli=true sanitizer_coverage_flags="trace-pc-guard" target_cpu="x64"'
else
    echo "Unsupported operating system"
fi

ninja -C ./out/fuzzbuild d8
