// Copyright 2020 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
var varNumbers = getObjectKeys(types)
// Do not use for in to avoid iterating over prototype properties
for (var i=0;i<varNumbers.length;i++) {
    var varNumber = varNumbers[i]
    var instrNumbers = getObjectKeys(types[varNumber])
    fuzzilli('FUZZILLI_PRINT', varNumber)
    fuzzilli('FUZZILLI_PRINT', instrNumbers.length)

    for (var j=0;j<instrNumbers.length;j++) {
        var instrNumber = instrNumbers[j]
        fuzzilli('FUZZILLI_PRINT', instrNumber)
        fuzzilli('FUZZILLI_PRINT', jsonStringify(types[varNumber][instrNumber]))
    }
}
