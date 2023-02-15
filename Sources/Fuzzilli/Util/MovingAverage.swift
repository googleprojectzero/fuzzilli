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

/// Computes the average of some value over the last N samples.
struct MovingAverage {
    private let n: Int
    private var lastN: [Double]
    private var sum = 0.0
    private var oldest = 0
    private var seen = 0

    var currentValue: Double {
        guard seen > 0 else { return 0.0 }
        return sum / Double(min(seen, n))
    }

    init(n: Int) {
        assert(n > 0)
        self.n = n
        lastN = [Double](repeating: 0, count: n)
    }

    mutating func add(_ value: Double) {
        seen += 1

        sum -= lastN[oldest]
        lastN[oldest] = value
        sum += value

        oldest = (oldest + 1) % n
    }

    mutating func add(_ value: Int) {
        add(Double(value))
    }
}
