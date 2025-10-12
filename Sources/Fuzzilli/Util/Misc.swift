// Copyright 2019 Google LLC
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

import Foundation

func currentMillis() -> UInt64 {
    return UInt64(Date().timeIntervalSince1970 * 1000)
}

func uniqueElements<E>(of list: [E]) -> [E] where E: Hashable {
    return Array(Set(list))
}

func align(_ v: Int, to desiredAlignment: Int) -> Int {
    let remainder = v % desiredAlignment
    return remainder != 0 ? desiredAlignment - remainder : 0
}

func measureTime<R>(_ operation: () -> R) -> (R, Double) {
    let start = Date()
    let r = operation()
    let end = Date()
    return (r, end.timeIntervalSince(start))
}

extension String {
    func rightPadded(toLength n: Int) -> String {
        return padding(toLength: n, withPad: " ", startingAt: 0)
    }

    func leftPadded(toLength n: Int) -> String {
        let diff = n - count
        if diff <= 0 {
            return self
        } else {
            return String(repeating: " ", count: diff) + self
        }
    }
}
