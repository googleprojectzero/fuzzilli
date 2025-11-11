import Foundation
import PostgresNIO
import PostgresKit

/// PostgreSQL-based corpus for distributed fuzzing.
///
/// This corpus connects directly to a master PostgreSQL database. Each fuzzer instance
/// stores and retrieves programs directly from the master database without local caching.
///
/// Features:
/// - Direct master database connection
/// - Execution metadata tracking (coverage, execution count, etc.)
/// - Dynamic batching based on execution speed
/// - Thread-safe operations
public class PostgreSQLCorpus: ComponentBase, Corpus {
    
    // MARK: - Configuration
    
    private let minSize: Int
    private let maxSize: Int
    private let minMutationsPerSample: Int
    private let databasePool: DatabasePool // Master database pool
    private let fuzzerInstanceId: String
    private let storage: PostgreSQLStorage // Master storage
    private let resume: Bool
    private let enableLogging: Bool
    
    /// Track current execution for event handling
    private var currentExecutionProgram: Program?
    private var currentExecutionPurpose: ExecutionPurpose?
    
    /// Track fuzzer registration status
    private var fuzzerRegistered = false
    private var fuzzerId: Int? // Master database fuzzer ID
    
    /// Batch execution storage
    private var pendingExecutions: [(Program, ProgramAspects, DatabaseExecutionPurpose)] = []
    private var executionBatchSize: Int // Dynamic batch size
    private let executionBatchLock = NSLock()
    
    /// Cache for recently accessed programs to avoid repeated DB queries
    private var recentProgramCache: [String: Program] = [:]
    private let recentCacheLock = NSLock()
    private let maxRecentCacheSize = 1000 // Keep only recent 1000 programs in memory
    
    // MARK: - Initialization
    
    public init(
        minSize: Int,
        maxSize: Int,
        minMutationsPerSample: Int,
        databasePool: DatabasePool, // Master database pool
        fuzzerInstanceId: String,
        resume: Bool = true, // Default to resume from previous state
        enableLogging: Bool = false
    ) {
        // The corpus must never be empty
        assert(minSize >= 1)
        assert(maxSize >= minSize)
        
        self.minSize = minSize
        self.maxSize = maxSize
        self.minMutationsPerSample = minMutationsPerSample
        self.databasePool = databasePool
        self.fuzzerInstanceId = fuzzerInstanceId
        self.resume = resume
        self.enableLogging = enableLogging
        self.storage = PostgreSQLStorage(databasePool: databasePool, enableLogging: enableLogging)
        
        // Initialize with default batch size, will be updated dynamically
        self.executionBatchSize = 100_000
        
        super.init(name: "PostgreSQLCorpus")
        
        // Setup signal handlers for graceful shutdown
        setupSignalHandlers()
        
        // Start periodic batch flushing and batch size recalculation
        startPeriodicBatchFlush()
        startPeriodicBatchSizeUpdate()
    }
    
    deinit {
        // Unregister this instance
        PostgreSQLCorpus.unregisterInstance(self)
        
        // Commit any pending batches when the corpus is deallocated
        // Use Task.detached to avoid capturing self
        Task.detached { [weak self] in
            await self?.commitPendingBatches()
        }
    }
    
    
    // MARK: - Performance Optimizations
    
    /// Async-safe locking helper
    private func withLock<T>(_ lock: NSLock, _ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
    
    private func startPeriodicBatchFlush() {
        // Flush batches every 5 seconds to ensure timely processing
        Task {
            while true {
                try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                flushExecutionBatch()
            }
        }
    }
    
    /// Recalculate batch size based on execution speed (execs/sec * 3600 for hourly batches)
    private func startPeriodicBatchSizeUpdate() {
        // Update batch size every 5 minutes
        Task {
            while true {
                try? await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000) // 5 minutes
                updateBatchSize()
            }
        }
    }
    
