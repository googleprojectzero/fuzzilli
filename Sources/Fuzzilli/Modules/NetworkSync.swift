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
import libsocket
// Explicitly import `Foundation.UUID` to avoid the conflict with `WinSDK.UUID`
import struct Foundation.UUID

// Module for synchronizing over the network.
//
// This module implementes a simple TCP-based protocol
// to exchange programs and statistics between fuzzer
// instances.
//
// The protocol consists of messages of the following
// format being sent between the parties. Messages are
// sent in both directions and are not answered.
// Messages are padded with zero bytes to the next
// multiple of four. The message length includes the
// size of the header but excludes any padding bytes.
//
// +----------------------+----------------------+------------------+-----------+
// |        length        |         type         |     payload      |  padding  |
// | 4 byte little endian | 4 byte little endian | length - 8 bytes |           |
// +----------------------+----------------------+------------------+-----------+

/// Supported message types.
enum MessageType: UInt32 {
    // A simple ping message to keep the TCP connection alive.
    case keepalive      = 0

    // Informs the other side that the sender is terminating.
    case shutdown       = 1

    // Send by workers after connecting. Identifies a worker through a UUID.
    case identify       = 2

    // A synchronization packet sent by a master to a newly connected worker.
    // Contains the exported state of the master so the worker can
    // synchronize itself with that.
    case sync           = 3

    // A FuzzIL program that is interesting and should be imported by the receiver.
    case program        = 4

    // A crashing program that is sent from a worker to a master.
    case crash          = 5

    // A statistics package send by a worker to a master.
    case statistics     = 6

    // Log messages are forwarded from workers to masters.
    case log            = 7
}

fileprivate let messageHeaderSize = 8
fileprivate let maxMessageSize = 1024 * 1024 * 1024

/// Protocol for an object capable of receiving messages.
protocol MessageHandler {
    func handleMessage(_ payload: Data, ofType type: MessageType, from connection: Connection)
    func handleError(_ err: String, on connection: Connection)
    // The fuzzer instance on which to schedule the handler calls
    var fuzzer: Fuzzer { get }
}

/// A connection to a network peer that speaks the above protocol.
class Connection {
    /// The file descriptor on POSIX or SOCKET handle on Windows of the socket.
    let socket: libsocket.socket_t

    // Whether this connection has been closed.
    private(set) var closed = false

    /// Message handler to which incoming messages are delivered.
    private let handler: MessageHandler

    /// DispatchQueue on which data is sent to and received from the socket.
    private let queue: DispatchQueue

    /// DispatchSource to trigger when data is available.
    private var readSource: DispatchSourceRead? = nil

    /// DispatchSource to trigger when data can be sent.
    private var writeSource: DispatchSourceWrite? = nil

    /// Buffer for incoming messages. Must only be accessed on this connection's dispatch queue.
    private var currentMessageData = Data()

