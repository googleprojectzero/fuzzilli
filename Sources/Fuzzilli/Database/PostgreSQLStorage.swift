import Foundation
import PostgresNIO
import PostgresKit

/// PostgreSQL storage backend for Fuzzilli corpus and execution data
///
/// This class provides methods to store and retrieve programs, executions, crashes,
/// and metadata from PostgreSQL database. It handles the actual database operations
/// that the PostgreSQLCorpus uses for persistence and synchronization.
///
/// Note: This is a simplified implementation that logs operations instead of
/// performing actual database operations. The actual database integration will
/// be implemented when we have a working PostgreSQL setup.
public class PostgreSQLStorage {
    
    // MARK: - Properties
    
    private let databasePool: DatabasePool
    private let logger: Logging.Logger
    
    // MARK: - Initialization
    
    public init(databasePool: DatabasePool) {
        self.databasePool = databasePool
        self.logger = Logging.Logger(label: "PostgreSQLStorage")
    }
    
    // MARK: - Fuzzer Management
    
    /// Register a new fuzzer instance in the database
    public func registerFuzzer(name: String, engineType: String, hostname: String? = nil) async throws -> Int {
        logger.debug("Registering fuzzer: name=\(name), engineType=\(engineType), hostname=\(hostname ?? "none")")
        
        // Use direct connection to avoid connection pool deadlock
        guard let eventLoopGroup = databasePool.getEventLoopGroup() else {
            throw PostgreSQLStorageError.noResult
        }
        
        let connection = try await PostgresConnection.connect(
            on: eventLoopGroup.next(),
            configuration: PostgresConnection.Configuration(
                host: "localhost",
                port: 5433,
                username: "fuzzilli",
                password: "fuzzilli123",
                database: "fuzzilli",
                tls: .disable
            ),
            id: 0,
            logger: logger
        )
        defer { Task { _ = try? await connection.close() } }
        
        // First, check if a fuzzer with this name already exists
        let checkQuery: PostgresQuery = "SELECT fuzzer_id, status FROM main WHERE fuzzer_name = \(name)"
        let checkResult = try await connection.query(checkQuery, logger: self.logger)
        let checkRows = try await checkResult.collect()
        
        if let existingRow = checkRows.first {
            let existingFuzzerId = try existingRow.decode(Int.self, context: .default)
            let existingStatus = try existingRow.decode(String.self, context: .default)
            
            // Update status to active if it was inactive
            if existingStatus != "active" {
                let updateQuery: PostgresQuery = "UPDATE main SET status = 'active' WHERE fuzzer_id = \(existingFuzzerId)"
                try await connection.query(updateQuery, logger: self.logger)
                logger.debug("Reactivated existing fuzzer: fuzzerId=\(existingFuzzerId)")
            } else {
                logger.debug("Reusing existing active fuzzer: fuzzerId=\(existingFuzzerId)")
            }
            
            return existingFuzzerId
        }
        
        // If no existing fuzzer found, create a new one
        let insertQuery: PostgresQuery = """
            INSERT INTO main (fuzzer_name, engine_type, status) 
            VALUES (\(name), \(engineType), 'active') 
            RETURNING fuzzer_id
        """
        
        let result = try await connection.query(insertQuery, logger: self.logger)
        let rows = try await result.collect()
        guard let row = rows.first else {
            throw PostgreSQLStorageError.noResult
        }
        
        let fuzzerId = try row.decode(Int.self, context: .default)
        self.logger.debug("Created new fuzzer: fuzzerId=\(fuzzerId)")
        return fuzzerId
    }
    
    /// Get fuzzer instance by name
    public func getFuzzer(name: String) async throws -> FuzzerInstance? {
        logger.debug("Getting fuzzer: name=\(name)")
        
        // Use direct connection to avoid connection pool deadlock
        guard let eventLoopGroup = databasePool.getEventLoopGroup() else {
            throw PostgreSQLStorageError.noResult
        }
        
        let connection = try await PostgresConnection.connect(
            on: eventLoopGroup.next(),
            configuration: PostgresConnection.Configuration(
                host: "localhost",
                port: 5433,
                username: "fuzzilli",
                password: "fuzzilli123",
                database: "fuzzilli",
                tls: .disable
            ),
            id: 0,
            logger: logger
        )
        defer { Task { _ = try? await connection.close() } }
        
        let query: PostgresQuery = "SELECT fuzzer_id, created_at, fuzzer_name, engine_type, status FROM main WHERE fuzzer_name = \(name)"
        let result = try await connection.query(query, logger: self.logger)
        let rows = try await result.collect()
        
        guard let row = rows.first else {
            return nil
        }
        
        let fuzzerId = try row.decode(Int.self, context: .default)
        let createdAt = try row.decode(Date.self, context: .default)
        let fuzzerName = try row.decode(String.self, context: .default)
        let engineType = try row.decode(String.self, context: .default)
        let status = try row.decode(String.self, context: .default)
        
        let fuzzer = FuzzerInstance(
            fuzzerId: fuzzerId,
            createdAt: createdAt,
            fuzzerName: fuzzerName,
            engineType: engineType,
            status: status
        )
        
        self.logger.debug("Fuzzer found: \(fuzzerName) (ID: \(fuzzerId))")
        return fuzzer
    }
    