    /// Calculate and update dynamic batch size based on execution speed
    private func updateBatchSize() {
        guard let statsModule = Statistics.instance(for: fuzzer) else {
            // If statistics module not available, use default batch size
            if enableLogging {
                logger.warning("Statistics module not available, using default batch size")
            }
            return
        }
        
        let stats = statsModule.compute()
        let execsPerSecond = stats.execsPerSecond
        
        // Calculate executions per hour: execs/sec * 60 sec/min * 60 min/hour
        let calculatedBatchSize = Int(execsPerSecond * 60.0 * 60.0)
        
        // Ensure minimum batch size (1000) and maximum (1M)
        let newBatchSize = max(1000, min(1_000_000, calculatedBatchSize))
        
        executionBatchLock.withLock {
            executionBatchSize = newBatchSize
        }
        
        if enableLogging {
            logger.info("Updated execution batch size: \(newBatchSize) (based on \(String(format: "%.2f", execsPerSecond)) execs/sec)")
        }
    }
    
    // MARK: - Signal Handling and Early Exit
    
    private func setupSignalHandlers() {
        // Handle SIGINT (Ctrl+C) and SIGTERM for graceful shutdown
        // Note: Signal handling is simplified for cross-platform compatibility
        // The deinit method will handle cleanup when the object is deallocated
    }
    
    // Instance tracking for cleanup (simplified without signal handling)
    private static var allInstances: [PostgreSQLCorpus] = []
    private static let instancesLock = NSLock()
    
    private static func registerInstance(_ instance: PostgreSQLCorpus) {
        instancesLock.lock()
        defer { instancesLock.unlock() }
        allInstances.append(instance)
    }
    
    private static func unregisterInstance(_ instance: PostgreSQLCorpus) {
        instancesLock.lock()
        defer { instancesLock.unlock() }
        allInstances.removeAll { $0 === instance }
    }
    
    private func commitPendingBatches() async {
        guard fuzzerId != nil else { return }
        
        // Commit pending executions
        let queuedExecutions = executionBatchLock.withLock {
            let queuedExecutions = pendingExecutions
            pendingExecutions.removeAll()
            return queuedExecutions
        }
        
        if !queuedExecutions.isEmpty {
            await processExecutionBatch(queuedExecutions)
            if enableLogging {
                self.logger.info("Committed \(queuedExecutions.count) pending executions on exit")
            }
        }
    }
    
    override func initialize() {
        // Register this instance for signal handling
        PostgreSQLCorpus.registerInstance(self)
        
        // Initialize database pool and register fuzzer (only once)
        Task {
            do {
                // Initialize master database pool
                try await databasePool.initialize()
                if enableLogging {
                    self.logger.info("Master database pool initialized successfully")
                }
                
                // Register this fuzzer instance in the master database (only once)
                if !fuzzerRegistered {
                    do {
                        let id = try await storage.registerFuzzer(
                            name: fuzzerInstanceId,
                            engineType: "v8"
                        )
                        fuzzerId = id
                        fuzzerRegistered = true
                        if enableLogging {
                            self.logger.info("Fuzzer registered in master database with ID: \(id)")
                        }
                    } catch {
                        logger.error("Failed to register fuzzer after retries: \(error)")
                        if enableLogging {
                            self.logger.info("Fuzzer will continue without database registration - executions will be queued")
                        }
                    }
                }
                
            } catch {
                logger.error("Failed to initialize database pool: \(error)")
            }
        }
        
        // Track coverage statistics from evaluator
        fuzzer.registerEventListener(for: fuzzer.events.InterestingProgramFound) { ev in
            if let coverageEvaluator = self.fuzzer.evaluator as? ProgramCoverageEvaluator {
                let currentCoverage = coverageEvaluator.currentScore
                
                Task {
                    await self.storeCoverageSnapshot(
                        coverage: currentCoverage,
                        programHash: DatabaseUtils.calculateProgramHash(program: ev.program)
                    )
                }
            }
        }
        
        // Listen for PreExecute events to track the program being executed
        fuzzer.registerEventListener(for: fuzzer.events.PreExecute) { (program, purpose) in
            // Store the program and purpose for the next PostExecute event
            self.currentExecutionProgram = program
            self.currentExecutionPurpose = purpose
        }
        
        // Listen for PostExecute events to track all program executions
        fuzzer.registerEventListener(for: fuzzer.events.PostExecute) { execution in
            if let program = self.currentExecutionProgram, let purpose = self.currentExecutionPurpose {
                // DEBUG: Log execution recording
                if self.enableLogging {
                    self.logger.info("Recording execution: outcome=\(execution.outcome), execTime=\(execution.execTime)")
                }
                
                // Create ProgramAspects from the execution
                let aspects = ProgramAspects(outcome: execution.outcome)
                
                // Map execution purpose to database execution purpose
                let dbExecutionPurpose: DatabaseExecutionPurpose
                switch purpose {
                case .fuzzing:
                    dbExecutionPurpose = .fuzzing
                case .programImport:
                    dbExecutionPurpose = .programImport
                case .minimization:
                    dbExecutionPurpose = .minimization
                case .checkForDeterministicBehavior:
                    dbExecutionPurpose = .deterministicCheck
                case .startup:
                    dbExecutionPurpose = .startup
                case .runtimeAssistedMutation:
                    dbExecutionPurpose = .runtimeAssistedMutation
                case .other:
                    dbExecutionPurpose = .other
                }
                
                // Cache execution data immediately before REPRL context becomes invalid
                let executionData = ExecutionData(
                    outcome: execution.outcome,
                    execTime: execution.execTime,
                    stdout: execution.stdout,
                    stderr: execution.stderr,
                    fuzzout: execution.fuzzout
                )
                
                // Store execution data with cached metadata
                Task {
                    await self.storeExecutionWithCachedData(program, executionData, dbExecutionPurpose, aspects)
                }
            } else {
                // DEBUG: Log when execution is not recorded
                if self.enableLogging {
                    self.logger.info("Skipping execution recording: program=\(self.currentExecutionProgram != nil), purpose=\(self.currentExecutionPurpose != nil)")
                }
            }
        }
        
        // Schedule periodic flush of execution batch
        fuzzer.timers.scheduleTask(every: 5.0, flushExecutionBatch)
        if enableLogging {
            logger.info("Scheduled execution batch flush every 5 seconds")
        }
        
        // Schedule periodic retry of fuzzer registration if it failed
        fuzzer.timers.scheduleTask(every: 30.0, retryFuzzerRegistration)
        if enableLogging {
            logger.info("Scheduled fuzzer registration retry every 30 seconds")
        }
        
        // Schedule periodic batch size update
        fuzzer.timers.scheduleTask(every: 5 * Minutes, updateBatchSize)
        if enableLogging {
            logger.info("Scheduled batch size update every 5 minutes")
        }
        
        // Load initial batch size from current execution speed
        updateBatchSize()
    }
    
