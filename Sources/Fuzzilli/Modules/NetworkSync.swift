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
/// TODO: add some kind of compression and encryption...

/// Supported message types.
enum MessageType: UInt32 {
    // A simple ping message to keep the TCP connection alive.
    case keepalive    = 0
    
    // Send by workers after connecting. Identifies a worker through a UUID.
    case identify     = 1
    
    // A FuzzIL program that is interesting and should be imported at the other end.
    case program      = 2
    
    // A crashing program that is sent from a worker to a master.
    case crash        = 3
    
    // A request by a worker to a master that the master should sent another part of
    // its corpus to the worker. Includes the number of programs that the worker
    // has already imported.
    case syncRequest  = 4
    
    // A reply to a sync request. Contains a slice of the master's corpus.
    // If that slice is empty, then synchronization is finished.
    case syncResponse = 5
    
    // A statistics package send by a worker to a master.
    case statistics   = 6
}

/// Payload of an identification message.
fileprivate struct Identification: Codable {
    let workerId: UUID
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
    
    /// DispatchQueue on which messages will be received and handlers invoked.
    private let queue: DispatchQueue
    
    /// DispatchSource to trigger when data is available.
    private let readSource: DispatchSourceRead
    
    /// DispatchSource to trigger when data can be sent.
    private var writeSource: DispatchSourceWrite? = nil
    
    /// Buffer for incoming messages.
    private var currentMessageData = Data()
    
    /// Buffer to receive into.
    private var receiveBuffer = [UInt8](repeating: 0, count: 1024 * 1024)
    
    /// Pending outgoing data.
    private var sendBuffer = Data()
    
    init(socket: Int32, handler: MessageHandler, fuzzer: Fuzzer) {
        self.socket = socket
        self.handler = handler
        self.queue = fuzzer.queue
        self.logger = fuzzer.makeLogger(withLabel: "Connection \(socket)")
        
        self.readSource = DispatchSource.makeReadSource(fileDescriptor: socket, queue: queue)
        self.readSource.setEventHandler { [weak self] in
            self?.handleDataAvailable()
        }
        self.readSource.resume()
    }
    
    deinit {
        readSource.cancel()
        writeSource?.cancel()
        libsocket.socket_close(socket)
    }
    
    /// Send a message.
    ///
    /// This will either send the message immediately or queue for delivery
    /// once the remote peer can accept more data.
    func sendMessage(_ data: Data, ofType type: MessageType) {
        guard data.count + messageHeaderSize <= maxMessageSize else {
            logger.error("Message too large to be sent. Discarding")
            return
        }
        
        var length = UInt32(data.count + messageHeaderSize).littleEndian
        var type = type.rawValue.littleEndian
        let padding = Data(repeating: 0, count: paddingLength(for: Int(length)))
        
        var message = Data(bytes: &length, count: 4)
        message.append(Data(bytes: &type, count: 4))
        message.append(data)
        message.append(padding)
        
        if sendBuffer.count > 0 {
            // No more data can be send at this time. Queue the message.
            sendBuffer = sendBuffer + message
            return
        }
        
        // Try to send the data immediately.
        sendBuffer = message
        sendPendingData()
    }
    
    private func sendPendingData() {
        let length = sendBuffer.count
        assert(length > 0)
        
        let rv = sendBuffer.withUnsafeBytes { body -> CInt in
            return libsocket.socket_send(socket, body.bindMemory(to: UInt8.self).baseAddress, UInt32(length))
        }
        
        if rv < 0 {
            handler.handleError(on: self)
            sendBuffer.removeAll()
            writeSource?.cancel()
            writeSource = nil
        } else if rv != length {
            assert(rv < length)
            // Only managed to send part of the data. Queue the rest.
            sendBuffer.removeFirst(Int(rv))
            if writeSource == nil {
                self.writeSource = DispatchSource.makeWriteSource(fileDescriptor: socket, queue: queue)
                self.writeSource?.setEventHandler { [weak self] in
                    self?.sendPendingData()
                }
                self.writeSource?.resume()
            }
        } else {
            // Sent all data successfully.
            sendBuffer.removeAll()
            writeSource?.cancel()
            writeSource = nil
        }
    }
    
    private func handleDataAvailable() {
        // Just read a chunk of data and then process it. If there is more data pending, we will be invoked again.
        let bytesRead = read(socket, UnsafeMutablePointer<UInt8>(&receiveBuffer), receiveBuffer.count)
        guard bytesRead > 0 else {
            return handler.handleError(on: self)
        }
        currentMessageData.append(UnsafeMutablePointer<UInt8>(&receiveBuffer), count: Int(bytesRead))
        
        while currentMessageData.count >= messageHeaderSize {
            let length = Int(readUint32(from: currentMessageData, atOffset: 0))
            
            guard length <= maxMessageSize && length >= messageHeaderSize else {
                // For now we just close the connection if an invalid message is received.
                logger.warning("Received message with invalid length. Closing connection.")
                return handler.handleError(on: self)
            }
            
            guard length <= currentMessageData.count else {
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
                return handler.handleError(on: self)
            }
        }
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
    
    /// DispatchQueue on which the sockets are handled.
    private let socketQueue: DispatchQueue
    
    /// Active workers. The key is the socket filedescriptor number.
    private var workers = [Int32: Worker]()
    
    /// Maximum number of programs in a sync response.
    private let maxCorpusChunkSize = 1000
    
    /// Cache for sync responses.
    private var corpusChunks = [Int: Data]()
    
    public init(for fuzzer: Fuzzer, address: String, port: UInt16) {
        self.fuzzer = fuzzer
        self.logger = fuzzer.makeLogger(withLabel: "NetworkMaster")
        self.address = address
        self.port = port
        self.socketQueue = DispatchQueue(label: "socket_queue")
    }
    
    public func initialize(with fuzzer: Fuzzer) {
        self.serverFd = libsocket.socket_listen(address, port)
        guard serverFd > 0 else {
            logger.fatal("Failed to open server socket")
        }
        
        socketQueue.async {
            repeat {
                let workerFd = libsocket.socket_accept(self.serverFd)
                guard workerFd > 0 else {
                    fuzzer.queue.async {
                        self.logger.warning("Failed to accept client connection")
                    }
                    sleep(10)       // TODO better error handling here
                    continue
                }
                fuzzer.queue.async {
                    self.handleNewWorker(workerFd)
                }
            } while true
        }
        
        logger.info("Accepting worker connections on \(address):\(port)")
        
        // Only start sending interesting programs after a short delay to not spam the workers too much.
        fuzzer.timers.runAfter(10 * Minutes) {
            addEventListener(for: fuzzer.events.InterestingProgramFound) { ev in
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
    
    func handleNewWorker(_ fd: Int32) {
        let worker = Worker(conn: Connection(socket: fd, handler: self, fuzzer: fuzzer), id: nil)
        workers[fd] = worker
        
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
            
        case .identify:
            if let msg = try? decoder.decode(Identification.self, from: payload) {
                if worker.id != nil {
                    logger.warning("Received multiple identification messages from client. Ignoring message")
                    break
                }
                workers[worker.conn.socket] = Worker(conn: worker.conn, id: msg.workerId)
                
                logger.info("Worker identified as \(msg.workerId)")
                dispatchEvent(fuzzer.events.WorkerConnected, data: msg.workerId)
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
            
        case .syncRequest:
            if payload.count == 4 {
                let value = payload.withUnsafeBytes { $0.load(as: UInt32.self) }
                let start = Int(UInt32(littleEndian: value))
                
                // Send the next batch of programs from our corpus
                let data: Data
                if let cached = corpusChunks[start] {
                    data = cached
                } else {
                    let corpus = fuzzer.corpus.export()
                    let end = min(start + maxCorpusChunkSize, corpus.count)
                    var batch = corpus[start..<end]
                    
                    // Speed up termination of the synchronization procedure
                    if end - start < 10 {
                        batch.removeAll()
                    }
                    
                    let encoder = JSONEncoder()
                    data = try! encoder.encode(Array(batch))
                    
                    // Only cache full chunks
                    if start % maxCorpusChunkSize == 0 && end - start == maxCorpusChunkSize {
                        corpusChunks[start] = data
                    }
                }
                
                worker.conn.sendMessage(data, ofType: .syncResponse)
            } else {
                logger.warning("Received malformed syncRequest from worker")
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
            
        default:
            logger.warning("Received unexpected packet from worker")
        }
    }
    
    func handleError(on connection: Connection) {
        if let worker = workers[connection.socket] {
            disconnect(worker)
        }
    }
    
    private func disconnect(_ worker: Worker) {
        if let id = worker.id {
            // If the id is nil then the worker never registered, so no need to deregister it internally
            dispatchEvent(fuzzer.events.WorkerDisconnected, data: id)
        }
        workers.removeValue(forKey: worker.conn.socket)
        logger.info("Worker disconnected")
    }
    
    struct Worker {
        // The network connection to the worker.
        let conn: Connection
        
        // The id of the worker.
        let id: UUID?
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
    
    /// UUID of this instance.
    let id: UUID
    
    /// Indicates whether the corpus has been synchronized with the master yet.
    private var corpusSynchronized = false
    
    /// Number of programs already imported from the master.
    private var syncPosition = 0
    
    /// Connection to the master instance.
    private var conn: Connection! = nil
    
    public init(for fuzzer: Fuzzer, hostname: String, port: UInt16) {
        self.fuzzer = fuzzer
        self.logger = fuzzer.makeLogger(withLabel: "NetworkWorker")
        self.masterHostname = hostname
        self.masterPort = port
        self.id = UUID()
    }
    
    public func initialize(with fuzzer: Fuzzer) {
        connect()
        
        addEventListener(for: fuzzer.events.CrashFound) { ev in
            self.sendProgram(ev.program, type: .crash)
        }
        
        // Only start sending interesting programs after a short delay to not spam the master instance too much.
        fuzzer.timers.runAfter(10 * Minutes) {
            addEventListener(for: fuzzer.events.InterestingProgramFound) { ev in
                guard self.corpusSynchronized else {
                    return
                }
                self.sendProgram(ev.program, type: .program)
            }
        }
        
        // Regularly send local statistics to the master.
        if let stats = Statistics.instance(for: fuzzer) {
            fuzzer.timers.scheduleTask(every: 1 * Minutes) {
                let encoder = JSONEncoder()
                let data = stats.compute()
                let payload = try! encoder.encode(data)
                self.conn.sendMessage(payload, ofType: .statistics)
            }
        }
        
        // Start corpus synchronization.
        requestCorpusSync()
    }
    
    func handleMessage(_ payload: Data, ofType type: MessageType, from connection: Connection) {
        let decoder = JSONDecoder()
        
        switch type {
        case .keepalive:
            break
            
        case .program:
            if let program = try? decoder.decode(Program.self, from: payload) {
                guard corpusSynchronized else {
                    // If synchronization hasn't finished yet then we'll get this program again.
                    return
                }
                
                fuzzer.importProgram(program, withDropout: true)
            } else {
                logger.warning("Received malformed program from master")
            }
            
        case .syncResponse:
            if let corpus = try? decoder.decode([Program].self, from: payload) {
                if corpus.isEmpty {
                    corpusSynchronized = true
                    logger.info("Corpus synchronization finished")
                    return
                }
                
                fuzzer.importCorpus(corpus, withDropout: true)
                logger.info("Imported \(corpus.count) programs from master")
                syncPosition += corpus.count
                requestCorpusSync()
            } else {
                logger.warning("Received malformed corpus from master")
            }
            
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
        
        logger.info("Connected to master, our id: \(id)")
        conn = Connection(socket: fd, handler: self, fuzzer: fuzzer)
        
        // Identify ourselves.
        let encoder = JSONEncoder()
        let msg = Identification(workerId: id)
        let payload = try! encoder.encode(msg)
        conn.sendMessage(payload, ofType: .identify)
    }

    private func requestCorpusSync() {
        var start = UInt32(syncPosition).littleEndian
        let payload = Data(bytes: &start, count: 4)
        conn.sendMessage(payload, ofType: .syncRequest)
    }
    
    private func sendProgram(_ program: Program, type: MessageType) {
        assert(type == .program || type == .crash)
        let encoder = JSONEncoder()
        let payload = try! encoder.encode(program)
        conn.sendMessage(payload, ofType: type)
    }
}
