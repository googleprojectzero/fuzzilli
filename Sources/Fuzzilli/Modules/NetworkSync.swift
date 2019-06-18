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

/// Module for synchronizing over the network.
///
/// This module implementes a simple TCP-based protocol
/// to exchange programs and statistics between fuzzer
/// instances.
///
/// The protocol consists of messages of the following
/// format being sent between the parties. Messages are
/// sent in both directions and are not answered.
/// Messages are padded with zero bytes to the next
/// multiple of four. The message length includes the
/// size of the header but excludes any padding bytes.
///
/// +----------------------+----------------------+------------------+-----------+
/// |        length        |         type         |     payload      |  padding  |
/// | 4 byte little endian | 4 byte little endian | length - 8 bytes |           |
/// +----------------------+----------------------+------------------+-----------+
///
/// TODO: add some kind of compression, encryption, and authentication...

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
    
    /// Log messages are forwarded from workers to masters.
    case log            = 7
}

/// Payload of an identification message.
fileprivate struct Identification: Codable {
    // The UUID of the worker
    let workerId: UUID
}

/// Payload of a log message.
fileprivate struct LogMessage: Codable {
    let creator: UUID
    let level: Int
    let label: String
    let content: String
}

fileprivate let messageHeaderSize = 8
fileprivate let maxMessageSize = 1024 * 1024 * 1024

/// Protocol for an object capable of receiving messages.
protocol MessageHandler {
    func handleMessage(_ payload: Data, ofType type: MessageType, from connection: Connection)
    func handleError(on connection: Connection)
}

/// A connection to a network peer that speaks the above protocol.
class Connection {
    /// File descriptor of the socket.
    let socket: Int32
    
    /// Logger for this connection.
    private let logger: Logger
    
    /// Message handler to which incoming messages are delivered.
    private let handler: MessageHandler
    
    /// OperationQueue on which messages will be received and handlers invoked.
    private let queue: OperationQueue
    
    /// DispatchSource to trigger when data is available.
    private var readSource: OperationSource? = nil
    
    /// DispatchSource to trigger when data can be sent.
    private var writeSource: OperationSource? = nil
    
    /// Buffer for incoming messages.
    private var currentMessageData = Data()
    
    /// Buffer to receive incoming data into.
    private var receiveBuffer = [UInt8](repeating: 0, count: 1024 * 1024)
    
    /// Pending outgoing data.
    private var sendQueue: [Data] = []
    
    init(socket: Int32, handler: MessageHandler, fuzzer: Fuzzer) {
        self.socket = socket
        self.handler = handler
        self.logger = fuzzer.makeLogger(withLabel: "Connection \(socket)")
        self.queue = fuzzer.queue
        
        self.readSource = OperationSource.forReading(from: socket, on: fuzzer.queue) { [weak self] in
            self?.handleDataAvailable()
        }
    }
    
    deinit {
        libsocket.socket_close(socket)
    }
    
    func close() {
        readSource?.cancel()
        writeSource?.cancel()
    }
    
    /// Send a message.
    ///
    /// This will either send the message immediately or queue for delivery
    /// once the remote peer can accept more data.
    func sendMessage(_ data: Data, ofType type: MessageType) {
        guard data.count + messageHeaderSize <= maxMessageSize else {
            return logger.error("Message too large to be sent (\(data.count + messageHeaderSize)B). Discarding")
        }
        
        var length = UInt32(data.count + messageHeaderSize).littleEndian
        var type = type.rawValue.littleEndian
        let padding = Data(repeating: 0, count: self.paddingLength(for: Int(length)))
   
        // We are careful not to copy the passed data here
        self.sendQueue.append(Data(bytes: &length, count: 4))
        self.sendQueue.append(Data(bytes: &type, count: 4))
        self.sendQueue.append(data)
        self.sendQueue.append(padding)
        
        self.sendPendingData()
    }
    