    // MARK: - Corpus Protocol Implementation
    
    public var size: Int {
        // Query database for corpus size
        guard let fuzzerId = fuzzerId else { return 0 }
        // Use a cached value that gets updated periodically, or query synchronously
        // For now, return a placeholder - this will be improved with async queries
        return 0 // Will be updated to query DB
    }
    
    public var isEmpty: Bool {
        return size == 0
    }
    
    public var supportsFastStateSynchronization: Bool {
        return true
    }
    
    public func add(_ program: Program, _ aspects: ProgramAspects) {
        guard program.size > 0 else { return }
        
        // Filter out test programs with FUZZILLI_CRASH
        if DatabaseUtils.containsFuzzilliCrash(program: program) {
            if enableLogging {
                logger.info("Skipping program with FUZZILLI_CRASH (test case)")
            }
            return
        }
        
        guard let fuzzerId = fuzzerId else {
            if enableLogging {
                logger.warning("Cannot add program: fuzzer not registered")
            }
            return
        }
        
        // Store program directly to master DB asynchronously
        Task {
            do {
                let programHash = DatabaseUtils.calculateProgramHash(program: program)
                let metadata = ExecutionMetadata(lastOutcome: DatabaseExecutionOutcome(
                    id: DatabaseUtils.mapExecutionOutcome(outcome: aspects.outcome),
                    outcome: aspects.outcome.description,
                    description: aspects.outcome.description
                ))
                
                // Add to recent cache for fast access
                recentCacheLock.withLock {
                    recentProgramCache[programHash] = program
                    // Limit cache size
                    if recentProgramCache.count > maxRecentCacheSize {
                        let oldestKey = recentProgramCache.keys.first
                        if let key = oldestKey {
                            recentProgramCache.removeValue(forKey: key)
                        }
                    }
                }
                
                _ = try await storage.storeProgram(program: program, fuzzerId: fuzzerId, metadata: metadata)
            } catch {
                logger.error("Failed to store program in database: \(error)")
            }
        }
    }
    
