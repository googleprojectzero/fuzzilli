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
@testable import Fuzzilli

extension Program: Equatable {
    // Fairly expensive equality testing, but it's only needed for testing anyway... :)
    public static func == (lhs: Program, rhs: Program) -> Bool {
        // We consider two programs to be equal if their code is equal
        let code1 = lhs.code.map({ $0.asProtobuf() })
        let code2 = rhs.code.map({ $0.asProtobuf() })
        return code1 == code2
    }
}
    
// Convenience variable constructor
func v(_ n: Int) -> Variable {
    return Variable(number: n)
}
