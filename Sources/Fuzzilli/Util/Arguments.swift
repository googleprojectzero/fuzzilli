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

/// Provides conventient access to a program's command line arguments.
public class Arguments {
    public let programName: String

    public var numPositionalArguments: Int {
        return positionalArguments.count
    }

    public var numOptionalArguments: Int {
        return optionalArguments.count
    }

    /// Any optional arguments that have not been used.
    public private(set) var unusedOptionals: Set<String>

    private let positionalArguments: [String]
    private let optionalArguments: [String: String]

    init(programName: String, positionalArguments: [String], optionalArguments: [String: String]) {
        self.programName = programName
        self.positionalArguments = positionalArguments
        self.optionalArguments = optionalArguments
        unusedOptionals = Set<String>(optionalArguments.keys)
    }

    public func useArgument(_ key: String) -> String? {
        unusedOptionals.remove(key)
        return optionalArguments[key]
    }

    public subscript(index: Int) -> String {
        return positionalArguments[index]
    }

    public subscript(name: String) -> String? {
        let key = String(name.drop(while: { $0 == "-" }))
        return useArgument(key)
    }

    public func int(for name: String) -> Int? {
        if let value = self[name] {
            return Int(value)
        } else {
            return nil
        }
    }

    public func uint(for name: String) -> UInt? {
        if let value = self[name] {
            return UInt(value)
        } else {
            return nil
        }
    }

    public func bool(for name: String) -> Bool? {
        if let value = self[name] {
            return Bool(value)
        } else {
            return nil
        }
    }

    public func double(for name: String) -> Double? {
        if let value = self[name] {
            return Double(value)
        } else {
            return nil
        }
    }

    public func has(_ name: String) -> Bool {
        return self[name] != nil
    }

    public static func parse(from args: [String]) -> Arguments {
        var positionalArguments = [String]()
        var optionalArguments = [String: String]()

        for arg in args[1..<args.count] {
            if !arg.starts(with: "-") {
                positionalArguments.append(arg)
                continue
            }

            let parts = arg.split(separator: "=", maxSplits: 1)
            let name = String(parts[0].drop(while: { $0 == "-" }))
            let value = parts.count > 1 ? String(parts[1]) : ""
            optionalArguments[name] = value
        }

        return Arguments(programName: args[0], positionalArguments: positionalArguments, optionalArguments: optionalArguments)
    }

    /// Parses a hostname and port from a string of the format "hostname:port".
    public static func parseHostPort(_ s: String) -> (String, UInt16)? {
        let parts = s.split(separator: ":")
        guard parts.count == 2 else {
            return nil
        }

        let host = String(parts[0])
        if let port = UInt16(parts[1]) {
            return (host, port)
        } else {
            return nil
        }
    }
}