    /// Add execution to batch for later processing
    private func addToExecutionBatch(_ program: Program, _ aspects: ProgramAspects, executionType: DatabaseExecutionPurpose) {
        // Use atomic operations to avoid blocking locks
        let shouldProcessBatch: [(Program, ProgramAspects, DatabaseExecutionPurpose)]? = executionBatchLock.withLock {
            pendingExecutions.append((program, aspects, executionType))
            let currentBatchSize = executionBatchSize
            let shouldProcess = pendingExecutions.count >= currentBatchSize
            if shouldProcess {
                let batch = pendingExecutions
                pendingExecutions.removeAll()
                return batch
            }
            return nil
        }
        
        // Process batch asynchronously if needed
        if let batch = shouldProcessBatch {
            Task {
                await processExecutionBatch(batch)
            }
        }
    }
    
    /// Process a batch of executions
    private func processExecutionBatch(_ batch: [(Program, ProgramAspects, DatabaseExecutionPurpose)]) async {
        guard let fuzzerId = fuzzerId else {
            logger.error("Cannot process execution batch: fuzzer not registered")
            return
        }
        
        if enableLogging {
            self.logger.info("Processing batch of \(batch.count) executions")
        }
        
        do {
            // Prepare batch data for programs (deduplicate by program hash)
            var uniquePrograms: [String: (Program, ExecutionMetadata)] = [:]
            var executionBatchData: [ExecutionBatchData] = []
            
            for (program, aspects, executionType) in batch {
                // Filter out test programs with FUZZILLI_CRASH (false positive crashes)
                if DatabaseUtils.containsFuzzilliCrash(program: program) {
                    if enableLogging {
                        logger.info("Skipping execution with FUZZILLI_CRASH (test case) in batch processing")
                    }
                    continue
                }
                
                let programHash = DatabaseUtils.calculateProgramHash(program: program)
                
                // Only store unique programs
                if uniquePrograms[programHash] == nil {
                    let metadata = ExecutionMetadata(lastOutcome: DatabaseExecutionOutcome(
                        id: DatabaseUtils.mapExecutionOutcome(outcome: aspects.outcome),
                        outcome: aspects.outcome.description,
                        description: aspects.outcome.description
                    ))
                    uniquePrograms[programHash] = (program, metadata)
                }
                
                // Prepare execution data, compute coverage percentage from evaluator if available
                let coveragePct: Double = {
                    if let coverageEvaluator = self.fuzzer.evaluator as? ProgramCoverageEvaluator {
                        return coverageEvaluator.currentScore * 100.0
                    } else {
                        return 0.0
                    }
                }()

                let executionData = ExecutionBatchData(
                    program: program,
                    executionType: executionType,
                    mutatorType: nil,
                    outcome: aspects.outcome,
                    coverage: coveragePct,
                    coverageEdges: (aspects as? CovEdgeSet).map { Set($0.getEdges().map { Int($0) }) } ?? Set<Int>()
                )
                executionBatchData.append(executionData)
            }
            
            // Batch store programs (only unique ones) directly to master DB
            let programBatch = Array(uniquePrograms.values)
            if !programBatch.isEmpty {
                _ = try await storage.storeProgramsBatch(programs: programBatch, fuzzerId: fuzzerId)
            }
            
            // Batch store executions directly to master DB
            if !executionBatchData.isEmpty {
                _ = try await storage.storeExecutionsBatch(executions: executionBatchData, fuzzerId: fuzzerId)
            }
            
            if enableLogging {
                self.logger.info("Completed batch processing: \(programBatch.count) unique programs, \(executionBatchData.count) executions")
            }
            
        } catch {
            logger.error("Failed to process execution batch: \(error)")
        }
    }
    
    /// Flush any pending executions in the batch
    private func flushExecutionBatch() {
        let batch = executionBatchLock.withLock {
            let batch = pendingExecutions
            pendingExecutions.removeAll()
            return batch
        }
        
        if !batch.isEmpty {
            if enableLogging {
                self.logger.info("Flushing \(batch.count) pending executions")
            }
            Task {
                await processExecutionBatch(batch)
            }
        }
    }
    