    /// Buffer to receive incoming data into. Must only be accessed on this connection's dispatch queue.
    private var receiveBuffer = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: 1024*1024)

    /// Pending outgoing data. Must only be accessed on this connection's dispatch queue.
    private var sendQueue: [Data] = []

    init(socket: libsocket.socket_t, handler: MessageHandler) {
        self.socket = socket
        self.handler = handler
        self.queue = DispatchQueue(label: "Socket \(socket)")

#if os(Windows)
        self.readSource = DispatchSource.makeReadSource(handle: HANDLE(bitPattern: UInt(socket))!, queue: self.queue)
#else
        self.readSource = DispatchSource.makeReadSource(fileDescriptor: socket, queue: self.queue)
#endif
        self.readSource?.setEventHandler { [weak self] in
            self?.handleDataAvailable()
        }
        self.readSource?.activate()
    }

    deinit {
        libsocket.socket_close(socket)
        receiveBuffer.deallocate()
    }

    /// Closes this connection.
    /// This does not need to be called after receiving an error, as in that case the connection will already have been closed.
    func close() {
        self.queue.sync {
            self.internalClose()
        }
    }

    /// Cancels the read and write sources and shuts down the socket.
    private func internalClose() {
        dispatchPrecondition(condition: .onQueue(queue))

        readSource?.cancel()
        readSource = nil
        writeSource?.cancel()
        writeSource = nil

        if !closed {
            libsocket.socket_shutdown(socket)
            closed = true
        }
    }

    /// Send a message.
    ///
    /// This will queue the given data for delivery as soon as the remote peer can accept more data.
    func sendMessage(_ data: Data, ofType type: MessageType, syncWith group: DispatchGroup? = nil) {
        dispatchPrecondition(condition: .notOnQueue(queue))
        group?.enter()
        self.queue.async {
            self.internalSendMessage(data, ofType: type)

            // Note: this isn't completely correct since the data might have to be queue. But it should be good enough...
            group?.leave()
        }
    }

    private func internalSendMessage(_ data: Data, ofType type: MessageType) {
        dispatchPrecondition(condition: .onQueue(queue))

        guard !closed else {
            return error("Attempted to send data on a closed connection")
        }
        guard data.count + messageHeaderSize <= maxMessageSize else {
            return error("Message too large to send (\(data.count + messageHeaderSize)B)")
        }

        var length = UInt32(data.count + messageHeaderSize).littleEndian
        var type = type.rawValue.littleEndian
        let padding = Data(repeating: 0, count: align(Int(length), to: 4))

        // We are careful not to copy the passed data here
        self.sendQueue.append(Data(bytes: &length, count: 4))
        self.sendQueue.append(Data(bytes: &type, count: 4))
        self.sendQueue.append(data)
        self.sendQueue.append(padding)

        self.sendPendingData()
    }

    private func sendPendingData() {
        dispatchPrecondition(condition: .onQueue(queue))

        var i = 0
        while i < sendQueue.count {
            let chunk = sendQueue[i]
            let length = chunk.count
            let startIndex = chunk.startIndex

            let rv = chunk.withUnsafeBytes { content -> Int in
                return libsocket.socket_send(socket, content.bindMemory(to: UInt8.self).baseAddress, length)
            }

            if rv < 0 {
                return error("Failed to send data")
            } else if rv != length {
                assert(rv < length)
                // Only managed to send part of the data. Requeue the rest.
                let newStart = startIndex.advanced(by: rv)
                sendQueue[i] = chunk[newStart...]
                break
            }

            i += 1
        }

        // Remove all chunks that were successfully sent
        sendQueue.removeFirst(i)

        // If we were able to send all chunks, remove the writer source
        if sendQueue.isEmpty {
            writeSource?.cancel()
            writeSource = nil
        } else if writeSource == nil {
            // Otherwise ensure we have an active write source to notify us when the next chunk can be sent
#if os(Windows)
            writeSource = DispatchSource.makeWriteSource(handle: HANDLE(bitPattern: UInt(socket))!, queue: self.queue)
#else
            writeSource = DispatchSource.makeWriteSource(fileDescriptor: socket, queue: self.queue)
#endif
            writeSource?.setEventHandler { [weak self] in
                self?.sendPendingData()
            }
            writeSource?.activate()
        }
    }

    private func handleDataAvailable() {
        dispatchPrecondition(condition: .onQueue(queue))

        // Receive all available data
        var numBytesRead = 0
        var gotData = false
        repeat {
            numBytesRead = socket_recv(socket, receiveBuffer.baseAddress, receiveBuffer.count)
            if numBytesRead > 0 {
                gotData = true
                currentMessageData.append(receiveBuffer.baseAddress!, count: numBytesRead)
            }
        } while numBytesRead > 0

        guard gotData else {
            // We got a read event but no data was available so the remote end must have closed the connection.
            return error("Connection closed by peer")
        }

        // ... and process it
        while currentMessageData.count >= messageHeaderSize {
            let length = Int(readUint32(from: currentMessageData, atOffset: 0))

            guard length <= maxMessageSize && length >= messageHeaderSize else {
                // For now we just close the connection if an invalid message is received.
                return error("Received message with invalid length")
            }

            let totalMessageLength = length + align(length, to: 4)
            guard totalMessageLength <= currentMessageData.count else {
                // Not enough data available right now. Wait until next packet is received.
                break
            }

            let message = Data(currentMessageData.prefix(length))
            // Explicitely make a copy of the data here so the discarded data is also freed from memory
            currentMessageData = currentMessageData.subdata(in: totalMessageLength..<currentMessageData.count)

            let type = readUint32(from: message, atOffset: 4)
            if let type = MessageType(rawValue: type) {
                let payload = message.suffix(from: messageHeaderSize)
                handler.fuzzer.async {
                    self.handler.handleMessage(payload, ofType: type, from: self)
                }
            } else {
                return error("Received message with invalid type")
            }
        }
    }

    /// Handle an error: close the connection and inform our handler.
    /// Must execute on the connection's dispatch queue.
    private func error(_ err: String = "") {
        internalClose()
        handler.fuzzer.async {
            self.handler.handleError(err, on: self)
        }
    }

    /// Helper function to unpack a little-endian, 32-bit unsigned integer from a data packet.
    private func readUint32(from data: Data, atOffset offset: Int) -> UInt32 {
        assert(offset >= 0 && data.count >= offset + 4)
        let value = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt32.self) }
        return UInt32(littleEndian: value)
    }
}

