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

/// Model of the execution environment.
public protocol Environment: Component {
    /// List of integer values that might yield interesting behaviour or trigger edge cases in the target language.
    var interestingIntegers: [Int] { get }
    
    /// List of floating point values that might yield interesting behaviour or trigger edge cases in the target language.
    var interestingFloats: [Double] { get }
    
    /// List of string values that might yield interesting behaviour or trigger edge cases in the target language.
    var interestingStrings: [String] { get }
    
    /// List of builtin objects in the target environment.
    var builtins: [String] { get }
    
    /// List of property names in the target environment.
    var propertyNames: [String] { get }
    
    /// List of method names in the target environment.
    var methodNames: [String] { get }
}

public class JavaScriptEnvironment: ComponentBase, Environment {
    // Possible return values of the 'typeof' operator.
    public static let jsTypeNames = ["undefined", "boolean", "number", "string", "symbol", "function", "object"]
    
    // Integer values that are more likely to trigger edge-cases.
    public let interestingIntegers = [-9007199254740993, -9007199254740992, -9007199254740991,          // Smallest integer value that is still precisely representable by a double
                                      -4294967297, -4294967296, -4294967295,                            // Negative Uint32 max
                                      -2147483649, -2147483648, -2147483647,                            // Int32 min
                                      -1073741824, -536870912, -268435456,                              // -2**32 / {4, 8, 16}
                                      -65537, -65536, -65535,                                           // -2**16
                                      -4096, -1024, -256, -128,                                         // Other powers of two
                                      -2, -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 16, 64,                 // Numbers around 0
                                      127, 128, 129,                                                    // 2**7
                                      255, 256, 257,                                                    // 2**8
                                      512, 1000, 1024, 4096, 10000,                                     // Misc numbers
                                      65535, 65536, 65537,                                              // 2**16
                                      268435456, 536870912, 1073741824,                                 // 2**32 / {4, 8, 16}
                                      2147483647, 2147483648, 2147483649,                               // Int32 max
                                      4294967295, 4294967296, 4294967297,                               // Uint32 max
                                      9007199254740991, 9007199254740992, 9007199254740993,             // Biggest integer value that is still precisely representable by a double
    ]
    
    // Double values that are more likely to trigger edge-cases.
    public let interestingFloats = [-Double.infinity, -Double.greatestFiniteMagnitude, -1e12, -1e9, -1e6, -1e3, -5.0, -4.0, -3.0, -2.0, -1.0, -Double.ulpOfOne, -Double.leastNormalMagnitude, -0.0, 0.0, Double.leastNormalMagnitude, Double.ulpOfOne, 1.0, 2.0, 3.0, 4.0, 5.0, 1e3, 1e6, 1e9, 1e12, Double.greatestFiniteMagnitude, Double.infinity, Double.nan]

    // TODO more?
    public let interestingStrings = jsTypeNames
    
    public let builtins: [String]
    public let propertyNames: [String]
    public let methodNames: [String]
    
    public init(builtins: [String], propertyNames: [String], methodNames: [String]) {
        self.builtins = builtins
        self.propertyNames = propertyNames
        self.methodNames = methodNames
        
        super.init(name: "Environment")
        
        assert(Set(builtins).count == builtins.count)
        assert(Set(propertyNames).count == propertyNames.count)
        assert(Set(methodNames).count == methodNames.count)
    }
}