    /// Retry fuzzer registration if it failed initially
    private func retryFuzzerRegistration() {
        guard !fuzzerRegistered else { return }
        
        Task {
            do {
                let id = try await registerFuzzerWithRetry()
                fuzzerId = id
                fuzzerRegistered = true
                if enableLogging {
                    self.logger.info("Successfully registered fuzzer on retry with ID: \(id)")
                }
                
                // Process any queued executions
                let queuedExecutions = executionBatchLock.withLock {
                    let queuedExecutions = pendingExecutions
                    pendingExecutions.removeAll()
                    return queuedExecutions
                }
                
                if !queuedExecutions.isEmpty {
                    if enableLogging {
                        self.logger.info("Processing \(queuedExecutions.count) queued executions after successful registration")
                    }
                    await processExecutionBatch(queuedExecutions)
                }
                
            } catch {
                logger.warning("Fuzzer registration retry failed: \(error)")
            }
        }
    }
    
    public func randomElementForSplicing() -> Program {
        // Try to get from recent cache first
        if let cached = recentCacheLock.withLock({ recentProgramCache.values.randomElement() }) {
            return cached
        }
        
        // Fallback: query database for a random program
        // For now, return a minimal program to avoid blocking
        // This should be improved with async queries
        return Program()
    }
    
    public func randomElementForMutating() -> Program {
        // Try to get from recent cache first
        if let cached = recentCacheLock.withLock({ recentProgramCache.values.randomElement() }) {
            return cached
        }
        
        // Fallback: query database for a random program
        // For now, return a minimal program to avoid blocking
        // This should be improved with async queries
        return Program()
    }
    
    public func allPrograms() -> [Program] {
        // Return programs from recent cache
        return recentCacheLock.withLock {
            Array(recentProgramCache.values)
        }
    }
    
    public func exportState() throws -> Data {
        // Export from recent cache
        let programs = recentCacheLock.withLock {
            Array(recentProgramCache.values)
        }
        let res = try encodeProtobufCorpus(programs)
        if enableLogging {
            self.logger.info("Successfully serialized \(programs.count) programs from PostgreSQL corpus")
        }
        return res
    }
    
    public func importState(_ buffer: Data) throws {
        let newPrograms = try decodeProtobufCorpus(buffer)
        
        guard let fuzzerId = fuzzerId else {
            throw PostgreSQLStorageError.connectionFailed
        }
        
        // Store all programs to database
        Task {
            for program in newPrograms {
                let programHash = DatabaseUtils.calculateProgramHash(program: program)
                let metadata = ExecutionMetadata(lastOutcome: DatabaseExecutionOutcome(
                    id: DatabaseUtils.mapExecutionOutcome(outcome: .succeeded),
                    outcome: "Succeeded",
                    description: "Program executed successfully"
                ))
                
                do {
                    _ = try await storage.storeProgram(program: program, fuzzerId: fuzzerId, metadata: metadata)
                    
                    // Add to recent cache
                    recentCacheLock.withLock {
                        recentProgramCache[programHash] = program
                        if recentProgramCache.count > maxRecentCacheSize {
                            let oldestKey = recentProgramCache.keys.first
                            if let key = oldestKey {
                                recentProgramCache.removeValue(forKey: key)
                            }
                        }
                    }
                } catch {
                    logger.error("Failed to import program: \(error)")
                }
            }
        }
        
        if enableLogging {
            self.logger.info("Imported \(newPrograms.count) programs into PostgreSQL corpus")
        }
    }
    
    // MARK: - Database Operations
    
    /// Register fuzzer with retry logic
    private func registerFuzzerWithRetry() async throws -> Int {
        // Use the fuzzerInstanceId directly as the name to avoid double "fuzzer-" prefix
        let fuzzerName = fuzzerInstanceId
        let engineType = "v8" // This could be made configurable
        
        let maxRetries = 3
        var lastError: Error?
        
        for attempt in 1...maxRetries {
            do {
                if enableLogging {
                    self.logger.info("Attempting to register fuzzer (attempt \(attempt)/\(maxRetries))")
                }
                let id = try await storage.registerFuzzer(
                    name: fuzzerName,
                    engineType: engineType
                )
                if enableLogging {
                    self.logger.info("Successfully registered fuzzer with ID: \(id)")
                }
                return id
            } catch {
                lastError = error
                logger.warning("Failed to register fuzzer (attempt \(attempt)/\(maxRetries)): \(error)")
                
                if attempt < maxRetries {
                    // Wait before retrying
                    try await Task.sleep(nanoseconds: UInt64(attempt * 2 * 1_000_000_000)) // 2s, 4s, 6s
                }
            }
        }
        
        throw lastError ?? DatabasePoolError.initializationFailed("Failed to register fuzzer after \(maxRetries) attempts")
    }
    