    private func sendPendingData() {
        var i = 0
        while i < sendQueue.count {
            let chunk = sendQueue[i]
            let length = chunk.count
            let startIndex = chunk.startIndex
            
            let rv = chunk.withUnsafeBytes { content -> Int in
                return libsocket.socket_send(socket, content.bindMemory(to: UInt8.self).baseAddress, length)
            }
            
            if rv < 0 {
                // Network error. We'll notify our client through handleDataAvailable though.
                // That way we can deliver any data that's still pending at this point.
                // Note (probably) this doesn't work correctly if the remote end just closes
                // the socket in one direction, but that shouldn't happen in our implementation ...
                sendQueue.removeAll()
                writeSource?.cancel()
                return
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
        
        // If we were able to sent all chunks, remove the writer source
        if sendQueue.isEmpty {
            writeSource?.cancel()
            writeSource = nil
        } else if writeSource == nil {
            // Otherwise ensure we have an active write source to notify us when the next chunk can be sent
            self.writeSource = OperationSource.forWriting(to: socket, on: queue) { [weak self] in
                self?.sendPendingData()
            }
        }
    }
    
    private func handleDataAvailable() {
        // Receive all available data
        var receivedData = Data()
        while true {
            let bytesRead = read(socket, UnsafeMutablePointer<UInt8>(&receiveBuffer), receiveBuffer.count)
            guard bytesRead > 0 else {
                break
            }
            receivedData.append(UnsafeMutablePointer<UInt8>(&receiveBuffer), count: Int(bytesRead))
        }
        
        guard receivedData.count > 0 else {
            // We got a read event but no data was available so the remote end must have closed the connection.
            return error()
        }
        
        currentMessageData.append(receivedData)
        
        // ... and process it
        while currentMessageData.count >= messageHeaderSize {
            let length = Int(readUint32(from: currentMessageData, atOffset: 0))
            
            guard length <= maxMessageSize && length >= messageHeaderSize else {
                // For now we just close the connection if an invalid message is received.
                logger.warning("Received message with invalid length. Closing connection.")
                return error()
            }
            
            guard length + paddingLength(for: length) <= currentMessageData.count else {
                // Not enough data available right now. Wait until next packet is received.
                break
            }
            
            let message = Data(currentMessageData.prefix(length))
            currentMessageData.removeFirst(length + paddingLength(for: length))
            
            let type = readUint32(from: message, atOffset: 4)
            if let type = MessageType(rawValue: type) {
                let payload = message.suffix(from: messageHeaderSize)
                handler.handleMessage(payload, ofType: type, from: self)
            } else {
                logger.warning("Received message with invalid type. Closing connection.")
                return error()
            }
        }
    }
    
    // Handle an error: close our connection and inform our handler.
    private func error() {
        close()
        handler.handleError(on: self)
    }
    
    // Helper function to unpack a little-endian, 32-bit unsigned integer from a data packet.
    private func readUint32(from data: Data, atOffset offset: Int) -> UInt32 {
        assert(offset >= 0 && data.count >= offset + 4)
        let value = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: UInt32.self) }
        return UInt32(littleEndian: value)
    }
    
    // Compute the number of padding bytes for the given message size.
    private func paddingLength(for messageSize: Int) -> Int {
        let remainder = messageSize % 4
        return remainder == 0 ? 0 : 4 - remainder
    }
}

public class NetworkMaster: Module, MessageHandler {
    /// File descriptor of the server socket.
    private var serverFd: Int32 = -1
    
    /// Associated fuzzer.
    private unowned let fuzzer: Fuzzer
    
    /// Logger for this module.
    private let logger: Logger
    
    /// Address and port on which the master listens.
    let address: String
    let port: UInt16
    
    /// Operation source to trigger when a new client connection is available.
    private var connectionSource: OperationSource? = nil
    
    /// Active workers. The key is the socket filedescriptor number.
    private var workers = [Int32: Worker]()
    
    /// Since fuzzer state can grow quite large (> 100MB) and takes long to serialize,
    /// we cache the serialized state for a short time.
    private var cachedState = Data()
    private var cachedStateCreationTime = Date.distantPast
    
    public init(for fuzzer: Fuzzer, address: String, port: UInt16) {
        self.fuzzer = fuzzer
        self.logger = fuzzer.makeLogger(withLabel: "NetworkMaster")
        self.address = address
        self.port = port
    }
    
    public func initialize(with fuzzer: Fuzzer) {
        self.serverFd = libsocket.socket_listen(address, port)
        guard serverFd > 0 else {
            logger.fatal("Failed to open server socket")
        }
        
        connectionSource = OperationSource.forReading(from: serverFd, on: fuzzer.queue, block: handleNewConnection)
        
        logger.info("Accepting worker connections on \(address):\(port)")
        
        fuzzer.events.Shutdown.observe {
            for worker in self.workers.values {
                worker.conn.sendMessage(Data(), ofType: .shutdown)
            }
        }
        
        // Only start sending interesting programs after a short delay to not spam the workers too much.
        fuzzer.timers.runAfter(10 * Minutes) {
            fuzzer.events.InterestingProgramFound.observe { ev in
                let encoder = JSONEncoder()
                let data = try! encoder.encode(ev.program)
                for worker in self.workers.values {
                    worker.conn.sendMessage(data, ofType: .program)
                }
            }
        }
        
        // Regularly send keepalive messages.
        fuzzer.timers.scheduleTask(every: 1 * Minutes) {
            for worker in self.workers.values {
                worker.conn.sendMessage(Data(), ofType: .keepalive)
            }
        }
    }
    
