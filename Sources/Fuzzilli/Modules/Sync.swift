// Copyright 2023 Google LLC
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

// This file specifies and implements the protocol used to coordinate multiple
// Fuzzilli instances for distributed fuzzing.
//
// For distributed fuzzing, multiple Fuzzilli instances form a tree hierarchy,
// consisting of three different types of nodes:
//   - A single root node
//   - Zero or more intermediate nodes
//   - One or more leaf nodes
//
//                                        +----------+
//                                        |          |
//                                        |   root   |
//                                        |          |
//                                        +-+-+----+-+
//                                          | |    |
//                           +--------------+ |    +--------------------------+
//                           |                |                               |
//                  +--------v-------+    +---v------------+         +--------v-------+
//                  |                |    |                |         |                |
//                  | intermediate 1 |    | intermediate 2 |         | intermediate N |
//                  |                |    |                |   ...   |                |
//                  +--+--+-----+----+    +----------------+         +----------------+
//                     |  |     |
//         +-----------+  |     +-----+
//         |              |           |
//    +----v---+   +------v-+     +---v----+
//    | leaf 1 |   | leaf 2 | ... | leaf M |      ....        ....        ....
//    +--------+   +--------+     +--------+
//
// The nodes in this tree communicate (only) with their direct parent and children. The protocol
// used for this communication is specified and implemented in this file.
//
// In general, child nodes send crashes and interesting programs upwards in the tree, while parent
// nodes deduplicate crashes and interesting programs and share their corpus with child nodes.
// As such, there are two different roles in this tree: parent nodes and child nodes. For each role,
// this file implements a Fuzzilli Module that performs the corresponding communication.
// The roles map to the above instance types as follows:
//   - The root is only a parent node
//   - The intermediate nodes are both parent and child nodes
//   - the leaf nodes are only child nodes.
//

/// The different messages supported by the distributed fuzzing protocol.
enum MessageType: UInt32 {
    // Informs the other side that the sender is terminating.
    case shutdown            = 0

    // A synchronization packet sent by a parent to a newly connected child.
    // Contains the exported state of the parent so the child can
    // synchronize itself with that.
    case sync                = 1

    // A program from a corpus import. Send from parents to children.
    // Children are expected to add this program to their corpus
    // even if it does not trigger new coverage and without minimization.
    case importedProgram     = 2

    // A program that triggered interesting behaviour and which should
    // therefore be imported by the receiver.
    case interestingProgram  = 3

    // A program that caused a crash. Only sent from a children to their parent.
    case crashingProgram     = 4

    // A statistics package send by a child to a parent node.
    case statistics          = 5

    // Log messages are forwarded from child to parent nides.
    case log                 = 6
}

/// Distributed fuzzing nodes can be configured to only share their corpus in one direction in the tree.
/// This enum lists the possible corpus synchonization modes.
public enum CorpusSynchronizationMode {
    // Only sent corpus samples to parent nodes. This way, child nodes
    // are forced to create their own corpus, potentially leading to
    // more diverse samples overall.
    case up

    // Only sent corpus samples to child nodes. May be useful when
    // importing a corpus which should be shared with child nodes.
    case down

    // Send corpus samples in both directions. If all instancesn the network use
    // this mode, then they will all operate on roughly the same corpus.
    case full

    // Don't send corpus samples to any other instance.
    case none
}

/// Common logic shared by the different nodes in distributed fuzzing.
public class DistributedFuzzingNode {
    /// Associated fuzzer instance.
    unowned let fuzzer: Fuzzer

    let logger: Logger

    /// The corpus synchronization mode used by this instance.
    let corpusSynchronizationMode: CorpusSynchronizationMode

    init(for fuzzer: Fuzzer, name: String, corpusSynchronizationMode: CorpusSynchronizationMode) {
        self.fuzzer = fuzzer
        self.logger = Logger(withLabel: name)
        self.corpusSynchronizationMode = corpusSynchronizationMode
    }

    /// Exports the internal state of this fuzzer.
    ///
    /// The state returned by this function can be passed to the synchronizeState method to restore
    /// the state. This can be used to synchronize different fuzzer instances and makes it
    /// possible to resume a previous fuzzing run at a later time.
    /// Note that for this to work, the instances need to be configured identically, i.e. use
    /// the same components (in particular, corpus) and the same build of the target engine.
    public func exportState() -> Data {
        assert(fuzzer.state != .waiting)

        do {
            if supportsFastStateSynchronization {
                let state = try Fuzzilli_Protobuf_FuzzerState.with {
                    $0.corpus = try fuzzer.corpus.exportState()
                    $0.evaluatorState = fuzzer.evaluator.exportState()
                }
                return try state.serializedData()
            } else {
                // Just export all samples in the current corpus
                return try encodeProtobufCorpus(fuzzer.corpus.allPrograms())
            }
        } catch {
            logger.error("Failed to export fuzzer state: \(error)")
            return Data()
        }
    }