    /// Get database statistics for a specific fuzzer
    public func getDatabaseStatistics(fuzzerId: Int) async throws -> DatabaseStatistics {
        logger.debug("Getting database statistics for fuzzer: \(fuzzerId)")
        
        // Use direct connection to avoid connection pool deadlock
        guard let eventLoopGroup = databasePool.getEventLoopGroup() else {
            throw PostgreSQLStorageError.noResult
        }
        
        let connection = try await PostgresConnection.connect(
            on: eventLoopGroup.next(),
            configuration: PostgresConnection.Configuration(
                host: "localhost",
                port: 5433,
                username: "fuzzilli",
                password: "fuzzilli123",
                database: "fuzzilli",
                tls: .disable
            ),
            id: 0,
            logger: logger
        )
        defer { Task { _ = try? await connection.close() } }
        
        // Get program count for this fuzzer
        let programQuery: PostgresQuery = "SELECT COUNT(*) FROM fuzzer WHERE fuzzer_id = \(fuzzerId)"
        let programResult = try await connection.query(programQuery, logger: self.logger)
        let programRows = try await programResult.collect()
        let totalPrograms = try programRows.first?.decode(Int.self, context: .default) ?? 0
        
        // Get execution count for this fuzzer
        let executionQuery: PostgresQuery = "SELECT COUNT(*) FROM execution e JOIN program p ON e.program_base64 = p.program_base64 WHERE p.fuzzer_id = \(fuzzerId)"
        let executionResult = try await connection.query(executionQuery, logger: self.logger)
        let executionRows = try await executionResult.collect()
        let totalExecutions = try executionRows.first?.decode(Int.self, context: .default) ?? 0
        
        // Get crash count for this fuzzer
        let crashQuery: PostgresQuery = """
            SELECT COUNT(*) FROM execution e 
            JOIN program p ON e.program_base64 = p.program_base64 
            JOIN execution_outcome eo ON e.execution_outcome_id = eo.id 
            WHERE p.fuzzer_id = \(fuzzerId) AND eo.outcome = 'Crashed'
        """
        let crashResult = try await connection.query(crashQuery, logger: self.logger)
        let crashRows = try await crashResult.collect()
        let totalCrashes = try crashRows.first?.decode(Int.self, context: .default) ?? 0
        
        // Get active fuzzers count
        let activeQuery: PostgresQuery = "SELECT COUNT(*) FROM main WHERE status = 'active'"
        let activeResult = try await connection.query(activeQuery, logger: self.logger)
        let activeRows = try await activeResult.collect()
        let activeFuzzers = try activeRows.first?.decode(Int.self, context: .default) ?? 0
        
        let stats = DatabaseStatistics(
            totalPrograms: totalPrograms,
            totalExecutions: totalExecutions,
            totalCrashes: totalCrashes,
            activeFuzzers: activeFuzzers
        )
        
        self.logger.debug("Database statistics: Programs: \(stats.totalPrograms), Executions: \(stats.totalExecutions), Crashes: \(stats.totalCrashes), Active Fuzzers: \(stats.activeFuzzers)")
        return stats
    }
    
    // MARK: - Program Management
    