    func handleNewConnection() {
        let clientFd = libsocket.socket_accept(serverFd)
        guard clientFd > 0 else {
            return logger.error("Failed to accept client connection")
        }
        
        let worker = Worker(conn: Connection(socket: clientFd, handler: self, fuzzer: fuzzer), id: nil, connectionTime: Date())
        workers[clientFd] = worker
        
        // TODO should have some address information here.
        logger.info("New worker connected")
    }
    
    func handleMessage(_ payload: Data, ofType type: MessageType, from connection: Connection) {
        if let worker = workers[connection.socket] {
            handleMessageInternal(payload, ofType: type, from: worker)
        }
    }
    
    private func handleMessageInternal(_ payload: Data, ofType type: MessageType, from worker: Worker) {
        let decoder = JSONDecoder()
        
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
                logger.info("Worker \(id) disconnected")
            }
            disconnect(worker)
            
        case .identify:
            if let msg = try? decoder.decode(Identification.self, from: payload) {
                if worker.id != nil {
                    logger.warning("Received multiple identification messages from client. Ignoring message")
                    break
                }
                workers[worker.conn.socket] = Worker(conn: worker.conn, id: msg.workerId, connectionTime: worker.connectionTime)
                
                logger.info("Worker identified as \(msg.workerId)")
                fuzzer.events.WorkerConnected.dispatch(with: msg.workerId)
                
                // Send our fuzzing state to the worker
                let now = Date()
                if cachedState.isEmpty || now.timeIntervalSince(cachedStateCreationTime) > 15 * Minutes {
                    // No cached state or it is too old
                    let state = fuzzer.exportState()
                    let encoder = JSONEncoder()
                    
                    let (data, duration) = measureTime { try! encoder.encode(state) }
                    logger.info("Encoding fuzzer state took \((String(format: "%.2f", duration)))s. Data size: \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .memory))")
                    
                    cachedState = data
                    cachedStateCreationTime = now
                }
                worker.conn.sendMessage(cachedState, ofType: .sync)
            } else {
                logger.warning("Received malformed identification message from worker")
            }
            
        case .crash:
            if let program = try? decoder.decode(Program.self, from: payload) {
                fuzzer.importCrash(program)
            } else {
                logger.warning("Received malformed program from worker")
            }
            
        case .program:
            if let program = try? decoder.decode(Program.self, from: payload) {
                fuzzer.importProgram(program)
            } else {
                logger.warning("Received malformed program from worker")
            }
            
        case .statistics:
            let decoder = JSONDecoder()
            if let data = try? decoder.decode(Statistics.Data.self, from: payload) {
                if let stats = Statistics.instance(for: fuzzer) {
                    stats.importData(data, from: worker.id!)
                }
            } else {
                logger.warning("Received malformed statistics update from worker")
            }
            
        case .log:
            let decoder = JSONDecoder()
            if let msg = try? decoder.decode(LogMessage.self, from: payload), let level = LogLevel(rawValue: msg.level) {
                fuzzer.events.Log.dispatch(with: (creator: msg.creator, level: level, label: msg.label, message: msg.content))
            } else {
                logger.warning("Received malformed log message data from worker")
            }
            