public enum NetworkCorpusSynchronizationMode {
    // Only sent corpus samples to master instances. This way, workers
    // are forced to create their own corpus, potentially leading to
    // more diverse samples overall.
    case up
    // Only sent corpus samples to worker instances. May be useful
    // when importing a corpus at a master instance which should be
    // shared with workers.
    case down
    // Send corpus samples to both workers and masters. If all instances
    // in the network use this mode, then they will all operate on roughly
    // the same corpus.
    case full
    // Don't send corpus samples to any other instance.
    case none
}

public class NetworkMaster: Module, MessageHandler {
    /// File descriptor or SOCKET handle of the server socket.
    private var serverFd: libsocket.socket_t = INVALID_SOCKET

    /// Associated fuzzer.
    unowned let fuzzer: Fuzzer

    /// Logger for this module.
    private let logger: Logger

    /// Address and port on which the master listens.
    let address: String
    let port: UInt16

    /// Dispatch source to trigger when a new client connection is available.
    private var connectionSource: DispatchSourceRead? = nil
    /// DispatchQueue on which to accept client connections
    private var serverQueue: DispatchQueue? = nil

    /// Active workers. The key is the socket filedescriptor number.
    private var workers = [libsocket.socket_t: Worker]()

    /// The corpus synchronization mode used by this instance.
    private let corpusSynchronizationMode: NetworkCorpusSynchronizationMode

    /// Since fuzzer state can grow quite large (> 100MB) and takes long to serialize,
    /// we cache the serialized state for a short time.
    private var cachedState = Data()
    private var cachedStateCreationTime = Date.distantPast

    public init(for fuzzer: Fuzzer, address: String, port: UInt16, corpusSynchronizationMode: NetworkCorpusSynchronizationMode) {
        self.fuzzer = fuzzer
        self.logger = Logger(withLabel: "NetworkMaster")
        self.address = address
        self.port = port
        self.corpusSynchronizationMode = corpusSynchronizationMode
    }

    public func initialize(with fuzzer: Fuzzer) {
        assert(self.fuzzer === fuzzer)

        self.serverFd = libsocket.socket_listen(address, port)
        guard serverFd > 0 else {
            logger.fatal("Failed to open server socket")
        }

        self.serverQueue = DispatchQueue(label: "Server Queue \(serverFd)")
#if os(Windows)
        self.connectionSource = DispatchSource.makeReadSource(handle: HANDLE(bitPattern: UInt(serverFd))!, queue: serverQueue)
#else
        self.connectionSource = DispatchSource.makeReadSource(fileDescriptor: serverFd, queue: serverQueue)
#endif
        self.connectionSource?.setEventHandler {
            let socket = libsocket.socket_accept(self.serverFd)
            fuzzer.async {
                self.handleNewConnection(socket)
            }
        }
        connectionSource?.activate()

        logger.info("Accepting worker connections on \(address):\(port)")

        fuzzer.registerEventListener(for: fuzzer.events.Shutdown) { _ in
            let shutdownGroup = DispatchGroup()
            for worker in self.workers.values {
                worker.conn.sendMessage(Data(), ofType: .shutdown, syncWith: shutdownGroup)
            }
            // Attempt to make sure that the shutdown messages have been sent before continuing.
            let _ = shutdownGroup.wait(timeout: .now() + .seconds(5))
        }

        fuzzer.registerEventListener(for: fuzzer.events.InterestingProgramFound) { ev in
            guard self.shouldSendCorpusSamplesToWorkers() else { return }

            let proto = ev.program.asProtobuf()
            guard let data = try? proto.serializedData() else {
                return self.logger.error("Failed to serialize program")
            }

            for worker in self.workers.values {
                guard let workerId = worker.id else { continue }
                // Don't send programs back to where they came from originally
                if case .worker(let id) = ev.origin, id == workerId { continue }
                worker.conn.sendMessage(data, ofType: .program)
            }
        }

        // Regularly send keepalive messages.
        fuzzer.timers.scheduleTask(every: 1 * Minutes) {
            for worker in self.workers.values {
                worker.conn.sendMessage(Data(), ofType: .keepalive)
            }
        }
    }