    /// Store multiple programs in batch for better performance
    public func storeProgramsBatch(programs: [(Program, ExecutionMetadata)], fuzzerId: Int) async throws -> [String] {
        guard !programs.isEmpty else { return [] }
        
        // Use direct connection to avoid connection pool deadlock
        guard let eventLoopGroup = databasePool.getEventLoopGroup() else {
            throw PostgreSQLStorageError.noResult
        }
        
        let connection = try await PostgresConnection.connect(
            on: eventLoopGroup.next(),
            configuration: PostgresConnection.Configuration(
                host: "localhost",
                port: 5433,
                username: "fuzzilli",
                password: "fuzzilli123",
                database: "fuzzilli",
                tls: .disable
            ),
            id: 0,
            logger: logger
        )
        defer { Task { _ = try? await connection.close() } }
        
        var programHashes: [String] = []
        var fuzzerValues: [String] = []
        var programValues: [String] = []
        
        // Prepare batch data
        for (program, _) in programs {
            let programHash = DatabaseUtils.calculateProgramHash(program: program)
            let programBase64 = DatabaseUtils.encodeProgramToBase64(program: program)
            programHashes.append(programHash)
            
            // Escape single quotes in strings
            let escapedProgramBase64 = programBase64.replacingOccurrences(of: "'", with: "''")
            
            fuzzerValues.append("('\(escapedProgramBase64)', \(fuzzerId), \(program.size), '\(programHash)')")
            programValues.append("('\(escapedProgramBase64)', \(fuzzerId), \(program.size), '\(programHash)')")
        }
        
        // Batch insert into fuzzer table
        if !fuzzerValues.isEmpty {
            let fuzzerQueryString = "INSERT INTO fuzzer (program_base64, fuzzer_id, program_size, program_hash) VALUES " + 
                fuzzerValues.joined(separator: ", ") + " ON CONFLICT (program_base64) DO NOTHING"
            let fuzzerQuery = PostgresQuery(stringLiteral: fuzzerQueryString)
            try await connection.query(fuzzerQuery, logger: self.logger)
        }
        
        // Batch insert into program table
        if !programValues.isEmpty {
            let programQueryString = "INSERT INTO program (program_base64, fuzzer_id, program_size, program_hash) VALUES " + 
                programValues.joined(separator: ", ") + " ON CONFLICT (program_base64) DO UPDATE SET " +
                "fuzzer_id = EXCLUDED.fuzzer_id, program_size = EXCLUDED.program_size, " +
                "program_hash = EXCLUDED.program_hash"
            let programQuery = PostgresQuery(stringLiteral: programQueryString)
            try await connection.query(programQuery, logger: self.logger)
        }
        
        return programHashes
    }
    
    /// Store both program and execution in a single transaction to avoid foreign key issues
    public func storeProgramAndExecution(
        program: Program,
        fuzzerId: Int,
        executionType: DatabaseExecutionPurpose,
        outcome: ExecutionOutcome,
        coverage: Double,
        executionTimeMs: Int,
        stdout: String?,
        stderr: String?,
        fuzzout: String?,
        metadata: ExecutionMetadata
    ) async throws -> (programHash: String, executionId: Int) {
        let programHash = DatabaseUtils.calculateProgramHash(program: program)
        let programBase64 = DatabaseUtils.encodeProgramToBase64(program: program)
        logger.debug("Storing program and execution: hash=\(programHash), fuzzerId=\(fuzzerId), executionCount=\(metadata.executionCount)")
        
        // Use direct connection to avoid connection pool deadlock
        guard let eventLoopGroup = databasePool.getEventLoopGroup() else {
            throw PostgreSQLStorageError.noResult
        }
        
        let connection = try await PostgresConnection.connect(
            on: eventLoopGroup.next(),
            configuration: PostgresConnection.Configuration(
                host: "localhost",
                port: 5433,
                username: "fuzzilli",
                password: "fuzzilli123",
                database: "fuzzilli",
                tls: .disable
            ),
            id: 0,
            logger: logger
        )
        defer { Task { _ = try? await connection.close() } }
        
        // Start transaction
        try await connection.query("BEGIN", logger: self.logger)
        
        do {
            // Insert into fuzzer table (corpus)
            let fuzzerQuery = PostgresQuery(stringLiteral: """
                INSERT INTO fuzzer (program_base64, fuzzer_id, program_size, program_hash) 
                VALUES ('\(programBase64)', \(fuzzerId), \(program.size), '\(programHash)') 
                ON CONFLICT (program_base64) DO NOTHING
            """)
            try await connection.query(fuzzerQuery, logger: self.logger)
            
            // Insert into program table (executed programs) - use DO UPDATE to ensure it exists
            let programQuery = PostgresQuery(stringLiteral: """
                INSERT INTO program (program_base64, fuzzer_id, program_size, program_hash) 
                VALUES ('\(programBase64)', \(fuzzerId), \(program.size), '\(programHash)') 
                ON CONFLICT (program_base64) DO UPDATE SET 
                    fuzzer_id = EXCLUDED.fuzzer_id,
                    program_size = EXCLUDED.program_size,
                    program_hash = EXCLUDED.program_hash
            """)
            try await connection.query(programQuery, logger: self.logger)
            
            // Now store the execution
            let executionTypeId = DatabaseUtils.mapExecutionType(purpose: executionType)
            
            // Extract execution metadata from ExecutionOutcome
            let (signalCode, exitCode) = extractExecutionMetadata(from: outcome)
            
            // Use signal-aware mapping for execution outcomes
            let outcomeId = DatabaseUtils.mapExecutionOutcomeWithSignal(outcome: outcome, signalCode: signalCode)
            
            // Prepare parameters for NULL handling
            let signalCodeValue = signalCode != nil ? "\(signalCode!)" : "NULL"
            let exitCodeValue = exitCode != nil ? "\(exitCode!)" : "NULL"
            let stdoutValue = stdout != nil ? "'\(stdout!.replacingOccurrences(of: "'", with: "''"))'" : "NULL"
            let stderrValue = stderr != nil ? "'\(stderr!.replacingOccurrences(of: "'", with: "''"))'" : "NULL"
            let fuzzoutValue = fuzzout != nil ? "'\(fuzzout!.replacingOccurrences(of: "'", with: "''"))'" : "NULL"
            
            let executionQuery = PostgresQuery(stringLiteral: """
                INSERT INTO execution (
                    program_base64, execution_type_id, mutator_type_id, 
                    execution_outcome_id, coverage_total, execution_time_ms, 
                    signal_code, exit_code, stdout, stderr, fuzzout, 
                    feedback_vector, created_at
                ) VALUES (
                    '\(programBase64)', \(executionTypeId), 
                    NULL, \(outcomeId), \(coverage), 
                    \(executionTimeMs), \(signalCodeValue), \(exitCodeValue), 
                    \(stdoutValue), \(stderrValue), \(fuzzoutValue), 
                    NULL, NOW()
                ) RETURNING execution_id
            """)
            
            let result = try await connection.query(executionQuery, logger: self.logger)
            let rows = try await result.collect()
            guard let row = rows.first else {
                throw PostgreSQLStorageError.noResult
            }
            
            let executionId = try row.decode(Int.self, context: PostgresDecodingContext.default)
            
            // Commit transaction
            try await connection.query("COMMIT", logger: self.logger)
            
            self.logger.debug("Program and execution storage successful: hash=\(programHash), executionId=\(executionId)")
            return (programHash, executionId)
            
        } catch {
            // Rollback transaction on error
            try await connection.query("ROLLBACK", logger: self.logger)
            throw error
        }
    }
    
