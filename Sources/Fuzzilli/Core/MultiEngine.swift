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

import Foundation

/// Wraps multiple engines into one, which can be initialized given a
/// WeightedList. This can then switch engines to use, or use a more
/// complicated heuristic.
public class MultiEngine: ComponentBase, FuzzEngine {
    let engines: WeightedList<FuzzEngine>
    private var iterationCount = 0

    public init(engines: [(FuzzEngine, Int)]) {
        self.engines = WeightedList(engines)
        super.init(name: "MultiEngine")
    }

    override func initialize() {
        for engine in engines {
            engine.initialize(with: self.fuzzer)
        }
    }

    public func fuzzOne(_ group: DispatchGroup) {
        self.engines.randomElement().fuzzOne(group)
    }
}
