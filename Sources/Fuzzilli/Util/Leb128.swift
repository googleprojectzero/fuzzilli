// Copyright 2022 Google LLC
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

public struct Leb128 {
    public static func unsignedEncode(_ value: Int) -> Data {
        assert(value >= 0)
        var value = value

        var data = Data()

        repeat {
            // Grab lower 7 bits
            var byte = UInt8(value & 0b1111111)
            value >>= 7
            if value != 0 {
                // Set high bit of byte, as there is more to come
                byte |= 0b10000000
            }
            data.append(byte)
        } while value != 0

        return data
    }

    public static func signedEncode(_ value: Int) -> Data {
        var value = value
        var data = Data()

        var more = true
        while more {
            var byte = UInt8(value & 0x7F)
            value = value >> 7

            if (value == 0 && (byte >> 6) == 0) || (value == -1 && (byte >> 6) == 1) {
                more = false
            } else {
                byte |= 0x80
            }

            data.append(byte)
        }

        return data
    }
}