    /// Store a program in the database with execution metadata
    public func storeProgram(program: Program, fuzzerId: Int, metadata: ExecutionMetadata) async throws -> String {
        let programHash = DatabaseUtils.calculateProgramHash(program: program)
        let programBase64 = DatabaseUtils.encodeProgramToBase64(program: program)
        logger.debug("Storing program: hash=\(programHash), fuzzerId=\(fuzzerId), executionCount=\(metadata.executionCount)")
        
        // Use direct connection to avoid connection pool deadlock
        guard let eventLoopGroup = databasePool.getEventLoopGroup() else {
            throw PostgreSQLStorageError.noResult
        }
        
        let connection = try await PostgresConnection.connect(
            on: eventLoopGroup.next(),
            configuration: PostgresConnection.Configuration(
                host: "localhost",
                port: 5433,
                username: "fuzzilli",
                password: "fuzzilli123",
                database: "fuzzilli",
                tls: .disable
            ),
            id: 0,
            logger: logger
        )
        defer { Task { _ = try? await connection.close() } }
        
        // Insert into fuzzer table (corpus)
        let fuzzerQuery: PostgresQuery = """
            INSERT INTO fuzzer (program_base64, fuzzer_id, program_size, program_hash) 
            VALUES ('\(programBase64)', \(fuzzerId), \(program.size), '\(programHash)') 
            ON CONFLICT (program_base64) DO NOTHING
        """
        try await connection.query(fuzzerQuery, logger: self.logger)
        
        // Generate JavaScript code from the program
        let lifter = JavaScriptLifter(ecmaVersion: .es6)
        _ = lifter.lift(program, withOptions: [])
        
        // Insert into program table (executed programs)
        // Use DO UPDATE to ensure the program exists for foreign key constraints
        let programQuery: PostgresQuery = """
            INSERT INTO program (program_base64, fuzzer_id, program_size, program_hash) 
            VALUES ('\(programBase64)', \(fuzzerId), \(program.size), '\(programHash)') 
            ON CONFLICT (program_base64) DO UPDATE SET 
                fuzzer_id = EXCLUDED.fuzzer_id,
                program_size = EXCLUDED.program_size,
                program_hash = EXCLUDED.program_hash
        """
        try await connection.query(programQuery, logger: self.logger)
        
        self.logger.debug("Program storage successful: hash=\(programHash)")
        return programHash
    }
    