    /// Set the state of this fuzzer instance to the given state.
    ///
    /// The given state must've previously been exported by exportState() above. Further, the exporting
    /// and importing instances need to be configured identically, see above.
    func synchronizeState(to data: Data) throws {
        if supportsFastStateSynchronization {
            let state = try Fuzzilli_Protobuf_FuzzerState(serializedBytes: data)
            try fuzzer.corpus.importState(state.corpus)
            try fuzzer.evaluator.importState(state.evaluatorState)
        } else {
            let corpus = try decodeProtobufCorpus(data)
            fuzzer.scheduleCorpusImport(corpus, importMode: .interestingOnly(shouldMinimize: false))
        }
    }

    /// Whether the internal state of this fuzzer instance can be serialized and restored elsewhere, e.g. on a child instance.
    private var supportsFastStateSynchronization: Bool {
        // We might eventually need to check that the other relevant components
        // (in particular the evaluator) support this as well, but currenty all
        // of them do.
        return fuzzer.corpus.supportsFastStateSynchronization
    }
}

/// A parent node in distributed fuzzing.
///
/// Parent nodes share their corpus with their child nodes and accept + deduplicate
/// crashes and newly found interesting programs from their child nodes.
public class DistributedFuzzingParentNode: DistributedFuzzingNode, Module {
    private let transport: DistributedFuzzingParentNodeTransport

    /// List of all child nodes connected to us. They are identified by their UUID.
    private var children = Set<UUID>()

    init(for fuzzer: Fuzzer, name: String, corpusSynchronizationMode: CorpusSynchronizationMode, transport: DistributedFuzzingParentNodeTransport) {
        self.transport = transport
        super.init(for: fuzzer, name: name, corpusSynchronizationMode: corpusSynchronizationMode)
        transport.setOnMessageCallback(onMessageReceived)
        transport.setOnChildConnectedCallback(onChildConnected)
        transport.setOnChildDisconnectedCallback(onChildDisconnected)
    }

    final public func initialize(with fuzzer: Fuzzer) {
        transport.initialize()

        fuzzer.registerEventListener(for: fuzzer.events.Shutdown) { _ in
            let shutdownGroup = DispatchGroup()
            for child in self.children {
                self.transport.send(.shutdown, to: child, contents: Data(), synchronizeWith: shutdownGroup)
            }
            // Attempt to make sure that the shutdown messages have been sent before continuing.
            let _ = shutdownGroup.wait(timeout: .now() + .seconds(5))
        }

        fuzzer.registerEventListener(for: fuzzer.events.Synchronized) {
            for child in self.children {
                self.sendSynchronizationMessage(to: child)
            }
        }

        fuzzer.registerEventListener(for: fuzzer.events.InterestingProgramFound) { ev in
            guard self.shouldSendCorpusSamplesToChildren() else { return }

            let proto = ev.program.asProtobuf()
            guard let payload = try? proto.serializedData() else {
                return self.logger.error("Failed to serialize program")
            }

            for child in self.children {
                if case .corpusImport = ev.origin {
                    self.transport.send(.importedProgram, to: child, contents: payload)
                } else {
                    // Don't send programs back to where they came from originally
                    if case .child(let id) = ev.origin, id == child { continue }
                    self.transport.send(.interestingProgram, to: child, contents: payload)
                }
            }
        }
    }

    private func onMessageReceived(_ messageType: MessageType, data: Data, from child: UUID) {
        switch messageType {
        case .shutdown:
            logger.info("Child node \(child) shut down")
            transport.disconnect(child)

        case .crashingProgram:
            do {
                let proto = try Fuzzilli_Protobuf_Program(serializedBytes: data)
                let program = try Program(from: proto)
                fuzzer.importCrash(program, origin: .child(id: child))
            } catch {
                logger.warning("Received malformed program from child node: \(error)")
            }

        case .interestingProgram:
            guard shouldAcceptCorpusSamplesFromChildren() else {
                logger.warning("Received corpus sample from child node but not configured to accept them (corpus synchronization mode is \(corpusSynchronizationMode)). Ignoring message.")
                return
            }

            do {
                let proto = try Fuzzilli_Protobuf_Program(serializedBytes: data)
                let program = try Program(from: proto)
                fuzzer.importProgram(program, origin: .child(id: child), enableDropout: false)
            } catch {
                logger.warning("Received malformed program from child node: \(error)")
            }

        case .statistics:
            if let data = try? Fuzzilli_Protobuf_Statistics(serializedBytes: data) {
                if let stats = Statistics.instance(for: fuzzer) {
                    stats.importData(data, from: child)
                }
            } else {
                logger.warning("Received malformed statistics update from child node")
            }

        case .log:
            if let proto = try? Fuzzilli_Protobuf_LogMessage(serializedBytes: data),
               let origin = UUID(uuidString: proto.origin),
               let level = LogLevel(rawValue: Int(clamping: proto.level)) {
                fuzzer.dispatchEvent(fuzzer.events.Log, data: (origin: origin, level: level, label: proto.label, message: proto.content))
            } else {
                logger.warning("Received malformed log message from child node")
            }

        case .importedProgram,
             .sync:
            logger.error("Received unexpected message: \(messageType)")

        }
    }

