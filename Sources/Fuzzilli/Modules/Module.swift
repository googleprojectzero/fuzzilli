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

// A module interacts with the fuzzer in some way but does not provide services
// to the rest of the fuzzer and is not required for basic functionality.
public protocol Module {
    // Will be called after the fuzzer is fully initialized and able to execute programs.
    // At this point, all other modules will have been instantiated but might not be initialized yet.
    // Useful if a module makes use of another module.
    func initialize(with fuzzer: Fuzzer)
}

extension Module {
    public func initialize(with fuzzer: Fuzzer) {}

    public var name: String {
        return String(describing: type(of: self))
    }

    public static var name: String {
        return String(describing: self)
    }

    /// Returns the instance of this module on the provided fuzzer instance if it exists, nil otherwise.
    public static func instance(for fuzzer: Fuzzer) -> Self? {
        if let instance = fuzzer.modules[self.name] {
            return instance as? Self
        } else {
            return nil
        }
    }
}
