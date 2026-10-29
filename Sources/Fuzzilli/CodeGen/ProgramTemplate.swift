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

public class ProgramTemplate: Contributor {
    fileprivate let f: (ProgramBuilder) -> Void

    public init(_ name: String, _ f: @escaping (_: ProgramBuilder) -> Void) {
        self.f = f
        super.init(name: name)
    }

    public func generate(in b: ProgramBuilder) {
        f(b)
    }

    public func clone() -> ProgramTemplate {
        return ProgramTemplate(name, f)
    }
}

/// Strongly typed ProgramTemplate that can be used to differentiate templates that make use of Wasm.
public class WasmProgramTemplate: ProgramTemplate {
    public override func clone() -> WasmProgramTemplate {
        return WasmProgramTemplate(name, f)
    }
}
