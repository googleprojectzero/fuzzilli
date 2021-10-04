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

func convertToCArray(_ array: [String]) -> UnsafeMutablePointer<UnsafePointer<Int8>?> {
    let buffer = UnsafeMutablePointer<UnsafePointer<Int8>?>.allocate(capacity: array.count + 1)
    for (i, str) in array.enumerated() {
#if os(Windows)
        buffer[i] = UnsafePointer(str.withCString(_strdup))
#else
        buffer[i] = UnsafePointer(str.withCString(strdup))
#endif
    }
    buffer[array.count] = nil
    return buffer
}

func freeCArray(_ array: UnsafeMutablePointer<UnsafePointer<Int8>?>, numElems: Int) {
    for arg in array ..< array + numElems {
        free(UnsafeMutablePointer(mutating: arg.pointee))
    }
    array.deallocate()
}
