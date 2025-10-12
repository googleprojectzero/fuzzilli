import Foundation
import NIO
import RediStack

public class RedisCorpus: ComponentBase, Collection, Corpus {
    private let minSize: Int
    private let minMutationsPerSample: Int
    private var programs: RingBuffer<Program>
    private var ages: RingBuffer<Int>
    private var totalEntryCounter = 0
    private var uniqueBase64Programs: Set<String> = []
    private var COUNT = 0 // arb count used for determing when to sync from redis
    private var programIdToBase64: [String: String] = [:]

    private var eventLoopGroup: MultiThreadedEventLoopGroup?
    private var redisPool: RedisConnectionPool?

    public init(minSize: Int, maxSize: Int, minMutationsPerSample: Int) {
        assert(minSize >= 1)
        assert(maxSize >= minSize)
        self.minSize = minSize
        self.minMutationsPerSample = minMutationsPerSample
        self.programs = RingBuffer(maxSize: maxSize)
        self.ages = RingBuffer(maxSize: maxSize)

        super.init(name: "Corpus")
    }

    deinit {
        if let pool = redisPool { pool.close() }
        if let group = eventLoopGroup { try? group.syncShutdownGracefully() }
    }

    override func initialize() {
        if !fuzzer.config.staticCorpus {
            fuzzer.timers.scheduleTask(every: 30 * Minutes, cleanup)
        }
        eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        if let group = eventLoopGroup {
            let address = try? SocketAddress(ipAddress: "127.0.0.1", port: 6379)
            let config = RedisConnectionPool.Configuration(
                initialServerConnectionAddresses: [address!],
                maximumConnectionCount: .maximumActiveConnections(1),
                connectionFactoryConfiguration: .init()
            )
            redisPool = RedisConnectionPool(configuration: config, boundEventLoop: group.next())
        }
    }

    public var size: Int {
        return programs.count
    }

    public var isEmpty: Bool {
        return size == 0
    }

    public var supportsFastStateSynchronization: Bool {
        return true
    }

    public func add(_ program: Program, _ : ProgramAspects) {
        // try to sync from redis if the local corpus when doing an add 
        if checkSizeRedis() {
            receiveFromRedis()
        }
        addInternal(program)
    }

    public func addInternal(_ program: Program) {
        if program.size > 0 {
            let idx = totalEntryCounter
            prepareProgramForInclusion(program, index: idx)
            programs.append(program)
            ages.append(0)
            totalEntryCounter += 1
            sendToRedis(index: idx, program: program, age: 0)
        }
    }

    public func randomElementForSplicing() -> Program {
        // sync every 200 mutaitons 
        if (COUNT > 200) {
            if checkSizeRedis() {
                receiveFromRedis()
            }
            COUNT = 0
        }
        COUNT += 1
        assert(programs.count > 0)
        let idx = Int.random(in: 0..<programs.count)
        let program = programs[idx]
        assert(!program.isEmpty)
        return program
    }

    public func randomElementForMutating() -> Program {
        // sync every 200 mutations
        if (COUNT > 200) {
            if checkSizeRedis() {
                receiveFromRedis()
            }
            COUNT = 0
        }
        COUNT += 1
        let idx = Int.random(in: 0..<programs.count)
        ages[idx] += 1
        let program = programs[idx]
        assert(!program.isEmpty)
        return program
    }

    public func allPrograms() -> [Program] {
        return Array(programs)
    }

    public func exportState() throws -> Data {
        let res = try encodeProtobufCorpus(programs)
        logger.info("Successfully serialized \(programs.count) programs")
        return res
    }

    public func importState(_ buffer: Data) throws {
        let newPrograms = try decodeProtobufCorpus(buffer)
        programs.removeAll()
        ages.removeAll()
        newPrograms.forEach(addInternal)
    }

    private func cleanup() {
        assert(!fuzzer.config.staticCorpus)
        var newPrograms = RingBuffer<Program>(maxSize: programs.maxSize)
        var newAges = RingBuffer<Int>(maxSize: ages.maxSize)

        for i in 0..<programs.count {
            let remaining = programs.count - i
            if ages[i] < minMutationsPerSample || remaining <= (minSize - newPrograms.count) {
                newPrograms.append(programs[i])
                newAges.append(ages[i])
            }
        }

        logger.info("Corpus cleanup finished: \(self.programs.count) -> \(newPrograms.count)")
        programs = newPrograms
        ages = newAges
    }

    public var startIndex: Int {
        return programs.startIndex
    }

    public var endIndex: Int {
        return programs.endIndex
    }

    public subscript(index: Int) -> Program {
        return programs[index]
    }

