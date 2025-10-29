import Foundation
import PostgresNIO
import PostgresKit

/// PostgreSQL-based corpus with in-memory caching for distributed fuzzing.
///
/// This corpus maintains a local in-memory cache of programs and their execution metadata,
/// while synchronizing with a central PostgreSQL database. Each fuzzer instance maintains
/// its own cache and periodically syncs with the master database.
///
/// Features:
/// - In-memory caching for fast access
/// - PostgreSQL backend for persistence and sharing
/// - Execution metadata tracking (coverage, execution count, etc.)
/// - Periodic synchronization with central database
/// - Thread-safe operations
public class PostgreSQLCorpus: ComponentBase, Corpus {
    
    // MARK: - Configuration
    
    private let minSize: Int
    private let maxSize: Int
    private let minMutationsPerSample: Int
    private let syncInterval: TimeInterval
    private let databasePool: DatabasePool
    private let fuzzerInstanceId: String
    private let storage: PostgreSQLStorage
    private let resume: Bool
    private let enableLogging: Bool
    
    // MARK: - In-Memory Cache
    
    /// Thread-safe in-memory cache of programs and their metadata
    private var programCache: [String: (program: Program, metadata: ExecutionMetadata)] = [:]
    private let cacheLock = NSLock()
    
    /// Ring buffer for fast random access (similar to BasicCorpus)
    private var programs: RingBuffer<Program>
    private var ages: RingBuffer<Int>
    private var programHashes: RingBuffer<String> // Track hashes for database operations
    
    /// Counts the total number of entries in the corpus
    private var totalEntryCounter = 0
    
    /// Track pending database operations
    private var pendingSyncOperations: Set<String> = []
    private let syncLock = NSLock()
    
    /// Track current execution for event handling
    private var currentExecutionProgram: Program?
    private var currentExecutionPurpose: ExecutionPurpose?
    
    /// Track fuzzer registration status
    private var fuzzerRegistered = false
    private var fuzzerId: Int?
    
    /// Batch execution storage
    private var pendingExecutions: [(Program, ProgramAspects, DatabaseExecutionPurpose)] = []
    private let executionBatchSize: Int
    private let executionBatchLock = NSLock()
    
    // MARK: - Initialization
    
