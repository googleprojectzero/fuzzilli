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
public enum TypeCollectionStatus: Equatable {
    case success
    case error
    case timeout
    case notAttempted

    public init(from typeCollectionOutcome: ExecutionOutcome){
        switch typeCollectionOutcome {
            case .crashed: self = .error
            case .failed: self = .error
            case .succeeded: self = .success
            case .timedOut: self = .timeout
        }
    }

    public init(rawValue: Int) {
        switch rawValue {
            case 0: self = .success
            case 1: self = .error
            case 2: self = .timeout
            case 3: self = .notAttempted
            default: self = .notAttempted
        }
    }

    public var rawValue: Int {
        switch self {
            case .success: return 0
            case .error: return 1
            case .timeout: return 2
            case .notAttempted: return 3
        }
    }
}