    func handleMessage(_ payload: Data, ofType type: MessageType, from connection: Connection) {
        if let worker = workers[connection.socket] {
            handleMessageInternal(payload, ofType: type, from: worker)
        }
    }

    func handleError(_ err: String, on connection: Connection) {
        // In case the worker isn't known, we probably already disconnected it, so there's nothing to do.
        if let worker = workers[connection.socket] {
            logger.warning("Error on connection \(connection.socket): \(err). Disconnecting client.")
            if let id = worker.id {
                let activeSeconds = Int(-worker.connectionTime.timeIntervalSinceNow)
                let activeMinutes = activeSeconds / 60
                let activeHours = activeMinutes / 60
                logger.warning("Lost connection to worker \(id). Worker was active for \(activeHours)h \(activeMinutes % 60)m \(activeSeconds % 60)s")
            }
            disconnect(worker)
        }
    }

    private func handleNewConnection(_ socket: libsocket.socket_t) {
        guard socket > 0 else {
            return logger.error("Failed to accept client connection")
        }

        let worker = Worker(conn: Connection(socket: socket, handler: self), id: nil, connectionTime: Date())
        workers[socket] = worker

        logger.info("New worker connected")
    }

    private func handleMessageInternal(_ payload: Data, ofType type: MessageType, from worker: Worker) {
        // Workers must identify themselves first.
        if type != .identify && worker.id == nil {
            logger.warning("Received message from unidentified worker. Closing connection...")
            return disconnect(worker)
        }

        switch type {
        case .keepalive:
            break

        case .shutdown:
            if let id = worker.id {
                logger.info("Worker \(id) shut down")
            }
            disconnect(worker)

        case .identify:
            guard let proto = try? Fuzzilli_Protobuf_Identification(serializedData: payload), let uuid = UUID(uuidData: proto.uuid) else {
                logger.warning("Received malformed identification message from worker")
                break
            }

            guard worker.id == nil else {
                logger.warning("Received multiple identification messages from client. Ignoring message")
                break
            }
            workers[worker.conn.socket] = Worker(conn: worker.conn, id: uuid, connectionTime: worker.connectionTime)

            logger.info("Worker identified as \(uuid)")
            fuzzer.dispatchEvent(fuzzer.events.WorkerConnected, data: uuid)

            guard shouldSendCorpusSamplesToWorkers() else {
                // We're not synchronizing our corpus/state with workers, so just send an empty message.
                worker.conn.sendMessage(Data(), ofType: .sync)
                break
            }

            // Send our fuzzing state to the worker
            let now = Date()
            if cachedState.isEmpty || now.timeIntervalSince(cachedStateCreationTime) > 15 * Minutes {
                // No cached state or it is too old. Recreate it.
                let (maybeState, duration) = measureTime { try? fuzzer.exportState() }
                if let state = maybeState {
                    logger.info("Encoding fuzzer state took \((String(format: "%.2f", duration)))s. Data size: \(ByteCountFormatter.string(fromByteCount: Int64(state.count), countStyle: .memory))")
                    cachedState = state
                    cachedStateCreationTime = now
                } else {
                    logger.error("Failed to export fuzzer state")
                }
            }
            worker.conn.sendMessage(cachedState, ofType: .sync)

        case .crash:
            do {
                let proto = try Fuzzilli_Protobuf_Program(serializedData: payload)
                let program = try Program(from: proto)
                fuzzer.importCrash(program, origin: .worker(id: worker.id!))
            } catch {
                logger.warning("Received malformed program from worker: \(error)")
            }

        case .program:
            guard shouldAcceptCorpusSamplesFromWorkers() else {
                logger.warning("Received corpus sample from worker but not configured to accept them (corpus synchronization mode is \(corpusSynchronizationMode)). Ignoring message.")
                return
            }

            do {
                let proto = try Fuzzilli_Protobuf_Program(serializedData: payload)
                let program = try Program(from: proto)
                fuzzer.importProgram(program, enableDropout: false, origin: .worker(id: worker.id!))
            } catch {
                logger.warning("Received malformed program from worker: \(error)")
            }

        case .statistics:
            if let data = try? Fuzzilli_Protobuf_Statistics(serializedData: payload) {
                if let stats = Statistics.instance(for: fuzzer) {
                    stats.importData(data, from: worker.id!)
                }
            } else {
                logger.warning("Received malformed statistics update from worker")
            }

        case .log:
            if let proto = try? Fuzzilli_Protobuf_LogMessage(serializedData: payload),
                let origin = UUID(uuidString: proto.origin),
                let level = LogLevel(rawValue: Int(clamping: proto.level)) {
                fuzzer.dispatchEvent(fuzzer.events.Log, data: (origin: origin, level: level, label: proto.label, message: proto.content))
            } else {
                logger.warning("Received malformed log message data from worker")
            }

        default:
            logger.warning("Received unexpected packet from worker")
        }
    }


