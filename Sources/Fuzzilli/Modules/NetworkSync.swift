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
// as transport layer for the sync protocol.
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

fileprivate let messageHeaderSize = 8
fileprivate let maxMessageSize = 1024 * 1024 * 1024

/// Protocol for an object capable of receiving messages.
fileprivate protocol MessageHandler {
    func handleMessage(_ payload: Data, ofType type: MessageType, from connection: Connection)
    func handleError(_ err: String, on connection: Connection)
    // The fuzzer instance on which to schedule the handler calls
    var fuzzer: Fuzzer { get }
}

/// A connection to a network peer that speaks the above protocol.
fileprivate class Connection {
    /// The file descriptor on POSIX or SOCKET handle on Windows of the socket.
    let socket: libsocket.socket_t

    /// The UUID of the remote end.
    let localId: UUID
    private(set) var remoteId: UUID! = nil

    /// DispatchQueue on which data is sent to and received from the socket.
    private let queue: DispatchQueue

    /// Whether this connection has been closed.
    private(set) var closed = false

    /// Message handler to which incoming messages are delivered.
    private let handler: MessageHandler

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

    init?(socket: libsocket.socket_t, localId: UUID, handler: MessageHandler) {
        self.socket = socket
        self.localId = localId
        self.handler = handler
        self.queue = DispatchQueue(label: "Socket \(socket)")

        guard performHandshake() else { return nil }

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
        queue.sync {
            self.internalClose()
        }
    }

    // Perform the handshake at the start of a new connection.
    //
    // During the handshake, each end of the connection sends it's UUID and waits (for a limited time, before aborting) for the other side's UUID.
    private func performHandshake() -> Bool {
        assert(remoteId == nil)

        // Send our id.
        let message = localId.uuidData
        let rv = message.withUnsafeBytes { data in
            return libsocket.socket_send(socket, data.bindMemory(to: UInt8.self).baseAddress, message.count)
        }
        guard rv == message.count else { return false }

        // Wait for the remote id. The socket has O_NONBLOCK set, so will not block if no data is available.
        var n = 0
        for _ in 0..<10 {
            n = libsocket.socket_recv(socket, receiveBuffer.baseAddress, 16)
            if n == 16 {
                break
            } else {
                Thread.sleep(forTimeInterval: 1 * Seconds)
            }
        }
        guard n == 16 else { return false }

        remoteId = UUID(uuidData: Data(bytes: receiveBuffer.baseAddress!, count: n))

        return true
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

        guard !closed else {
            return error("Received data on a closed connection")
        }

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
        dispatchPrecondition(condition: .onQueue(queue))

        guard !closed else {
            // This can happen, for example if outgoing data was queued before an error on the connection occurred.
            // In that case, the first error will close the connection, but the sending will then trigger a second error.
            return
        }

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

/// A parent node for distributed fuzzing over a network.
public class NetworkParent: DistributedFuzzingParentNode {
    public init(for fuzzer: Fuzzer, address: String, port: UInt16, corpusSynchronizationMode: CorpusSynchronizationMode) {
        let transport = Transport(for: fuzzer, address: address, port: port)
        super.init(for: fuzzer, name: "NetworkParent", corpusSynchronizationMode: corpusSynchronizationMode, transport: transport)
    }

    private class Transport: DistributedFuzzingParentNodeTransport, MessageHandler {
        /// Owning fuzzer instance. Needed for scheduling tasks on the fuzzer queue.
        unowned let fuzzer: Fuzzer

        /// File descriptor or SOCKET handle of the server socket.
        private var serverFd: libsocket.socket_t = INVALID_SOCKET

        /// Address and port on which to listen for connections.
        private let address: String
        private let port: UInt16

        /// Logger to use.
        private let logger: Logger

        /// Dispatch source to trigger when a new client connection is available.
        private var connectionSource: DispatchSourceRead? = nil
        /// DispatchQueue on which to accept client connections
        private var serverQueue: DispatchQueue? = nil

        /// Active workers indexed by the socket used to communicate with them.
        private var clientsBySocket = [libsocket.socket_t: Client]()

        /// Active workers indexed by their id.
        private var clientsById = [UUID: Client]()

        /// Callbacks from higher level protocol.
        private var onMessageCallback: OnMessageCallback? = nil
        private var onChildConnectedCallback: OnChildConnectedCallback? = nil
        private var onChildDisconnectedCallback: OnChildDisconnectedCallback? = nil

        init(for fuzzer: Fuzzer, address: String, port: UInt16) {
            self.fuzzer = fuzzer
            self.address = address
            self.port = port
            self.logger = Logger(withLabel: "NetworkParentTransport")
        }

        func initialize() {
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
                self.fuzzer.async {
                    self.handleNewConnection(socket)
                }
            }
            connectionSource?.activate()

            logger.info("Accepting worker connections on \(address):\(port)")
        }

        func send(_ messageType: MessageType, to child: UUID, contents: Data) {
            guard let client = clientsById[child] else {
                return logger.error("Unknown child node: \(child)")
            }

            client.conn.sendMessage(contents, ofType: messageType)
        }

        func send(_ messageType: MessageType, to child: UUID, contents: Data, synchronizeWith synchronizationGroup: DispatchGroup) {
            guard let client = clientsById[child] else {
                return logger.error("Unknown child node: \(child)")
            }

            client.conn.sendMessage(contents, ofType: messageType, syncWith: synchronizationGroup)
        }

        func handleMessage(_ payload: Data, ofType type: MessageType, from connection: Connection) {
            guard let client = clientsBySocket[connection.socket] else {
                return logger.error("Received message from unknown source?")
            }
            assert(client.id == connection.remoteId)
            onMessageCallback?(type, payload, client.id)
        }

        func handleError(_ err: String, on connection: Connection) {
            // In case the worker isn't known, we probably already disconnected it, so there's nothing to do.
            if let worker = clientsBySocket[connection.socket] {
                logger.warning("Error on connection \(connection.socket): \(err). Disconnecting client.")
                let activeSeconds = Int(-worker.connectionTime.timeIntervalSinceNow)
                let activeMinutes = activeSeconds / 60
                let activeHours = activeMinutes / 60
                logger.warning("Lost connection to worker \(worker.id). Worker was active for \(activeHours)h \(activeMinutes % 60)m \(activeSeconds % 60)s")

                disconnect(worker)
            }
        }

        func disconnect(_ worker: UUID) {
            guard let worker = clientsById[worker] else {
                return logger.error("Unknown worker \(worker)")
            }
            disconnect(worker)
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
            assert(onChildDisconnectedCallback == nil)
            onChildDisconnectedCallback = callback
        }

        private func handleNewConnection(_ socket: libsocket.socket_t) {
            guard socket > 0 else {
                return logger.error("Failed to accept client connection")
            }

            guard let conn = Connection(socket: socket, localId: fuzzer.id, handler: self) else {
                return logger.error("Failed to initialize client connection")
            }

            let client = Client(conn: conn, id: conn.remoteId, connectionTime: Date())

            if let existingClient = clientsById[conn.remoteId] {
                // This likely means that the client reconnected. Disconnect the old instance.
                disconnect(existingClient)
            }

            assert(!clientsById.keys.contains(conn.remoteId))
            clientsBySocket[socket] = client
            clientsById[conn.remoteId] = client

            logger.info("New client connected: \(client.id)")

            onChildConnectedCallback?(client.id)
        }

        private func disconnect(_ client: Client) {
            client.conn.close()
            clientsById.removeValue(forKey: client.id)
            clientsBySocket.removeValue(forKey: client.conn.socket)

            onChildDisconnectedCallback?(client.id)
        }

        private struct Client {
            // The network connection to the client.
            let conn: Connection

            // The id of the client.
            let id: UUID

            // The time the client connected.
            let connectionTime: Date
        }
    }
}

/// A child node for distributed fuzzing over a network.
public class NetworkChild: DistributedFuzzingChildNode {
    public init(for fuzzer: Fuzzer, hostname: String, port: UInt16, corpusSynchronizationMode: CorpusSynchronizationMode) {
        let transport = Transport(for: fuzzer, parentHostname: hostname, parentPort: port)
        super.init(for: fuzzer, name: "NetworkChild", corpusSynchronizationMode: corpusSynchronizationMode, transport: transport)
    }

    private class Transport: DistributedFuzzingChildNodeTransport, MessageHandler {
        /// Owning fuzzer instance. Needed for scheduling tasks on the fuzzer queue.
        unowned let fuzzer: Fuzzer

        /// Hostname and port of the parent node.
        private let parentHostname: String
        private let parentPort: UInt16

        /// Connection to the parent node.
        private var conn: Connection! = nil

        /// Logger to use.
        private let logger: Logger

        /// Callbacks from higher level protocol.
        private var onMessageCallback: OnMessageCallback? = nil

        public init(for fuzzer: Fuzzer, parentHostname: String, parentPort: UInt16) {
            self.fuzzer = fuzzer
            self.parentHostname = parentHostname
            self.parentPort = parentPort
            self.logger = Logger(withLabel: "NetworkChildNodeTransport")
        }

        func initialize() {
            connect()
        }

        func send(_ messageType: MessageType, contents: Data) {
            conn.sendMessage(contents, ofType: messageType)
        }

        func send(_ messageType: MessageType, contents: Data = Data(), synchronizeWith synchronizationGroup: DispatchGroup) {
            conn.sendMessage(contents, ofType: messageType, syncWith: synchronizationGroup)
        }

        func setOnMessageCallback(_ callback: @escaping OnMessageCallback) {
            assert(onMessageCallback == nil)
            onMessageCallback = callback
        }

        func handleMessage(_ payload: Data, ofType type: MessageType, from connection: Connection) {
            onMessageCallback?(type, payload)
        }

        func handleError(_ err: String, on connection: Connection) {
            assert(connection.socket == conn.socket)
            logger.error("Error on connection to parent node: \(err). Trying to reconnect...")
            connect()
        }

        private func connect() {
            for _ in 0..<10 {
                let fd = libsocket.socket_connect(parentHostname, parentPort)
                guard fd != INVALID_SOCKET else {
                    logger.error("Failed to connect to parent node. Retrying in 30 seconds")
                    Thread.sleep(forTimeInterval: 30 * Seconds)
                    continue
                }

                guard let connection = Connection(socket: fd, localId: fuzzer.id, handler: self) else {
                    logger.error("Failed to initialize connection to parent node. Retrying in 30 seconds")
                    Thread.sleep(forTimeInterval: 30 * Seconds)
                    continue
                }

                logger.info("Connected to parent node, our id: \(fuzzer.id), remote id: \(connection.remoteId!)")
                conn = connection
                return
            }

            logger.fatal("Failed to connect to parent node")
        }
    }
}