    /// Get program by hash
    public func getProgram(hash: String) async throws -> Program? {
        logger.debug("Getting program: hash=\(hash)")
        
        // For now, return nil (program not found)
        // TODO: Implement actual database query when PostgreSQL is set up
        logger.debug("Mock program lookup: program not found")
        return nil
    }
    
    /// Get program metadata for a specific fuzzer
    public func getProgramMetadata(programHash: String, fuzzerId: Int) async throws -> ExecutionMetadata? {
        logger.debug("Getting program metadata: hash=\(programHash), fuzzerId=\(fuzzerId)")
        
        // For now, return nil (metadata not found)
        // TODO: Implement actual database query when PostgreSQL is set up
        logger.debug("Mock metadata lookup: metadata not found")
        return nil
    }
    
    // MARK: - Execution Management
    
    /// Store multiple executions in batch for better performance
    public func storeExecutionsBatch(executions: [ExecutionBatchData], fuzzerId: Int) async throws -> [Int] {
        guard !executions.isEmpty else { return [] }
        
        // Use direct connection to avoid connection pool deadlock
        guard let eventLoopGroup = databasePool.getEventLoopGroup() else {
            throw PostgreSQLStorageError.noResult
        }
        
        let connection = try await PostgresConnection.connect(
            on: eventLoopGroup.next(),
            configuration: PostgresConnection.Configuration(
                host: "localhost",
                port: 5433,
                username: "fuzzilli",
                password: "fuzzilli123",
                database: "fuzzilli",
                tls: .disable
            ),
            id: 0,
            logger: logger
        )
        defer { Task { _ = try? await connection.close() } }
        
        var executionIds: [Int] = []
        var executionValues: [String] = []
        
        // Prepare batch data
        for executionData in executions {
            _ = DatabaseUtils.calculateProgramHash(program: executionData.program)
            let programBase64 = DatabaseUtils.encodeProgramToBase64(program: executionData.program)
            
            let executionTypeId = DatabaseUtils.mapExecutionType(purpose: executionData.executionType)
            
            // Extract execution metadata from ExecutionOutcome
            let (signalCode, exitCode) = extractExecutionMetadata(from: executionData.outcome)
            
            // Use signal-aware mapping for execution outcomes
            let outcomeId = DatabaseUtils.mapExecutionOutcomeWithSignal(outcome: executionData.outcome, signalCode: signalCode)
            
            // Store mutator name as text instead of ID
            let mutatorTypeValue = executionData.mutatorType != nil ? "'\(executionData.mutatorType!.replacingOccurrences(of: "'", with: "''"))'" : "NULL"
            let feedbackVectorValue = executionData.feedbackVector != nil ? "'\(executionData.feedbackVector!.base64EncodedString())'" : "NULL"
            let signalCodeValue = signalCode != nil ? "\(signalCode!)" : "NULL"
            let exitCodeValue = exitCode != nil ? "\(exitCode!)" : "NULL"
            let stdoutValue = executionData.stdout != nil ? "'\(executionData.stdout!.replacingOccurrences(of: "'", with: "''"))'" : "NULL"
            let stderrValue = executionData.stderr != nil ? "'\(executionData.stderr!.replacingOccurrences(of: "'", with: "''"))'" : "NULL"
            let fuzzoutValue = executionData.fuzzout != nil ? "'\(executionData.fuzzout!.replacingOccurrences(of: "'", with: "''"))'" : "NULL"
            
            executionValues.append("""
                ('\(programBase64.replacingOccurrences(of: "'", with: "''"))', \(executionTypeId), 
                \(mutatorTypeValue), \(outcomeId), \(executionData.coverage), 
                \(executionData.executionTimeMs), \(signalCodeValue), \(exitCodeValue), 
                \(stdoutValue), \(stderrValue), \(fuzzoutValue), 
                \(feedbackVectorValue), NOW())
            """)
        }
        
        // Batch insert executions
        if !executionValues.isEmpty {
            let queryString = """
                INSERT INTO execution (
                    program_base64, execution_type_id, mutator_type_id, 
                    execution_outcome_id, coverage_total, execution_time_ms, 
                    signal_code, exit_code, stdout, stderr, fuzzout, 
                    feedback_vector, created_at
                ) VALUES \(executionValues.joined(separator: ", ")) RETURNING execution_id
            """
            
            let query = PostgresQuery(stringLiteral: queryString)
            let result = try await connection.query(query, logger: self.logger)
            let rows = try await result.collect()
            
            for row in rows {
                let executionId = try row.decode(Int.self, context: .default)
                executionIds.append(executionId)
            }
        }
        
        return executionIds
    }
    