    private func onChildConnected(_ child: UUID) {
        children.insert(child)

        // Only synchronize with the child nodes if we're not ourselves waiting for a corpus
        // from our parent node. If that's the case, we'll instead send the corpus once the
        // Synchronized event is triggered, see above.
        if fuzzer.state != .waiting {
            sendSynchronizationMessage(to: child)
        }

        fuzzer.dispatchEvent(fuzzer.events.ChildNodeConnected, data: child)
    }

    private func onChildDisconnected(_ child: UUID) {
        children.remove(child)
        fuzzer.dispatchEvent(fuzzer.events.ChildNodeDisconnected, data: child)
    }

    private func sendSynchronizationMessage(to child: UUID) {
        guard shouldSendCorpusSamplesToChildren() else {
            // We're not synchronizing our corpus/state with child nodes, so just send an empty message.
            return transport.send(.sync, to: child, contents: Data())
        }

        let (state, duration) = measureTime { exportState() }
        logger.info("Encoding fuzzer state took \((String(format: "%.2f", duration)))s. Data size: \(ByteCountFormatter.string(fromByteCount: Int64(state.count), countStyle: .memory))")
        transport.send(.sync, to: child, contents: state)
    }

    private func shouldSendCorpusSamplesToChildren() -> Bool {
        return corpusSynchronizationMode == .down || corpusSynchronizationMode == .full
    }

    private func shouldAcceptCorpusSamplesFromChildren() -> Bool {
        return corpusSynchronizationMode == .up || corpusSynchronizationMode == .full
    }
}

/// The parent node transport layer. Responsible for accepting and managing connections from child nodes, and sending/receiving the raw messages.
protocol DistributedFuzzingParentNodeTransport {
    func initialize()
    func send(_ messageType: MessageType, to child: UUID, contents: Data)
    func send(_ messageType: MessageType, to child: UUID, contents: Data, synchronizeWith: DispatchGroup)
    func disconnect(_ child: UUID)

    typealias OnMessageCallback = (_ messageType: MessageType, _ data: Data, _ child: UUID) -> ()
    func setOnMessageCallback(_ callback: @escaping OnMessageCallback)
    typealias OnChildConnectedCallback = (_ child: UUID) -> ()
    func setOnChildConnectedCallback(_ callback: @escaping OnChildConnectedCallback)
    typealias OnChildDisconnectedCallback = (_ child: UUID) -> ()
    func setOnChildDisconnectedCallback(_ callback: @escaping OnChildDisconnectedCallback)
}

/// A child node in distributed fuzzing.
///
/// Child nodes initially synchronize their state with that of their parent instance.
/// Afterwards, they will send crashes and newly found interesting programs to their parent,
/// while also receiving interesting programs from it.
public class DistributedFuzzingChildNode: DistributedFuzzingNode, Module {
    private let transport: DistributedFuzzingChildNodeTransport
    private var parentIsShuttingDown = false

    init(for fuzzer: Fuzzer, name: String, corpusSynchronizationMode: CorpusSynchronizationMode, transport: DistributedFuzzingChildNodeTransport) {
        self.transport = transport
        super.init(for: fuzzer, name: name, corpusSynchronizationMode: corpusSynchronizationMode)
        transport.setOnMessageCallback(onMessageReceived)
    }