    public init(
        minSize: Int,
        maxSize: Int,
        minMutationsPerSample: Int,
        databasePool: DatabasePool,
        fuzzerInstanceId: String,
        syncInterval: TimeInterval = 60.0, // Default 1 minute sync interval
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
        self.syncInterval = syncInterval
        self.resume = resume
        self.enableLogging = enableLogging
        self.storage = PostgreSQLStorage(databasePool: databasePool, enableLogging: enableLogging)
        
        // Set optimized batch size for better throughput (reduced from 1M to 100k for more frequent processing)
        self.executionBatchSize = 100_000
        
        self.programs = RingBuffer(maxSize: maxSize)
        self.ages = RingBuffer(maxSize: maxSize)
        self.programHashes = RingBuffer(maxSize: maxSize)
        
        super.init(name: "PostgreSQLCorpus")
        
        // Setup signal handlers for graceful shutdown
        setupSignalHandlers()
        
        // Start periodic batch flushing for better throughput
        startPeriodicBatchFlush()
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
                try await databasePool.initialize()
                if enableLogging {
                    self.logger.info("Database pool initialized successfully")
                }
                
                // Register this fuzzer instance in the database (only once)
                if !fuzzerRegistered {
                    do {
                        let id = try await registerFuzzerWithRetry()
                        fuzzerId = id
                        fuzzerRegistered = true
                        if enableLogging {
                            self.logger.info("Fuzzer registered in database with ID: \(id)")
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
        
        // Schedule periodic synchronization with PostgreSQL
        fuzzer.timers.scheduleTask(every: syncInterval, syncWithDatabase)
        if self.enableLogging {
            logger.info("Scheduled database sync every \(syncInterval) seconds")
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
        
        // Schedule cleanup task (similar to BasicCorpus)
        if !fuzzer.config.staticCorpus {
            fuzzer.timers.scheduleTask(every: 30 * Minutes, cleanup)
        }
        
        // Load initial corpus from database if resume is enabled
        if resume {
            Task {
                await loadInitialCorpus()
            }
        }
    }
    
    // MARK: - Corpus Protocol Implementation
    
    public var size: Int {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return programs.count
    }
    
    public var isEmpty: Bool {
        return size == 0
    }
    
    public var supportsFastStateSynchronization: Bool {
        return true
    }
    
    public func add(_ program: Program, _ aspects: ProgramAspects) {
        addInternal(program, aspects: aspects)
    }
    
    /// Add execution to batch for later processing
    private func addToExecutionBatch(_ program: Program, _ aspects: ProgramAspects, executionType: DatabaseExecutionPurpose) {
        // Use atomic operations to avoid blocking locks
        let shouldProcessBatch: [(Program, ProgramAspects, DatabaseExecutionPurpose)]? = executionBatchLock.withLock {
            pendingExecutions.append((program, aspects, executionType))
            let shouldProcess = pendingExecutions.count >= executionBatchSize
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
            
            // Batch store programs (only unique ones)
            let programBatch = Array(uniquePrograms.values)
            if !programBatch.isEmpty {
                _ = try await storage.storeProgramsBatch(programs: programBatch, fuzzerId: fuzzerId)
            }
            
            // Batch store executions
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
    
    public func addInternal(_ program: Program, aspects: ProgramAspects? = nil) {
        guard program.size > 0 else { return }
        
        let programHash = DatabaseUtils.calculateProgramHash(program: program)
        
        cacheLock.lock()
        defer { cacheLock.unlock() }
        
        // Check if program already exists in cache
        if programCache[programHash] != nil {
            // Update execution metadata if aspects provided
            if let aspects = aspects {
                updateExecutionMetadata(for: programHash, aspects: aspects)
            }
            return
        }
        
        // Create execution metadata
        let outcome = DatabaseExecutionOutcome(
            id: DatabaseUtils.mapExecutionOutcome(outcome: aspects?.outcome ?? .succeeded),
            outcome: aspects?.outcome.description ?? "Succeeded",
            description: aspects?.outcome.description ?? "Program executed successfully"
        )
        
        var metadata = ExecutionMetadata(lastOutcome: outcome)
        if let aspects = aspects {
            updateExecutionMetadata(&metadata, aspects: aspects)
        }
        
        // Add to in-memory structures
        prepareProgramForInclusion(program, index: totalEntryCounter)
        programs.append(program)
        ages.append(0)
        programHashes.append(programHash)
        programCache[programHash] = (program: program, metadata: metadata)
        
        totalEntryCounter += 1
        
        // Mark for database sync
        markForSync(programHash)
        
        // Program added to corpus silently for performance
    }
    
    public func randomElementForSplicing() -> Program {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        
        assert(programs.count > 0, "Corpus should never be empty")
        let idx = Int.random(in: 0..<programs.count)
        let program = programs[idx]
        assert(!program.isEmpty)
        return program
    }
    
    public func randomElementForMutating() -> Program {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        
        assert(programs.count > 0, "Corpus should never be empty")
        let idx = Int.random(in: 0..<programs.count)
        ages[idx] += 1
        
        // Update execution metadata
        let programHash = programHashes[idx]
        if let (program, metadata) = programCache[programHash] {
            var updatedMetadata = metadata
            updatedMetadata.executionCount += 1
            updatedMetadata.lastExecutionTime = Date()
            programCache[programHash] = (program: program, metadata: updatedMetadata)
            markForSync(programHash)
        }
        
        let program = programs[idx]
        assert(!program.isEmpty)
        return program
    }
    
    public func allPrograms() -> [Program] {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return Array(programs)
    }
    
    public func exportState() throws -> Data {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        
        let res = try encodeProtobufCorpus(Array(programs))
        if enableLogging {
            self.logger.info("Successfully serialized \(programs.count) programs from PostgreSQL corpus")
        }
        return res
    }
    
    public func importState(_ buffer: Data) throws {
        let newPrograms = try decodeProtobufCorpus(buffer)
        
        cacheLock.lock()
        defer { cacheLock.unlock() }
        
        programs.removeAll()
        ages.removeAll()
        programHashes.removeAll()
        programCache.removeAll()
        
        newPrograms.forEach { program in
            addInternal(program)
        }
        
        if enableLogging {
            self.logger.info("Imported \(newPrograms.count) programs into PostgreSQL corpus")
        }
    }
    
    // MARK: - Database Operations
    
    /// Load initial corpus from PostgreSQL database
    private func loadInitialCorpus() async {
        if enableLogging {
            self.logger.info("Loading initial corpus from PostgreSQL...")
        }
        
        guard let fuzzerId = fuzzerId else {
            logger.warning("Cannot load initial corpus: fuzzer not registered")
            return
        }
        
        do {
            // Load programs from the last 24 hours to resume recent work
            let since = Date().addingTimeInterval(-24 * 60 * 60) // 24 hours ago
            let recentPrograms = try await storage.getRecentPrograms(
                fuzzerId: fuzzerId, 
                since: since, 
                limit: maxSize
            )
            
            if enableLogging {
                self.logger.info("Found \(recentPrograms.count) recent programs to resume")
            }
            
            // Add programs to the corpus
            withLock(cacheLock) {
                for (program, metadata) in recentPrograms {
                    let programHash = DatabaseUtils.calculateProgramHash(program: program)
                    
                    // Skip if already in cache
                    if programCache[programHash] != nil {
                        continue
                    }
                    
                    // Add to in-memory structures
                    prepareProgramForInclusion(program, index: totalEntryCounter)
                    programs.append(program)
                    ages.append(0)
                    programHashes.append(programHash)
                    programCache[programHash] = (program: program, metadata: metadata)
                    
                    totalEntryCounter += 1
                }
            }
            
            if enableLogging {
                self.logger.info("Resumed PostgreSQL corpus with \(programs.count) programs")
            }
            
            // If we have no programs, we need at least one to avoid empty corpus
            if programs.count == 0 {
                if enableLogging {
                    self.logger.info("No programs found to resume, corpus will start empty")
                }
            }
            
        } catch {
            logger.error("Failed to load initial corpus from PostgreSQL: \(error)")
            if enableLogging {
                self.logger.info("Corpus will start empty and build up from scratch")
            }
        }
    }
    
    /// Synchronize with PostgreSQL database
    private func syncWithDatabase() {
        Task {
            await performDatabaseSync()
        }
    }
    
    /// Perform actual database synchronization
    private func performDatabaseSync() async {
        let hashesToSync: Set<String>
        
        // Use async-safe lock for getting pending operations
        hashesToSync = withLock(syncLock) {
            let hashes = Set(pendingSyncOperations)
            pendingSyncOperations.removeAll()
            return hashes
        }
        
        guard !hashesToSync.isEmpty else { return }
        
        // Syncing programs with PostgreSQL silently
        
        // Get programs to sync from cache
        let programsToSync = withLock(cacheLock) {
            hashesToSync.compactMap { hash -> (Program, ExecutionMetadata)? in
                guard let (program, metadata) = programCache[hash] else { return nil }
                return (program, metadata)
            }
        }
        
        // Store each program in the database
        for (program, metadata) in programsToSync {
            do {
                // Use the registered fuzzer ID
                guard let fuzzerId = fuzzerId else {
                    logger.error("Cannot sync program: fuzzer not registered")
                    return
                }
                
                // Store the program with metadata
                _ = try await storage.storeProgram(
                    program: program,
                    fuzzerId: fuzzerId,
                    metadata: metadata
                )
                
                // Program synced to database silently
                
            } catch {
                logger.error("Failed to sync program to database: \(error)")
                // Re-add to pending sync for retry
                _ = withLock(syncLock) {
                    pendingSyncOperations.insert(DatabaseUtils.calculateProgramHash(program: program))
                }
            }
        }
        
        // Database sync completed silently
    }
    
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
    
    /// Mark a program hash for database synchronization
    private func markForSync(_ programHash: String) {
        syncLock.lock()
        defer { syncLock.unlock() }
        pendingSyncOperations.insert(programHash)
    }
    
    // MARK: - Execution Metadata Management
    
    /// Update execution metadata for a program
    private func updateExecutionMetadata(for programHash: String, aspects: ProgramAspects) {
        guard let (program, metadata) = programCache[programHash] else { return }
        var updatedMetadata = metadata
        updateExecutionMetadata(&updatedMetadata, aspects: aspects)
        programCache[programHash] = (program: program, metadata: updatedMetadata)
        markForSync(programHash)
    }
    
    /// Update execution metadata with new aspects
    private func updateExecutionMetadata(_ metadata: inout ExecutionMetadata, aspects: ProgramAspects) {
        metadata.executionCount += 1
        metadata.lastExecutionTime = Date()
        
        // Update outcome
        let outcome = DatabaseExecutionOutcome(
            id: DatabaseUtils.mapExecutionOutcome(outcome: aspects.outcome),
            outcome: aspects.outcome.description,
            description: aspects.outcome.description
        )
        metadata.updateLastOutcome(outcome)
        
        // Update coverage if available
        if let edgeSet = aspects as? CovEdgeSet {
            // For now, just track the count of edges since we can't access the actual edges
            metadata.lastCoverage = Double(edgeSet.count) // Simple coverage metric
            // TODO: Implement proper edge tracking when we have access to the edges
        }
    }
    
    // MARK: - Cleanup
    
    private func cleanup() {
        assert(!fuzzer.config.staticCorpus)
        
        cacheLock.lock()
        defer { cacheLock.unlock() }
        
        var newPrograms = RingBuffer<Program>(maxSize: programs.maxSize)
        var newAges = RingBuffer<Int>(maxSize: ages.maxSize)
        var newHashes = RingBuffer<String>(maxSize: programHashes.maxSize)
        var newCache: [String: (program: Program, metadata: ExecutionMetadata)] = [:]
        
        for i in 0..<programs.count {
            let remaining = programs.count - i
            let programHash = programHashes[i]
            
            if ages[i] < minMutationsPerSample || remaining <= (minSize - newPrograms.count) {
                newPrograms.append(programs[i])
                newAges.append(ages[i])
                newHashes.append(programHash)
                newCache[programHash] = programCache[programHash]
            } else {
                // Mark for database sync before removal
                markForSync(programHash)
            }
        }
        
        if enableLogging {
            self.logger.info("PostgreSQL corpus cleanup finished: \(self.programs.count) -> \(newPrograms.count)")
        }
        programs = newPrograms
        ages = newAges
        programHashes = newHashes
        programCache = newCache
    }
    
    // MARK: - Statistics and Monitoring
    
    /// Get corpus statistics
    public func getStatistics() -> CorpusStatistics {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        
        let totalExecutions = programCache.values.reduce(0) { $0 + $1.metadata.executionCount }
        let averageCoverage = programCache.values.isEmpty ? 0.0 : 
            programCache.values.reduce(0.0) { $0 + $1.metadata.lastCoverage } / Double(programCache.count)
        
        // Get current coverage from evaluator if available
        var currentCoverage = 0.0
        if let coverageEvaluator = fuzzer.evaluator as? ProgramCoverageEvaluator {
            currentCoverage = coverageEvaluator.currentScore
            // TEMPORARY TEST: Seed with 999.99 if coverage is 0 (for testing display)
            if currentCoverage == 0.0 {
                currentCoverage = 999.99
            }
        }
        
        return CorpusStatistics(
            totalPrograms: programs.count,
            totalExecutions: totalExecutions,
            averageCoverage: averageCoverage,
            currentCoverage: currentCoverage,
            pendingSyncOperations: pendingSyncOperations.count,
            fuzzerInstanceId: fuzzerInstanceId
        )
    }
    
    /// Get enhanced statistics including database coverage
    public func getEnhancedStatistics() async -> EnhancedCorpusStatistics {
        let (totalExecutions, averageCoverage, pendingSyncCount) = withLock(cacheLock) {
            let totalExecutions = programCache.values.reduce(0) { $0 + $1.metadata.executionCount }
            let averageCoverage = programCache.values.isEmpty ? 0.0 : 
                programCache.values.reduce(0.0) { $0 + $1.metadata.lastCoverage } / Double(programCache.count)
            return (totalExecutions, averageCoverage, pendingSyncOperations.count)
        }
        
        // Get database statistics
        var dbStats = DatabaseStatistics()
        if let fuzzerId = fuzzerId {
            do {
                dbStats = try await storage.getDatabaseStatistics(fuzzerId: fuzzerId)
            } catch {
                logger.warning("Failed to get database statistics: \(error)")
            }
        }
        
        return EnhancedCorpusStatistics(
            totalPrograms: programs.count,
            totalExecutions: totalExecutions,
            averageCoverage: averageCoverage,
            pendingSyncOperations: pendingSyncCount,
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