    /// Store execution record in the database
    public func storeExecution(
        program: Program,
        fuzzerId: Int,
        executionType: DatabaseExecutionPurpose,
        mutatorType: String? = nil,
        outcome: ExecutionOutcome,
        coverage: Double = 0.0,
        executionTimeMs: Int = 0,
        feedbackVector: Data? = nil,
        coverageEdges: Set<Int> = [],
        stdout: String? = nil,
        stderr: String? = nil,
        fuzzout: String? = nil
    ) async throws -> Int {
        let programHash = DatabaseUtils.calculateProgramHash(program: program)
        let programBase64 = DatabaseUtils.encodeProgramToBase64(program: program)
        logger.debug("Storing execution: hash=\(programHash), fuzzerId=\(fuzzerId), type=\(executionType), outcome=\(outcome)")
        
        // Use direct connection to avoid connection pool deadlock
        guard let eventLoopGroup = databasePool.getEventLoopGroup() else {
            throw PostgreSQLStorageError.noResult
        }
        
        let connection = try await PostgresConnection.connect(
            on: eventLoopGroup.next(),
            configuration: PostgresConnection.Configuration(
                host: "localhost",
                port: 5433,
                username: "fuzzilli",
                password: "fuzzilli123",
                database: "fuzzilli",
                tls: .disable
            ),
            id: 0,
            logger: logger
        )
        defer { Task { _ = try? await connection.close() } }
        
        let executionTypeId = DatabaseUtils.mapExecutionType(purpose: executionType)
        
        // Extract execution metadata from ExecutionOutcome
        let (signalCode, exitCode) = extractExecutionMetadata(from: outcome)
        
        // Use signal-aware mapping for execution outcomes
        let outcomeId = DatabaseUtils.mapExecutionOutcomeWithSignal(outcome: outcome, signalCode: signalCode)
        
        // Prepare parameters for NULL handling - store mutator name as text instead of ID
        let mutatorTypeValue = mutatorType != nil ? "'\(mutatorType!.replacingOccurrences(of: "'", with: "''"))'" : "NULL"
        let feedbackVectorValue = feedbackVector != nil ? "'\(feedbackVector!.base64EncodedString())'" : "NULL"
        let signalCodeValue = signalCode != nil ? "\(signalCode!)" : "NULL"
        let exitCodeValue = exitCode != nil ? "\(exitCode!)" : "NULL"
        let stdoutValue = stdout != nil ? "'\(stdout!.replacingOccurrences(of: "'", with: "''"))'" : "NULL"
        let stderrValue = stderr != nil ? "'\(stderr!.replacingOccurrences(of: "'", with: "''"))'" : "NULL"
        let fuzzoutValue = fuzzout != nil ? "'\(fuzzout!.replacingOccurrences(of: "'", with: "''"))'" : "NULL"
        
        let query = PostgresQuery(stringLiteral: """
            INSERT INTO execution (
                program_base64, execution_type_id, mutator_type_id, 
                execution_outcome_id, coverage_total, execution_time_ms, 
                signal_code, exit_code, stdout, stderr, fuzzout, 
                feedback_vector, created_at
            ) VALUES (
                '\(programBase64)', \(executionTypeId), 
                \(mutatorTypeValue), \(outcomeId), \(coverage), 
                \(executionTimeMs), \(signalCodeValue), \(exitCodeValue), 
                \(stdoutValue), \(stderrValue), \(fuzzoutValue), 
                \(feedbackVectorValue), NOW()
            ) RETURNING execution_id
        """)
        
        let result = try await connection.query(query, logger: self.logger)
        let rows = try await result.collect()
        guard let row = rows.first else {
            throw PostgreSQLStorageError.noResult
        }
        
        let executionId = try row.decode(Int.self, context: PostgresDecodingContext.default)
        self.logger.debug("Execution storage successful: executionId=\(executionId)")
        return executionId
    }
    
    /// Store execution record from Execution object
    public func storeExecution(
        program: Program,
        fuzzerId: Int,
        execution: Execution,
        executionType: DatabaseExecutionPurpose,
        mutatorType: String? = nil,
        coverage: Double = 0.0,
        feedbackVector: Data? = nil,
        coverageEdges: Set<Int> = []
    ) async throws -> Int {
        let executionTimeMs = Int(execution.execTime * 1000) // Convert to milliseconds
        return try await storeExecution(
            program: program,
            fuzzerId: fuzzerId,
            executionType: executionType,
            mutatorType: mutatorType,
            outcome: execution.outcome,
            coverage: coverage,
            executionTimeMs: executionTimeMs,
            feedbackVector: feedbackVector,
            coverageEdges: coverageEdges,
            stdout: execution.stdout,
            stderr: execution.stderr,
            fuzzout: execution.fuzzout
        )
    }
    
