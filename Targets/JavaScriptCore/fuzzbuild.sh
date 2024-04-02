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

if [ "$(uname)" == "Linux" ]; then
    ./Tools/Scripts/build-jsc --jsc-only --debug --cmakeargs="-DENABLE_STATIC_JSC=ON -DCMAKE_C_COMPILER='/usr/bin/clang' -DCMAKE_CXX_COMPILER='/usr/bin/clang++' -DCMAKE_CXX_FLAGS='-fsanitize-coverage=trace-pc-guard -O3 -lrt'"
elif [ "$(uname)" == "Darwin" ]; then
    unset WEBKIT_OUTPUTDIR # remove the outputdir env on macOS for the build without cmake will be in the Source directory(maybe the build-jsc have problem)
    ./Tools/Scripts/set-webkit-configuration --debug --analyze --coverage --force-optimization-level=O3 
    ./Tools/Scripts/build-jsc
else
    echo "Unsupported operating system"
fi