    private func disconnect(_ worker: Worker) {
        worker.conn.close()
        if let id = worker.id {
            // If the id is nil then the worker never registered, so no need to deregister it internally
            fuzzer.dispatchEvent(fuzzer.events.WorkerDisconnected, data: id)
        }
        workers.removeValue(forKey: worker.conn.socket)
    }

    private func shouldSendCorpusSamplesToWorkers() -> Bool {
        return corpusSynchronizationMode == .down || corpusSynchronizationMode == .full
    }

    private func shouldAcceptCorpusSamplesFromWorkers() -> Bool {
        return corpusSynchronizationMode == .up || corpusSynchronizationMode == .full
    }

    private struct Worker {
        // The network connection to the worker.
        let conn: Connection

        // The id of the worker.
        let id: UUID?

        // The time the worker connected.
        let connectionTime: Date
    }
}

public class NetworkWorker: Module, MessageHandler {
    /// Associated fuzzer.
    unowned let fuzzer: Fuzzer

    /// Logger for this module.
    private let logger: Logger

    /// Hostname of the master instance.
    let masterHostname: String

    /// Port of the master instance.
    let masterPort: UInt16

    /// Indicates whether the corpus has been synchronized with the master yet.
    private var synchronized = false

    /// Used when receiving a shutdown message from the master to avoid sending it further data.
    private var masterIsShuttingDown = false

    /// The corpus synchronization mode used by this instance.
    private let corpusSynchronizationMode: NetworkCorpusSynchronizationMode

    /// Connection to the master instance.
    private var conn: Connection! = nil

    public init(for fuzzer: Fuzzer, hostname: String, port: UInt16, corpusSynchronizationMode: NetworkCorpusSynchronizationMode) {
        self.fuzzer = fuzzer
        self.logger = Logger(withLabel: "NetworkWorker")
        self.masterHostname = hostname
        self.masterPort = port
        self.corpusSynchronizationMode = corpusSynchronizationMode
    }

    public func initialize(with fuzzer: Fuzzer) {
        assert(self.fuzzer === fuzzer)

        connect()

        fuzzer.registerEventListener(for: fuzzer.events.CrashFound) { ev in
            self.sendProgram(ev.program, type: .crash)
        }

        fuzzer.registerEventListener(for: fuzzer.events.Shutdown) { _ in
            if !self.masterIsShuttingDown {
                let shutdownGroup = DispatchGroup()
                self.conn.sendMessage(Data(), ofType: .shutdown, syncWith: shutdownGroup)
                // Attempt to make sure that the shutdown messages have been sent before continuing.
                let _ = shutdownGroup.wait(timeout: .now() + .seconds(5))
            }
        }

        fuzzer.registerEventListener(for: fuzzer.events.InterestingProgramFound) { ev in
            guard self.shouldSendCorpusSamplesToMaster() else { return }

            if self.synchronized {
                // If the program came from the master instance, don't send it back to it :)
                if case .master = ev.origin { return }
                self.sendProgram(ev.program, type: .program)
            }
        }

        // Regularly send local statistics to the master.
        if let stats = Statistics.instance(for: fuzzer) {
            fuzzer.timers.scheduleTask(every: 1 * Minutes) {
                let data = stats.compute()
                if let payload = try? data.serializedData() {
                    self.conn.sendMessage(payload, ofType: .statistics)
                }
            }
        }

        // Forward log events to the master.
        fuzzer.registerEventListener(for: fuzzer.events.Log) { ev in
            let msg = Fuzzilli_Protobuf_LogMessage.with {
                $0.origin = ev.origin.uuidString
                $0.level = UInt32(ev.level.rawValue)
                $0.label = ev.label
                $0.content = ev.message
            }
            let payload = try! msg.serializedData()
            self.conn.sendMessage(payload, ofType: .log)
        }

        // Set a timeout for synchronization.
        fuzzer.timers.runAfter(60 * Minutes) {
            if !self.synchronized {
                self.logger.error("Synchronization with master timed out. Continuing without synchronizing...")
                self.synchronized = true
            }
        }
    }