    /// Cached execution data to avoid REPRL context issues
    private struct ExecutionData {
        let outcome: ExecutionOutcome
        let execTime: TimeInterval
        let stdout: String
        let stderr: String
        let fuzzout: String
    }
    
    /// Store execution with cached data to avoid REPRL context issues
    private func storeExecutionWithCachedData(_ program: Program, _ executionData: ExecutionData, _ executionType: DatabaseExecutionPurpose, _ aspects: ProgramAspects) async {
        // Filter out test programs with FUZZILLI_CRASH (false positive crashes)
        if DatabaseUtils.containsFuzzilliCrash(program: program) {
            if enableLogging {
                logger.info("Skipping execution storage for program with FUZZILLI_CRASH (test case)")
            }
            return
        }
        
        do {
            // Use the registered fuzzer ID
            guard let fuzzerId = fuzzerId else {
                if enableLogging {
                    self.logger.info("Cannot store execution: fuzzer not registered")
                }
                return
            }
            
            // DEBUG: Log execution storage attempt
            if enableLogging {
                self.logger.info("Storing execution: fuzzerId=\(fuzzerId), outcome=\(executionData.outcome), execTime=\(executionData.execTime)")
            }

            // Derive coverage percentage (0-100) from evaluator if available
            let coveragePct: Double = {
                if let coverageEvaluator = self.fuzzer.evaluator as? ProgramCoverageEvaluator {
                    return coverageEvaluator.currentScore * 100.0
                } else {
                    return 0.0
                }
            }()

            // Store both program and execution in a single transaction to avoid foreign key issues
            _ = try await storage.storeProgramAndExecution(
                program: program,
                fuzzerId: fuzzerId,
                executionType: executionType,
                outcome: executionData.outcome,
                coverage: coveragePct,
                executionTimeMs: Int(executionData.execTime * 1000),
                stdout: executionData.stdout,
                stderr: executionData.stderr,
                fuzzout: executionData.fuzzout,
                metadata: ExecutionMetadata(lastOutcome: DatabaseExecutionOutcome(
                    id: DatabaseUtils.mapExecutionOutcome(outcome: aspects.outcome),
                    outcome: aspects.outcome.description,
                    description: aspects.outcome.description
                ))
            )

            if enableLogging {
                self.logger.info("Successfully stored program and execution")
            }
            
        } catch {
            logger.error("Failed to store execution: \(String(reflecting: error))")
        }
    }
    
    /// Store coverage snapshot to database
    private func storeCoverageSnapshot(coverage: Double, programHash: String) async {
        guard let fuzzerId = fuzzerId else {
            if enableLogging {
                self.logger.info("Cannot store coverage snapshot: fuzzer not registered")
            }
            return
        }
        
        do {
            // Get edge counts from the coverage evaluator if available
            let edgesFound: Int
            let totalEdges: Int
            
            if let coverageEvaluator = self.fuzzer.evaluator as? ProgramCoverageEvaluator {
                edgesFound = Int(coverageEvaluator.getFoundEdgesCount())
                totalEdges = Int(coverageEvaluator.getTotalEdgesCount())
            } else {
                edgesFound = 0
                totalEdges = 0
            }
            
            let query = PostgresQuery(stringLiteral: """
                INSERT INTO coverage_snapshot (
                    fuzzer_id, coverage_percentage, program_hash, edges_found, total_edges, created_at
                ) VALUES (
                    \(fuzzerId), \(coverage), '\(programHash)', \(edgesFound), \(totalEdges), NOW()
                )
            """)
            
            try await storage.executeQuery(query)
            if enableLogging {
                self.logger.info("Stored coverage snapshot: \(String(format: "%.6f%%", coverage * 100)) (\(edgesFound)/\(totalEdges) edges)")
            }
            
        } catch {
            logger.error("Failed to store coverage snapshot: \(error)")
        }
    }
    
    
    // MARK: - Statistics and Monitoring
    