    public func index(after i: Int) -> Int {
        return i + 1
    }
    // public function to update the feedback vector used in the stroage. swift code to sync    
    public func updateFeedbackVector(programId: String, feedbackData: String) {
        guard let pool = redisPool else { return }
        guard let programBase64 = programIdToBase64[programId] else { return }
        
        let streamData: [RESPValue] = [
            RESPValue(from: "stream:fuzz:updates"),
            RESPValue(from: "*"),
            RESPValue(from: "op"),
            RESPValue(from: "update_feedback"),
            RESPValue(from: "program_base64"),
            RESPValue(from: programBase64),
            RESPValue(from: "feedback_vector"),
            RESPValue(from: feedbackData)
        ]
        
        _ = pool.leaseConnection { (redis: RedisConnection) in
            redis.send(command: "XADD", with: streamData)
        }
    }

    private func sendToRedis(index: Int, program: Program, age: Int) {
        // send to stream using raw redis SEND command used with the python sync.py
        // then send to lacal redis storage via set
        guard let pool = redisPool else { return }
        
        guard let programBase64 = try? encodeProtobufCorpus([program]).base64EncodedString() else { return }
        uniqueBase64Programs.insert(programBase64)
        programIdToBase64[program.id.uuidString] = programBase64
        
        let coverageTotal: Double
        if let coverageEvaluator = fuzzer.evaluator as? ProgramCoverageEvaluator {
            coverageTotal = coverageEvaluator.currentScore * 100.0
        } else {
            coverageTotal = 0.0
        }
        
        let streamData: [RESPValue] = [
            RESPValue(from: "stream:fuzz:updates"),
            RESPValue(from: "*"),
            RESPValue(from: "op"),
            RESPValue(from: "set"),
            RESPValue(from: "program_base64"),
            RESPValue(from: programBase64),
            RESPValue(from: "fuzzer_id"),
            RESPValue(from: "0"),
            RESPValue(from: "feedback_vector"),
            RESPValue(from: "null"),
            RESPValue(from: "turboshaft_ir"),
            RESPValue(from: ""),
            RESPValue(from: "coverage_total"),
            RESPValue(from: String(format: "%.2f", coverageTotal))
        ]
        
        let payload: String = {
            let dict: [String: Any] = [
                "index": index,
                "program_b64": programBase64
            ]
            let data = try! JSONSerialization.data(withJSONObject: dict, options: [])
            return String(data: data, encoding: .utf8) ?? "{}"
        }()
        
        _ = pool.leaseConnection { (redis: RedisConnection) in
            redis.send(command: "XADD", with: streamData).flatMap { _ in
                redis.set("corpus:\(index)", to: payload).flatMap { _ in
                    redis.set("corpus:latest_index", to: String(index))
                }
            }
        }
    }


    private func checkSizeRedis() -> Bool {
        guard let pool = redisPool else { return false }
        var result = false
        let group = DispatchGroup()
        group.enter()
        _ = pool.leaseConnection { (redis: RedisConnection) in
            redis.get("corpus:latest_index").map { index in
                if let redisSize = Int(fromRESP: index) {
                    if redisSize + 1 != self.programs.count {
                        result = true
                    }
                } else {
                    if self.programs.count != 0 {
                        result = true
                    }
                }
                group.leave()
            }
        }
        group.wait()
        return result
    }

    private func receiveFromRedis() {
        guard let pool = redisPool else { return }
        _ = pool.leaseConnection { (redis: RedisConnection) -> EventLoopFuture<Void> in
            redis.get("corpus:latest_index").flatMap { index in
                guard let redisSize = Int(fromRESP: index) else { return pool.eventLoop.makeSucceededFuture(()) }
                let localSize = self.programs.count
                if redisSize + 1 > localSize {
                    let missingIndices = localSize...(redisSize)
                    let fetchFutures = missingIndices.map { idx in
                        redis.get("corpus:\(idx)").map { payload in
                            guard let payload = payload.string,
                                  let data = payload.data(using: .utf8),
                                  let dict = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                                  let b64 = dict["program_b64"] as? String,
                                  let programData = Data(base64Encoded: b64),
                                  let programs = try? decodeProtobufCorpus(programData),
                                  let program = programs.first else { return }
                            
                            if !self.uniqueBase64Programs.contains(b64) {
                                self.uniqueBase64Programs.insert(b64)
                                self.addInternal(program)
                            }
                        }
                    }
                    return EventLoopFuture.andAllSucceed(fetchFutures, on: pool.eventLoop)
                }
                return pool.eventLoop.makeSucceededFuture(())
            }
        }
    }
}