    func handleMessage(_ payload: Data, ofType type: MessageType, from connection: Connection) {
        switch type {
        case .keepalive:
            break

        case .shutdown:
            logger.info("Master is shutting down. Stopping this worker...")
            masterIsShuttingDown = true
            self.fuzzer.shutdown(reason: .masterShutdown)

        case .program:
            guard shouldAcceptCorpusSamplesFromMaster() else {
                logger.warning("Received corpus sample from master but not configured to accept them (corpus synchronization mode is \(corpusSynchronizationMode)). Ignoring message.")
                break
            }

            do {
                let proto = try Fuzzilli_Protobuf_Program(serializedData: payload)
                let program = try Program(from: proto)
                // Dropout can, if enabled in the fuzzer config, help workers become more independent
                // from the rest of the fuzzers by forcing them to rediscover edges in different ways.
                fuzzer.importProgram(program, enableDropout: true, origin: .master)
            } catch {
                logger.warning("Received malformed program from master")
            }

        case .sync:
            synchronized = true

            guard shouldAcceptCorpusSamplesFromMaster() else { break }

            guard !payload.isEmpty else {
                logger.warning("Received empty synchronization message from master. Is the master configured to synchronize its corpus with workers?")
                break
            }

            let start = Date()
            do {
                try fuzzer.importState(from: payload)
            } catch {
                logger.error("Failed to import state from master: \(error)")
            }
            let end = Date()
            logger.info("Decoding fuzzer state took \((String(format: "%.2f", end.timeIntervalSince(start))))s")
            logger.info("Synchronized with master. Corpus now contains \(fuzzer.corpus.size) programs")

        default:
            logger.warning("Received unexpected packet from master")
        }
    }

    func handleError(_ err: String, on connection: Connection) {
        logger.warning("Error on connection to master instance: \(err). Trying to reconnect to master...")
        connect()
    }

    private func connect() {
        var fd: libsocket.socket_t = INVALID_SOCKET
        for _ in 0..<10 {
            fd = libsocket.socket_connect(masterHostname, masterPort)
            if fd != INVALID_SOCKET {
                break
            }
            logger.warning("Failed to connect to master. Retrying in 30 seconds")
            Thread.sleep(forTimeInterval: 30)
        }
        if fd == INVALID_SOCKET {
            logger.fatal("Failed to connect to master")
        }

        logger.info("Connected to master, our id: \(fuzzer.id)")
        conn = Connection(socket: fd, handler: self)

        // Identify ourselves.
        let msg = Fuzzilli_Protobuf_Identification.with { $0.uuid = fuzzer.id.uuidData }
        let payload = try! msg.serializedData()
        conn.sendMessage(payload, ofType: .identify)
    }

    private func sendProgram(_ program: Program, type: MessageType) {
        assert(type == .program || type == .crash)
        let proto = program.asProtobuf()
        guard let data = try? proto.serializedData() else {
            return logger.error("Failed to serialize program")
        }
        conn.sendMessage(data, ofType: type)
    }

    private func shouldSendCorpusSamplesToMaster() -> Bool {
        return corpusSynchronizationMode == .up || corpusSynchronizationMode == .full
    }

    private func shouldAcceptCorpusSamplesFromMaster() -> Bool {
        return corpusSynchronizationMode == .down || corpusSynchronizationMode == .full
    }
}