    /// Extract execution metadata from ExecutionOutcome
    private func extractExecutionMetadata(from outcome: ExecutionOutcome) -> (signalCode: Int?, exitCode: Int?) {
        switch outcome {
        case .crashed(let signal):
            return (signalCode: signal, exitCode: nil)
        case .failed(let exitCode):
            return (signalCode: nil, exitCode: exitCode)
        case .succeeded, .timedOut:
            return (signalCode: nil, exitCode: nil)
        }
    }
    
    /// Get execution history for a program
    public func getExecutionHistory(programHash: String, fuzzerId: Int, limit: Int = 100) async throws -> [ExecutionRecord] {
        logger.debug("Getting execution history: hash=\(programHash), fuzzerId=\(fuzzerId), limit=\(limit)")
        
        // For now, return empty array
        // TODO: Implement actual database query when PostgreSQL is set up
        logger.debug("Mock execution history lookup: no executions found")
        return []
    }
    
    // MARK: - Crash Management
    
    /// Store crash information
    public func storeCrash(
        program: Program,
        fuzzerId: Int,
        executionId: Int,
        crashType: String,
        signalCode: Int? = nil,
        exitCode: Int? = nil,
        stdout: String? = nil,
        stderr: String? = nil
    ) async throws -> Int {
        let programHash = DatabaseUtils.calculateProgramHash(program: program)
        logger.debug("Storing crash: hash=\(programHash), fuzzerId=\(fuzzerId), executionId=\(executionId), type=\(crashType)")
        
        // For now, return a mock crash ID
        // TODO: Implement actual database storage when PostgreSQL is set up
        let mockCrashId = Int.random(in: 1...1000)
        logger.debug("Mock crash storage successful: crashId=\(mockCrashId)")
        return mockCrashId
    }
    
    // MARK: - Query Operations
    
    /// Get recent programs with metadata for a fuzzer
    public func getRecentPrograms(fuzzerId: Int, since: Date, limit: Int = 100) async throws -> [(Program, ExecutionMetadata)] {
        logger.debug("Getting recent programs: fuzzerId=\(fuzzerId), since=\(since), limit=\(limit)")
        
        guard let eventLoopGroup = databasePool.getEventLoopGroup() else {
            throw PostgreSQLStorageError.noResult
        }
        
        let connection = try await PostgresConnection.connect(
            on: eventLoopGroup.next(),
            configuration: PostgresConnection.Configuration(
                host: "localhost",
                port: 5433,
                username: "fuzzilli",
                password: "fuzzilli123",
                database: "fuzzilli",
                tls: .disable
            ),
            id: 0,
            logger: logger
        )
        defer { Task { _ = try? await connection.close() } }
        
        // Query for recent programs with their latest execution metadata
        let queryString = """
            SELECT 
                p.program_base64,
                p.program_size,
                p.program_hash,
                p.created_at,
                eo.outcome,
                eo.description,
                e.execution_time_ms,
                e.coverage_total,
                e.signal_code,
                e.exit_code
            FROM program p
            LEFT JOIN execution e ON p.program_base64 = e.program_base64
            LEFT JOIN execution_outcome eo ON e.execution_outcome_id = eo.id
            WHERE p.fuzzer_id = \(fuzzerId)
            AND p.created_at >= '\(since.ISO8601Format())'
            ORDER BY p.created_at DESC
            LIMIT \(limit)
        """
        
        let query = PostgresQuery(stringLiteral: queryString)
        let result = try await connection.query(query, logger: self.logger)
        let rows = try await result.collect()
        
        var programs: [(Program, ExecutionMetadata)] = []
        
        for row in rows {
            let programBase64 = try row.decode(String.self, context: .default)
            _ = try row.decode(Int.self, context: .default) // programSize
            let programHash = try row.decode(String.self, context: .default)
            _ = try row.decode(Date.self, context: .default) // createdAt
            let outcome = try row.decode(String?.self, context: .default)
            let description = try row.decode(String?.self, context: .default)
            _ = try row.decode(Int?.self, context: .default) // executionTimeMs
            let coverageTotal = try row.decode(Double?.self, context: .default)
            _ = try row.decode(Int?.self, context: .default) // signalCode
            _ = try row.decode(Int?.self, context: .default) // exitCode
            
            // Decode the program from base64
            guard let programData = Data(base64Encoded: programBase64) else {
                logger.warning("Failed to decode base64 data for program: \(programHash)")
                continue
            }
            
            let program: Program
            do {
                let protobuf = try Fuzzilli_Protobuf_Program(serializedBytes: programData)
                program = try Program(from: protobuf)
            } catch {
                logger.warning("Failed to decode program from protobuf: \(programHash), error: \(error)")
                continue
            }
            
            // Create execution metadata
            
            // Map outcome string to database ID
            let outcomeId: Int
            switch (outcome ?? "Succeeded").lowercased() {
            case "crashed":
                outcomeId = 1
            case "failed":
                outcomeId = 2
            case "succeeded":
                outcomeId = 3
            case "timedout":
                outcomeId = 4
            case "sigcheck":
                outcomeId = 34
            default:
                outcomeId = 3 // Default to succeeded
            }
            
            let dbOutcome = DatabaseExecutionOutcome(
                id: outcomeId,
                outcome: outcome ?? "Succeeded",
                description: description ?? "Program executed successfully"
            )
            
            var metadata = ExecutionMetadata(lastOutcome: dbOutcome)
            if let coverage = coverageTotal {
                metadata.lastCoverage = coverage
            }
            
            programs.append((program, metadata))
        }
        
        logger.debug("Loaded \(programs.count) recent programs from database")
        return programs
    }
    
