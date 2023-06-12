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

import Foundation

//
// Implementation of the distributed fuzzing protocol for synchronizing instances within the same process.
//

public class ThreadParent: DistributedFuzzingParentNode {
    fileprivate let transport: Transport

    public init(for fuzzer: Fuzzer) {
        self.transport = Transport(for: fuzzer)
        super.init(for: fuzzer, name: "ThreadParent", corpusSynchronizationMode: .full, transport: transport)
    }

    fileprivate class Transport: DistributedFuzzingParentNodeTransport {
        private let fuzzer: Fuzzer

        private let logger = Logger(withLabel: "ThreadParentTransport")

        private var clients: [UUID: Fuzzer] = [:]

        /// Used to ensure that all child nodes have shut down before this node terminates.
        private let shutdownGroup = DispatchGroup()

        // The other side simply directly invokes this callback.
        fileprivate var onMessageCallback: OnMessageCallback? = nil
        // This callback is invoked by this class.
        private var onChildConnectedCallback: OnChildConnectedCallback? = nil

        init(for fuzzer: Fuzzer) {
            self.fuzzer = fuzzer
        }

        func initialize() {
            fuzzer.registerEventListener(for: fuzzer.events.ShutdownComplete) { _ in
                self.shutdownGroup.wait()
            }
        }

        func registerClient(_ client: Fuzzer) {
            client.async {
                self.shutdownGroup.enter()
                client.registerEventListener(for: client.events.ShutdownComplete) { _ in
                    self.shutdownGroup.leave()
                    // The parent is responsible for terminating the process, so just sleep here now.
                    while true { Thread.sleep(forTimeInterval: 60) }
                }
            }

            clients[client.id] = client
            onChildConnectedCallback?(client.id)
        }

        func send(_ messageType: MessageType, to child: UUID, contents: Data) {
            guard let client = clients[child] else {
                fatalError("Unknown child node \(child)")
            }
            client.async {
                guard let module = ThreadChild.instance(for: client) else { fatalError("No active ThreadChild module on client instance") }
                module.transport.onMessageCallback?(messageType, contents)
            }
        }

        func send(_ messageType: MessageType, to child: UUID, contents: Data, synchronizeWith synchronizationGroup: DispatchGroup) {
            send(messageType, to: child, contents: contents)
        }

        func disconnect(_ child: UUID) {
            // This should only happen if the child encountered a fatal error or something like that, in which case we probably
            // want to terminate the whole fuzzing session since the child cannot continue fuzzing.
            logger.fatal("Child node \(child) unexpectedly terminated")
        }

        func setOnMessageCallback(_ callback: @escaping OnMessageCallback) {
            assert(onMessageCallback == nil)
            onMessageCallback = callback
        }

        func setOnChildConnectedCallback(_ callback: @escaping OnChildConnectedCallback) {
            assert(onChildConnectedCallback == nil)
            onChildConnectedCallback = callback
        }

        func setOnChildDisconnectedCallback(_ callback: @escaping OnChildDisconnectedCallback) {
            // We don't use this callback.
        }
    }
}

public class ThreadChild: DistributedFuzzingChildNode {
    fileprivate let transport: Transport

    public init(for fuzzer: Fuzzer, parent: Fuzzer) {
        self.transport = Transport(child: fuzzer, parent: parent)
        super.init(for: fuzzer, name: "ThreadChild", corpusSynchronizationMode: .full, transport: transport)
    }

    fileprivate class Transport: DistributedFuzzingChildNodeTransport {
        private let child: Fuzzer
        private let parent: Fuzzer
        private var parentModule: ThreadParent! = nil

        // The other side simply directly invokes this callback.
        fileprivate var onMessageCallback: OnMessageCallback? = nil

        init(child: Fuzzer, parent: Fuzzer) {
            self.child = child
            self.parent = parent
        }

        func initialize() {
            guard let parentModule = ThreadParent.instance(for: parent) else {
                fatalError("No active ThreadParent module on parent instance")
            }
            self.parentModule = parentModule

            parent.async {
                self.parentModule.transport.registerClient(self.child)
            }
        }

        func send(_ messageType: MessageType, contents: Data) {
            let ourId = child.id
            parent.async {
                self.parentModule.transport.onMessageCallback?(messageType, contents, ourId)
            }
        }

        func send(_ messageType: MessageType, contents: Data, synchronizeWith: DispatchGroup) {
            send(messageType, contents: contents)
        }

        func setOnMessageCallback(_ callback: @escaping OnMessageCallback) {
            assert(onMessageCallback == nil)
            onMessageCallback = callback
        }
    }
}
