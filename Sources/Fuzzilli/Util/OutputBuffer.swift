// Copyright 2026 Google LLC
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

/// Helper to concurrently read from a pipe into an OutputBuffer.
func setupConcurrentRead(from pipe: Pipe, into buffer: OutputBuffer, group: DispatchGroup) {
    group.enter()
    DispatchQueue.global().async {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        buffer.append(data)
        group.leave()
    }
}

final class OutputBuffer: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()

    func append(_ newData: Data) {
        lock.lock()
        defer { lock.unlock() }
        data.append(newData)
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return data.count
    }

    var currentData: Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}
