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

FLAGS="-fsanitize-coverage=trace-pc-guard -g -DJS_MORE_DETERMINISTIC"

export CXXFLAGS=$FLAGS
export CC=clang-10
export CXX=clang++-10

mkdir fuzzbuild_OPT.OBJ
cd fuzzbuild_OPT.OBJ
/bin/sh ../configure.in --enable-debug --enable-optimize --disable-shared-js --enable-js-fuzzilli

make -j$(getconf _NPROCESSORS_ONLN)