    final public func initialize(with fuzzer: Fuzzer) {
        transport.initialize()

        fuzzer.registerEventListener(for: fuzzer.events.CrashFound) { ev in
            self.sendProgram(ev.program, as: .crashingProgram)
        }

        fuzzer.registerEventListener(for: fuzzer.events.Shutdown) { _ in
            if !self.parentIsShuttingDown {
                let shutdownGroup = DispatchGroup()
                self.transport.send(.shutdown, contents: Data(), synchronizeWith: shutdownGroup)
                // Attempt to make sure that the shutdown messages have been sent before continuing.
                let _ = shutdownGroup.wait(timeout: .now() + .seconds(5))
            }
        }

        fuzzer.registerEventListener(for: fuzzer.events.InterestingProgramFound) { ev in
            guard self.shouldSendCorpusSamplesToParent() else { return }

            // If the program came from our parent node, don't send it back to it.
            if case .parent = ev.origin { return }

            // Similarly, child nodes never send programs "up" when importing a corpus.
            if case .corpusImport = ev.origin { return }

            self.sendProgram(ev.program, as: .interestingProgram)
        }

        // Regularly send local statistics to our parent node.
        if let stats = Statistics.instance(for: fuzzer) {
            fuzzer.timers.scheduleTask(every: 1 * Minutes) {
                self.sendStatistics(stats)
            }

            // Also send statistics directly after synchronization finished.
            fuzzer.registerEventListener(for: fuzzer.events.Synchronized) {
                self.sendStatistics(stats)
            }
        }

        // Forward log events to our parent node.
        fuzzer.registerEventListener(for: fuzzer.events.Log) { ev in
            let msg = Fuzzilli_Protobuf_LogMessage.with {
                $0.origin = ev.origin.uuidString
                $0.level = UInt32(ev.level.rawValue)
                $0.label = ev.label
                $0.content = ev.message
            }
            let payload = try! msg.serializedData()
            self.transport.send(.log, contents: payload)
        }
    }

    private func onMessageReceived(_ messageType: MessageType, data: Data) {
        switch messageType {

        case .shutdown:
            logger.info("Parent node is shutting down. Stopping this node...")
            parentIsShuttingDown = true
            fuzzer.shutdown(reason: .parentShutdown)

        case .sync:
            // No matter how this message is handled, we always need to signal afterwards that we're now synchronized with our parent node.
            defer { fuzzer.updateStateAfterSynchronizingWithParentNode() }

            guard shouldAcceptCorpusSamplesFromParent() else { return }

            guard !data.isEmpty else {
                return logger.warning("Received empty synchronization message. Is the parent node configured to synchronize its corpus with its children?")
            }

            guard fuzzer.state == .waiting else {
                // While child nodes will remain in the .waiting state until we've received a sync message, this can
                // still legitimately happen, for example if we imported our own corpus, or if we've lost the connection
                // to our parent node and are reconnecting to it.
                return logger.info("Not synchronizing our state with that of our parent as we already have a corpus")
            }

            let start = Date()
            do {
                try synchronizeState(to: data)
            } catch {
                logger.error("Failed to synchronize state: \(error)")
            }
            let end = Date()
            logger.info("Synchronized with parent node (took \((String(format: "%.2f", end.timeIntervalSince(start))))s). Corpus now contains \(fuzzer.corpus.size) programs")

        case .importedProgram,
             .interestingProgram:
            guard shouldAcceptCorpusSamplesFromParent() else {
                return logger.warning("Received corpus sample but not configured to accept them (corpus synchronization mode is \(corpusSynchronizationMode)). Ignoring message.")
            }

            do {
                let proto = try Fuzzilli_Protobuf_Program(serializedBytes: data)
                let program = try Program(from: proto)

                if messageType == .importedProgram {
                    // Regardless of the corpus import mode used by the parent node, as a child node we
                    // always add the program to our corpus without further checks or minimization as
                    // that will, if necessary, already have been performed by our parent node.
                    fuzzer.importProgram(program, origin: .corpusImport(mode: .full), enableDropout: true)
                } else {
                    assert(messageType == .interestingProgram)
                    fuzzer.importProgram(program, origin: .parent, enableDropout: true)
                }
            } catch {
                logger.warning("Received malformed program")
            }

        case .crashingProgram,
             .statistics,
             .log:
            logger.error("Received unexpected message: \(messageType)")
        }
    }

    private func sendProgram(_ program: Program, as type: MessageType) {
        assert(type == .interestingProgram || type == .crashingProgram)
        let proto = program.asProtobuf()
        guard let payload = try? proto.serializedData() else {
            return logger.error("Failed to serialize program")
        }
        transport.send(type, contents: payload)
    }

    private func sendStatistics(_ stats: Statistics) {
        let data = stats.compute()
        guard let payload = try? data.serializedData() else {
            return logger.error("Failed to serialize statistics")
        }
        transport.send(.statistics, contents: payload)
    }

    private func shouldSendCorpusSamplesToParent() -> Bool {
        return corpusSynchronizationMode == .up || corpusSynchronizationMode == .full
    }

    private func shouldAcceptCorpusSamplesFromParent() -> Bool {
        return corpusSynchronizationMode == .down || corpusSynchronizationMode == .full
    }
}

/// The child node transport layer. Responsible for connecting to the parent node and sending/receiving the raw messages to it/from it.
protocol DistributedFuzzingChildNodeTransport {
    func initialize()
    func send(_ messageType: MessageType, contents: Data)
    func send(_ messageType: MessageType, contents: Data, synchronizeWith: DispatchGroup)

    typealias OnMessageCallback = (_ messageType: MessageType, _ data: Data) -> ()
    func setOnMessageCallback(_ callback: @escaping OnMessageCallback)
}
