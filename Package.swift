// swift-tools-version:5.0
//
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

import PackageDescription

let package = Package(
    name: "Fuzzilli",
    platforms: [
        .macOS(.v10_13),
    ],
    products: [
        .library(name: "Fuzzilli", targets: ["Fuzzilli"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.6.0"),
    ],
    targets: [
        .target(name: "libsocket", dependencies: []),
        .target(name: "libreprl", dependencies: []),
        .target(name: "libcoverage", dependencies: [], linkerSettings: [.linkedLibrary("rt", .when(platforms: [.linux]))]),
        .target(name: "Fuzzilli", dependencies: ["SwiftProtobuf", "libsocket", "libreprl", "libcoverage", "JS"]),
        .target(name: "REPRLRun", dependencies: ["libreprl"]),
        .target(name: "FuzzilliCli", dependencies: ["Fuzzilli"]),
        .target(name: "JS", dependencies: []),
        .target(name: "FuzzILTool", dependencies: ["Fuzzilli"]),

        .testTarget(name: "FuzzilliTests", dependencies: ["Fuzzilli"]),
    ],
    swiftLanguageVersions: [.v5]
)
