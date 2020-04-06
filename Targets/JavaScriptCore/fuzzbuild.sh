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

export WEBKIT_OUTPUTDIR=FuzzBuild

if [ "$(uname)" == "Darwin" ]; then
    ./Tools/Scripts/build-jsc --jsc-only --release-and-assert --cmakeargs="-DENABLE_STATIC_JSC=ON -DCMAKE_CXX_FLAGS='-fsanitize-coverage=trace-pc-guard -DASSERT_ENABLED=1'"
elif [ "$(uname)" == "Linux" ]; then
    # Note: requires clang >= 4.0!
    ./Tools/Scripts/build-jsc --jsc-only --release-and-assert --cmakeargs="-DENABLE_STATIC_JSC=ON -DCMAKE_C_COMPILER='/usr/bin/clang' -DCMAKE_CXX_COMPILER='/usr/bin/clang++' -DCMAKE_CXX_FLAGS='-fsanitize-coverage=trace-pc-guard -lrt -DASSERT_ENABLED=1'"
else
    echo "Unsupported operating system"
fi