    /// Get corpus statistics
    public func getStatistics() -> CorpusStatistics {
        let recentCacheSize = recentCacheLock.withLock { recentProgramCache.count }
        
        // Get current coverage from evaluator if available
        var currentCoverage = 0.0
        if let coverageEvaluator = fuzzer.evaluator as? ProgramCoverageEvaluator {
            currentCoverage = coverageEvaluator.currentScore * 100.0
        }
        
        return CorpusStatistics(
            totalPrograms: recentCacheSize,
            totalExecutions: 0, // Will be queried from DB if needed
            averageCoverage: currentCoverage,
            currentCoverage: currentCoverage,
            pendingSyncOperations: 0, // No sync operations
            fuzzerInstanceId: fuzzerInstanceId
        )
    }
    
    /// Get enhanced statistics including database coverage
    public func getEnhancedStatistics() async -> EnhancedCorpusStatistics {
        let recentCacheSize = recentCacheLock.withLock { recentProgramCache.count }
        
        // Get database statistics
        var dbStats = DatabaseStatistics()
        if let fuzzerId = fuzzerId {
            do {
                dbStats = try await storage.getDatabaseStatistics(fuzzerId: fuzzerId)
            } catch {
                logger.warning("Failed to get database statistics: \(error)")
            }
        }
        
        // Get current coverage from evaluator
        var currentCoverage = 0.0
        if let coverageEvaluator = fuzzer.evaluator as? ProgramCoverageEvaluator {
            currentCoverage = coverageEvaluator.currentScore * 100.0
        }
        
        return EnhancedCorpusStatistics(
            totalPrograms: recentCacheSize,
            totalExecutions: dbStats.totalExecutions,
            averageCoverage: currentCoverage,
            pendingSyncOperations: 0, // No sync operations
            fuzzerInstanceId: fuzzerInstanceId,
            databasePrograms: dbStats.totalPrograms,
            databaseExecutions: dbStats.totalExecutions,
            databaseCrashes: dbStats.totalCrashes,
            activeFuzzers: dbStats.activeFuzzers,
            lastSyncTime: nil
        )
    }
}

// MARK: - Supporting Types

/// Statistics for PostgreSQL corpus
public struct CorpusStatistics {
    public let totalPrograms: Int
    public let totalExecutions: Int
    public let averageCoverage: Double
    public let currentCoverage: Double
    public let pendingSyncOperations: Int
    public let fuzzerInstanceId: String
    
    public var description: String {
        return "Programs: \(totalPrograms), Executions: \(totalExecutions), Avg Coverage: \(String(format: "%.2f%%", averageCoverage)), Current Coverage: \(String(format: "%.2f%%", currentCoverage)), Pending Sync: \(pendingSyncOperations)"
    }
}

/// Enhanced statistics for PostgreSQL corpus including database information
public struct EnhancedCorpusStatistics {
    public let totalPrograms: Int
    public let totalExecutions: Int
    public let averageCoverage: Double
    public let pendingSyncOperations: Int
    public let fuzzerInstanceId: String
    public let databasePrograms: Int
    public let databaseExecutions: Int
    public let databaseCrashes: Int
    public let activeFuzzers: Int
    public let lastSyncTime: Date?
    
    public var description: String {
        let syncTimeStr = lastSyncTime?.timeAgoString() ?? "Never"
        return "Programs: \(totalPrograms) (DB: \(databasePrograms)), Executions: \(totalExecutions) (DB: \(databaseExecutions)), Coverage: \(String(format: "%.2f%%", averageCoverage)), Crashes: \(databaseCrashes), Active Fuzzers: \(activeFuzzers), Last Sync: \(syncTimeStr)"
    }
}

/// Database statistics from PostgreSQL
public struct DatabaseStatistics {
    public let totalPrograms: Int
    public let totalExecutions: Int
    public let totalCrashes: Int
    public let activeFuzzers: Int
    
    public init(totalPrograms: Int = 0, totalExecutions: Int = 0, totalCrashes: Int = 0, activeFuzzers: Int = 0) {
        self.totalPrograms = totalPrograms
        self.totalExecutions = totalExecutions
        self.totalCrashes = totalCrashes
        self.activeFuzzers = activeFuzzers
    }
}

extension Date {
    func timeAgoString() -> String {
        let interval = Date().timeIntervalSince(self)
        let minutes = Int(interval / 60)
        let hours = Int(interval / 3600)
        let days = Int(interval / 86400)
        
        if days > 0 {
            return "\(days)d ago"
        } else if hours > 0 {
            return "\(hours)h ago"
        } else if minutes > 0 {
            return "\(minutes)m ago"
        } else {
            return "Just now"
        }
    }
}