        default:
            logger.warning("Received unexpected packet from worker")
        }
    }
    
    func handleError(on connection: Connection) {
        if let worker = workers[connection.socket] {
            if let id = worker.id {
                let activeSeconds = Int(-worker.connectionTime.timeIntervalSinceNow)
                let activeMinutes = activeSeconds / 60
                let activeHours = activeMinutes / 60
                logger.warning("Lost connection to worker \(id). Worker was active for \(activeHours)h \(activeMinutes % 60)m \(activeSeconds % 60)s")
            }
            disconnect(worker)
        }
    }
    
    private func disconnect(_ worker: Worker) {
        worker.conn.close()
        if let id = worker.id {
            // If the id is nil then the worker never registered, so no need to deregister it internally
            fuzzer.events.WorkerDisconnected.dispatch(with: id)
        }
        workers.removeValue(forKey: worker.conn.socket)
    }
    
    struct Worker {
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
    private unowned let fuzzer: Fuzzer
    
    /// Logger for this module.
    private let logger: Logger
    
    /// Hostname of the master instance.
    let masterHostname: String
    
    /// Port of the master instance.
    let masterPort: UInt16
    
    /// Indicates whether the corpus has been synchronized with the master yet.
    private var synchronized = false
    
    /// Number of programs already imported from the master.
    private var syncPosition = 0
    
    /// Used when receiving a shutdown message from the master to avoid sending it further data.
    private var masterIsShuttingDown = false
    
    /// Connection to the master instance.
    private var conn: Connection! = nil
    
    public init(for fuzzer: Fuzzer, hostname: String, port: UInt16) {
        self.fuzzer = fuzzer
        self.logger = fuzzer.makeLogger(withLabel: "NetworkWorker")
        self.masterHostname = hostname
        self.masterPort = port
    }
    
    public func initialize(with fuzzer: Fuzzer) {
        connect()
        
        fuzzer.events.CrashFound.observe { ev in
            self.sendProgram(ev.program, type: .crash)
        }
        
        fuzzer.events.Shutdown.observe {
            if !self.masterIsShuttingDown {
                self.conn.sendMessage(Data(), ofType: .shutdown)
            }
        }
        
        fuzzer.events.InterestingProgramFound.observe { ev in
            if self.synchronized {
                self.sendProgram(ev.program, type: .program)
            }
        }
        
        // Regularly send local statistics to the master.
        if let stats = Statistics.instance(for: fuzzer) {
            fuzzer.timers.scheduleTask(every: 1 * Minutes) {
                let encoder = JSONEncoder()
                let data = stats.compute()
                if let payload = try? encoder.encode(data) {
                    self.conn.sendMessage(payload, ofType: .statistics)
                }
            }
        }
        
        // Forward log events to the master.
        fuzzer.events.Log.observe { ev in
            let msg = LogMessage(creator: fuzzer.id, level: ev.level.rawValue, label: ev.label, content: ev.message)
            let encoder = JSONEncoder()
            let payload = try! encoder.encode(msg)
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
        let decoder = JSONDecoder()
        
        switch type {
        case .keepalive:
            break
            
        case .shutdown:
            logger.info("Master is shutting down. Stopping this worker...")
            masterIsShuttingDown = true
            self.fuzzer.stop()
            
        case .program:
            if let program = try? decoder.decode(Program.self, from: payload) {
                fuzzer.importProgram(program, withDropout: true)
            } else {
                logger.error("Received malformed program from master")
            }
            
        case .sync:
            let decoder = JSONDecoder()
            let (maybeState, duration) = measureTime { try? decoder.decode(Fuzzer.State.self, from: payload) }
            if let state = maybeState {
                logger.info("Decoding fuzzer state took \((String(format: "%.2f", duration)))s")
                do {
                    try fuzzer.importState(state)
                    logger.info("Synchronized with master. Corpus contains \(fuzzer.corpus.size) programs")
                    
                } catch {
                    logger.error("Failed to import state from master: \(error.localizedDescription)")
                }
            } else {
                logger.error("Received malformed sync packet from master")
            }
            synchronized = true
            
        default:
            logger.warning("Received unexpected packet from master")
        }
    }
    
    func handleError(on connection: Connection) {
        logger.warning("Trying to reconnect to master after connection error")
        connect()
    }
    
    private func connect() {
        var fd: Int32 = -1
        for _ in 0..<10 {
            fd = libsocket.socket_connect(masterHostname, masterPort)
            if fd >= 0 {
                break
            } else {
                logger.warning("Failed to connect to master. Retrying in 30 seconds")
                sleep(30)
            }
        }
        if fd < 0 {
            logger.fatal("Failed to connect to master")
        }
        
        logger.info("Connected to master, our id: \(fuzzer.id)")
        conn = Connection(socket: fd, handler: self, fuzzer: fuzzer)
        
        // Identify ourselves.
        let encoder = JSONEncoder()
        let msg = Identification(workerId: fuzzer.id)
        let payload = try! encoder.encode(msg)
        conn.sendMessage(payload, ofType: .identify)
    }
    
    private func sendProgram(_ program: Program, type: MessageType) {
        assert(type == .program || type == .crash)
        let encoder = JSONEncoder()
        let payload = try! encoder.encode(program)
        conn.sendMessage(payload, ofType: type)
    }
}