    /// Update program metadata
    public func updateProgramMetadata(programHash: String, fuzzerId: Int, metadata: ExecutionMetadata) async throws {
        logger.debug("Updating program metadata: hash=\(programHash), fuzzerId=\(fuzzerId), executionCount=\(metadata.executionCount)")
        
        // For now, just log the operation
        // TODO: Implement actual database update when PostgreSQL is set up
        logger.debug("Mock metadata update successful")
    }
    
    // MARK: - Statistics
    
    /// Get storage statistics
    public func getStorageStatistics() async throws -> StorageStatistics {
        logger.debug("Getting storage statistics")
        
        // For now, return mock statistics
        // TODO: Implement actual database statistics when PostgreSQL is set up
        let mockStats = StorageStatistics(
            totalPrograms: 0,
            totalExecutions: 0,
            totalCrashes: 0,
            activeFuzzers: 0
        )
        logger.debug("Mock statistics: \(mockStats.description)")
        return mockStats
    }
}

// MARK: - Supporting Types

/// Batch data for execution storage
public struct ExecutionBatchData {
    public let program: Program
    public let executionType: DatabaseExecutionPurpose
    public let mutatorType: String?
    public let outcome: ExecutionOutcome
    public let coverage: Double
    public let executionTimeMs: Int
    public let feedbackVector: Data?
    public let coverageEdges: Set<Int>
    public let stdout: String?
    public let stderr: String?
    public let fuzzout: String?
    
    public init(
        program: Program,
        executionType: DatabaseExecutionPurpose,
        mutatorType: String? = nil,
        outcome: ExecutionOutcome,
        coverage: Double = 0.0,
        executionTimeMs: Int = 0,
        feedbackVector: Data? = nil,
        coverageEdges: Set<Int> = [],
        stdout: String? = nil,
        stderr: String? = nil,
        fuzzout: String? = nil
    ) {
        self.program = program
        self.executionType = executionType
        self.mutatorType = mutatorType
        self.outcome = outcome
        self.coverage = coverage
        self.executionTimeMs = executionTimeMs
        self.feedbackVector = feedbackVector
        self.coverageEdges = coverageEdges
        self.stdout = stdout
        self.stderr = stderr
        self.fuzzout = fuzzout
    }
}

/// Storage statistics
public struct StorageStatistics {
    public let totalPrograms: Int
    public let totalExecutions: Int
    public let totalCrashes: Int
    public let activeFuzzers: Int
    
    public var description: String {
        return "Programs: \(totalPrograms), Executions: \(totalExecutions), Crashes: \(totalCrashes), Active Fuzzers: \(activeFuzzers)"
    }
}

/// PostgreSQL storage errors
public enum PostgreSQLStorageError: Error, LocalizedError {
    case noResult
    case invalidData
    case connectionFailed
    case queryFailed(String)
    
    public var errorDescription: String? {
        switch self {
        case .noResult:
            return "No result returned from database query"
        case .invalidData:
            return "Invalid data returned from database"
        case .connectionFailed:
            return "Failed to connect to database"
        case .queryFailed(let message):
            return "Database query failed: \(message)"
        }
    }
}