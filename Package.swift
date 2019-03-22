// swift-tools-version:4.2
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
    products: [
        .library(name: "Fuzzilli", targets: ["Fuzzilli"]),
    ],
    targets: [
        .target(name: "libforkserver", dependencies: []),
        .target(name: "libsocket", dependencies: []),
        .target(name: "libreprl", dependencies: []),
        .target(name: "libcoverage", dependencies: []),
        .target(name: "Fuzzilli", dependencies: ["libforkserver", "libsocket", "libreprl", "libcoverage"]),
        .target(name: "FuzzilliCli", dependencies: ["Fuzzilli"]),
    ],
    swiftLanguageVersions: [.v4_2]
)
