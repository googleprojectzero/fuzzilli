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
        resume: Bool = true // Default to resume from previous state
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
        self.storage = PostgreSQLStorage(databasePool: databasePool)
        
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
        Task {
            await commitPendingBatches()
        }
    }
    
    
    // MARK: - Performance Optimizations
    
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
        guard let fuzzerId = fuzzerId else { return }
        
        // Commit pending executions
        let queuedExecutions = executionBatchLock.withLock {
            let queuedExecutions = pendingExecutions
            pendingExecutions.removeAll()
            return queuedExecutions
        }
        
        if !queuedExecutions.isEmpty {
            do {
                try await processExecutionBatch(queuedExecutions)
                // logger.debug("Committed \(queuedExecutions.count) pending executions on exit")
            } catch {
                logger.error("Failed to commit pending executions on exit: \(error)")
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
                // logger.debug("Database pool initialized successfully")
                
                // Register this fuzzer instance in the database (only once)
                if !fuzzerRegistered {
                    do {
                        let id = try await registerFuzzerWithRetry()
                        fuzzerId = id
                        fuzzerRegistered = true
                        // logger.debug("Fuzzer registered in database with ID: \(id)")
                    } catch {
                        logger.error("Failed to register fuzzer after retries: \(error)")
                        // logger.debug("Fuzzer will continue without database registration - executions will be queued")
                    }
                }
                
            } catch {
                logger.error("Failed to initialize database pool: \(error)")
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
            }
        }
        
        // Schedule periodic synchronization with PostgreSQL
        fuzzer.timers.scheduleTask(every: syncInterval, syncWithDatabase)
        // logger.debug("Scheduled database sync every \(syncInterval) seconds")
        
        // Schedule periodic flush of execution batch
        fuzzer.timers.scheduleTask(every: 5.0, flushExecutionBatch)
        // logger.debug("Scheduled execution batch flush every 5 seconds")
        
        // Schedule periodic retry of fuzzer registration if it failed
        fuzzer.timers.scheduleTask(every: 30.0, retryFuzzerRegistration)
        // logger.debug("Scheduled fuzzer registration retry every 30 seconds")
        
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
        
        // logger.debug("Processing batch of \(batch.count) executions")
        
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
                
                // Prepare execution data
                let executionData = ExecutionBatchData(
                    program: program,
                    executionType: executionType,
                    mutatorType: nil,
                    outcome: aspects.outcome,
                    coverage: aspects is CovEdgeSet ? Double((aspects as! CovEdgeSet).count) : 0.0,
                    coverageEdges: Set<Int>() // Empty for now
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
            
            // logger.debug("Completed batch processing: \(programBatch.count) unique programs, \(executionBatchData.count) executions")
            
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
            // logger.debug("Flushing \(batch.count) pending executions")
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
                // logger.debug("Successfully registered fuzzer on retry with ID: \(id)")
                
                // Process any queued executions
                let queuedExecutions = executionBatchLock.withLock {
                    let queuedExecutions = pendingExecutions
                    pendingExecutions.removeAll()
                    return queuedExecutions
                }
                
                if !queuedExecutions.isEmpty {
                    // logger.debug("Processing \(queuedExecutions.count) queued executions after successful registration")
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
        if var (program, metadata) = programCache[programHash] {
            metadata.executionCount += 1
            metadata.lastExecutionTime = Date()
            programCache[programHash] = (program: program, metadata: metadata)
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
        // logger.debug("Successfully serialized \(programs.count) programs from PostgreSQL corpus")
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
        
        // logger.debug("Imported \(newPrograms.count) programs into PostgreSQL corpus")
    }
    
    // MARK: - Database Operations
    
    /// Load initial corpus from PostgreSQL database
    private func loadInitialCorpus() async {
        // logger.debug("Loading initial corpus from PostgreSQL...")
        
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
            
            // logger.debug("Found \(recentPrograms.count) recent programs to resume")
            
            // Add programs to the corpus
            cacheLock.lock()
            defer { cacheLock.unlock() }
            
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
            
            // logger.debug("Resumed PostgreSQL corpus with \(programs.count) programs")
            
            // If we have no programs, we need at least one to avoid empty corpus
            if programs.count == 0 {
                // logger.debug("No programs found to resume, corpus will start empty")
            }
            
        } catch {
            logger.error("Failed to load initial corpus from PostgreSQL: \(error)")
            // logger.debug("Corpus will start empty and build up from scratch")
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
        
        // Use synchronous lock for getting pending operations
        syncLock.lock()
        hashesToSync = Set(pendingSyncOperations)
        pendingSyncOperations.removeAll()
        syncLock.unlock()
        
        guard !hashesToSync.isEmpty else { return }
        
        // Syncing programs with PostgreSQL silently
        
        // Get programs to sync from cache
        cacheLock.lock()
        let programsToSync = hashesToSync.compactMap { hash -> (Program, ExecutionMetadata)? in
            guard let (program, metadata) = programCache[hash] else { return nil }
            return (program, metadata)
        }
        cacheLock.unlock()
        
        // Store each program in the database
        for (program, metadata) in programsToSync {
            do {
                // Use the registered fuzzer ID
                guard let fuzzerId = fuzzerId else {
                    logger.error("Cannot sync program: fuzzer not registered")
                    return
                }
                
                // Store the program with metadata
                let programHash = try await storage.storeProgram(
                    program: program,
                    fuzzerId: fuzzerId,
                    metadata: metadata
                )
                
                // Program synced to database silently
                
            } catch {
                logger.error("Failed to sync program to database: \(error)")
                // Re-add to pending sync for retry
                syncLock.lock()
                pendingSyncOperations.insert(DatabaseUtils.calculateProgramHash(program: program))
                syncLock.unlock()
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
                // logger.debug("Attempting to register fuzzer (attempt \(attempt)/\(maxRetries))")
                let id = try await storage.registerFuzzer(
                    name: fuzzerName,
                    engineType: engineType
                )
                // logger.debug("Successfully registered fuzzer with ID: \(id)")
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
                return // Silent fail for performance
            }
            
            // Store the program in the program table
            let programHash = try await storage.storeProgram(
                program: program,
                fuzzerId: fuzzerId,
                metadata: ExecutionMetadata(lastOutcome: DatabaseExecutionOutcome(
                    id: DatabaseUtils.mapExecutionOutcome(outcome: aspects.outcome),
                    outcome: aspects.outcome.description,
                    description: aspects.outcome.description
                ))
            )
            
            // Store the execution record with cached execution metadata
            let executionId = try await storage.storeExecution(
                program: program,
                fuzzerId: fuzzerId,
                executionType: executionType,
                outcome: executionData.outcome,
                coverage: aspects is CovEdgeSet ? Double((aspects as! CovEdgeSet).count) : 0.0,
                executionTimeMs: Int(executionData.execTime * 1000), // Convert to milliseconds
                stdout: executionData.stdout,
                stderr: executionData.stderr,
                fuzzout: executionData.fuzzout
            )
            
            // No logging for performance - just store silently
            
        } catch {
            // Silent fail for performance - errors are not critical for fuzzing
        }
    }
    
    /// Store execution with full metadata from Execution object
    private func storeExecutionWithMetadata(_ program: Program, _ execution: Execution, _ executionType: DatabaseExecutionPurpose, _ aspects: ProgramAspects) async {
        do {
            // Use the registered fuzzer ID
            guard let fuzzerId = fuzzerId else {
                logger.error("Cannot store execution: fuzzer not registered")
                return
            }
            
            // Store the program in the program table
            let programHash = try await storage.storeProgram(
                program: program,
                fuzzerId: fuzzerId,
                metadata: ExecutionMetadata(lastOutcome: DatabaseExecutionOutcome(
                    id: DatabaseUtils.mapExecutionOutcome(outcome: aspects.outcome),
                    outcome: aspects.outcome.description,
                    description: aspects.outcome.description
                ))
            )
            
            // Store the execution record with full execution metadata
            let executionId = try await storage.storeExecution(
                program: program,
                fuzzerId: fuzzerId,
                execution: execution,
                executionType: executionType,
                coverage: aspects is CovEdgeSet ? Double((aspects as! CovEdgeSet).count) : 0.0
            )
            
            // logger.debug("Stored execution with metadata: programHash=\(programHash), executionId=\(executionId), execTime=\(execution.execTime), outcome=\(execution.outcome)")
            
        } catch {
            logger.error("Failed to store execution with metadata: \(error)")
        }
    }
    
    /// Store a program execution in the database
    private func storeExecutionInDatabase(_ program: Program, _ aspects: ProgramAspects, executionType: DatabaseExecutionPurpose, mutatorType: String?) async {
        do {
            // Use the registered fuzzer ID
            guard let fuzzerId = fuzzerId else {
                logger.error("Cannot store execution: fuzzer not registered")
                return
            }
            
            // Store the program in the program table
            let programHash = try await storage.storeProgram(
                program: program,
                fuzzerId: fuzzerId,
                metadata: ExecutionMetadata(lastOutcome: DatabaseExecutionOutcome(
                    id: DatabaseUtils.mapExecutionOutcome(outcome: aspects.outcome),
                    outcome: aspects.outcome.description,
                    description: aspects.outcome.description
                ))
            )
            
            // Store the execution record
            let executionId = try await storage.storeExecution(
                program: program,
                fuzzerId: fuzzerId,
                executionType: executionType,
                mutatorType: mutatorType,
                outcome: aspects.outcome,
                coverage: aspects is CovEdgeSet ? Double((aspects as! CovEdgeSet).count) : 0.0
            )
            
            // logger.debug("Stored execution in database: programHash=\(programHash), executionId=\(executionId)")
            
        } catch {
            logger.error("Failed to store execution in database: \(error)")
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
        guard var (program, metadata) = programCache[programHash] else { return }
        updateExecutionMetadata(&metadata, aspects: aspects)
        programCache[programHash] = (program: program, metadata: metadata)
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
        
        // logger.debug("PostgreSQL corpus cleanup finished: \(self.programs.count) -> \(newPrograms.count)")
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
        
        return CorpusStatistics(
            totalPrograms: programs.count,
            totalExecutions: totalExecutions,
            averageCoverage: averageCoverage,
            pendingSyncOperations: pendingSyncOperations.count,
            fuzzerInstanceId: fuzzerInstanceId
        )
    }
}

// MARK: - Supporting Types

/// Statistics for PostgreSQL corpus
public struct CorpusStatistics {
    public let totalPrograms: Int
    public let totalExecutions: Int
    public let averageCoverage: Double
    public let pendingSyncOperations: Int
    public let fuzzerInstanceId: String
    
    public var description: String {
        return "Programs: \(totalPrograms), Executions: \(totalExecutions), Coverage: \(String(format: "%.2f%%", averageCoverage)), Pending Sync: \(pendingSyncOperations)"
    }
}
