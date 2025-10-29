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
    private let enableLogging: Bool
    
    // MARK: - Initialization
    
    public init(databasePool: DatabasePool, enableLogging: Bool = false) {
        self.databasePool = databasePool
        self.enableLogging = enableLogging
        self.logger = Logging.Logger(label: "PostgreSQLStorage")
    }
    
    // MARK: - Fuzzer Management
    
    /// Register a new fuzzer instance in the database
    public func registerFuzzer(name: String, engineType: String, hostname: String? = nil) async throws -> Int {
        if enableLogging {
            logger.info("Registering fuzzer: name=\(name), engineType=\(engineType), hostname=\(hostname ?? "none")")
        }
        
        // Use direct connection to avoid connection pool deadlock
        guard let eventLoopGroup = databasePool.getEventLoopGroup() else {
            throw PostgreSQLStorageError.noResult
        }
        
        let connection = try await PostgresConnection.connect(
            on: eventLoopGroup.next(),
            configuration: PostgresConnection.Configuration(
                host: "localhost",
                port: 5432,
                username: "fuzzilli",
                password: "fuzzilli123",
                database: "fuzzilli_master",
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
            let existingFuzzerId = try existingRow.decode(Int.self, context: PostgresDecodingContext.default)
            let existingStatus = try existingRow.decode(String.self, context: PostgresDecodingContext.default)
            
            // Update status to active if it was inactive
            if existingStatus != "active" {
                let updateQuery: PostgresQuery = "UPDATE main SET status = 'active' WHERE fuzzer_id = \(existingFuzzerId)"
                try await connection.query(updateQuery, logger: self.logger)
                if enableLogging {
                    logger.info("Reactivated existing fuzzer: fuzzerId=\(existingFuzzerId)")
                }
            } else {
                if enableLogging {
                    logger.info("Reusing existing active fuzzer: fuzzerId=\(existingFuzzerId)")
                }
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
        
        let fuzzerId = try row.decode(Int.self, context: PostgresDecodingContext.default)
        if enableLogging {
            self.logger.info("Created new fuzzer: fuzzerId=\(fuzzerId)")
        }
        return fuzzerId
    }
    
    /// Get fuzzer instance by name
    public func getFuzzer(name: String) async throws -> FuzzerInstance? {
        if enableLogging {
            logger.info("Getting fuzzer: name=\(name)")
        }
        
        // Use direct connection to avoid connection pool deadlock
        guard let eventLoopGroup = databasePool.getEventLoopGroup() else {
            throw PostgreSQLStorageError.noResult
        }
        
        let connection = try await PostgresConnection.connect(
            on: eventLoopGroup.next(),
            configuration: PostgresConnection.Configuration(
                host: "localhost",
                port: 5432,
                username: "fuzzilli",
                password: "fuzzilli123",
                database: "fuzzilli_master",
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
        
        let fuzzerId = try row.decode(Int.self, context: PostgresDecodingContext.default)
        let createdAt = try row.decode(Date.self, context: PostgresDecodingContext.default)
        let fuzzerName = try row.decode(String.self, context: PostgresDecodingContext.default)
        let engineType = try row.decode(String.self, context: PostgresDecodingContext.default)
        let status = try row.decode(String.self, context: PostgresDecodingContext.default)
        
        let fuzzer = FuzzerInstance(
            fuzzerId: fuzzerId,
            createdAt: createdAt,
            fuzzerName: fuzzerName,
            engineType: engineType,
            status: status
        )
        
        if enableLogging {
            self.logger.info("Fuzzer found: \(fuzzerName) (ID: \(fuzzerId))")
        }
        return fuzzer
    }
    
    /// Get database statistics for a specific fuzzer
    public func getDatabaseStatistics(fuzzerId: Int) async throws -> DatabaseStatistics {
        if enableLogging {
            logger.info("Getting database statistics for fuzzer: \(fuzzerId)")
        }
        
        // Use direct connection to avoid connection pool deadlock
        guard let eventLoopGroup = databasePool.getEventLoopGroup() else {
            throw PostgreSQLStorageError.noResult
        }
        
        let connection = try await PostgresConnection.connect(
            on: eventLoopGroup.next(),
            configuration: PostgresConnection.Configuration(
                host: "localhost",
                port: 5432,
                username: "fuzzilli",
                password: "fuzzilli123",
                database: "fuzzilli_master",
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
        let totalPrograms = try programRows.first?.decode(Int.self, context: PostgresDecodingContext.default) ?? 0
        
        // Get execution count for this fuzzer
        let executionQuery: PostgresQuery = "SELECT COUNT(*) FROM execution e JOIN program p ON e.program_hash = p.program_hash WHERE p.fuzzer_id = \(fuzzerId)"
        let executionResult = try await connection.query(executionQuery, logger: self.logger)
        let executionRows = try await executionResult.collect()
        let totalExecutions = try executionRows.first?.decode(Int.self, context: PostgresDecodingContext.default) ?? 0
        
        // Get crash count for this fuzzer
        let crashQuery: PostgresQuery = """
            SELECT COUNT(*) FROM execution e 
            JOIN program p ON e.program_hash = p.program_hash 
            JOIN execution_outcome eo ON e.execution_outcome_id = eo.id 
            WHERE p.fuzzer_id = \(fuzzerId) AND eo.outcome = 'Crashed'
        """
        let crashResult = try await connection.query(crashQuery, logger: self.logger)
        let crashRows = try await crashResult.collect()
        let totalCrashes = try crashRows.first?.decode(Int.self, context: PostgresDecodingContext.default) ?? 0
        
        // Get active fuzzers count
        let activeQuery: PostgresQuery = "SELECT COUNT(*) FROM main WHERE status = 'active'"
        let activeResult = try await connection.query(activeQuery, logger: self.logger)
        let activeRows = try await activeResult.collect()
        let activeFuzzers = try activeRows.first?.decode(Int.self, context: PostgresDecodingContext.default) ?? 0
        
        let stats = DatabaseStatistics(
            totalPrograms: totalPrograms,
            totalExecutions: totalExecutions,
            totalCrashes: totalCrashes,
            activeFuzzers: activeFuzzers
        )
        
        if enableLogging {
            self.logger.info("Database statistics: Programs: \(stats.totalPrograms), Executions: \(stats.totalExecutions), Crashes: \(stats.totalCrashes), Active Fuzzers: \(stats.activeFuzzers)")
        }
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
                port: 5432,
                username: "fuzzilli",
                password: "fuzzilli123",
                database: "fuzzilli_master",
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
            
            fuzzerValues.append("('\(programHash)', \(fuzzerId), \(program.size), '\(escapedProgramBase64)')")
            programValues.append("('\(programHash)', \(fuzzerId), \(program.size), '\(escapedProgramBase64)')")
        }
        
        // Batch insert into fuzzer table
        if !fuzzerValues.isEmpty {
            let fuzzerQueryString = "INSERT INTO fuzzer (program_hash, fuzzer_id, program_size, program_base64) VALUES " + 
                fuzzerValues.joined(separator: ", ") + " ON CONFLICT DO NOTHING"
            let fuzzerQuery = PostgresQuery(stringLiteral: fuzzerQueryString)
            try await connection.query(fuzzerQuery, logger: self.logger)
        }
        
        // Batch insert into program table - use two-step upsert for each program
        if !programValues.isEmpty {
            for programValue in programValues {
                // Extract program_hash from the value string for the UPDATE
                let components = programValue.dropFirst().dropLast().split(separator: ",")
                guard components.count >= 4 else { continue }
                let programHash = String(components[0].dropFirst().dropLast()) // Remove quotes
                let fuzzerId = String(components[1].trimmingCharacters(in: .whitespaces))
                let programSize = String(components[2].trimmingCharacters(in: .whitespaces))
                let programBase64 = String(components[3].dropFirst().dropLast()) // Remove quotes
                
                // Try UPDATE first
                let updateQuery = PostgresQuery(stringLiteral: """
                    UPDATE program SET 
                        fuzzer_id = \(fuzzerId),
                        program_size = \(programSize),
                        program_base64 = '\(programBase64)'
                    WHERE program_hash = '\(programHash)'
                """)
                let updateResult = try await connection.query(updateQuery, logger: self.logger)
                let updateRows = try await updateResult.collect()
                
                // If no rows were updated, insert the new program
                if updateRows.isEmpty {
                    let insertQuery = PostgresQuery(stringLiteral: """
                        INSERT INTO program (program_hash, fuzzer_id, program_size, program_base64) 
                        VALUES ('\(programHash)', \(fuzzerId), \(programSize), '\(programBase64)') 
                        ON CONFLICT DO NOTHING
                    """)
                    try await connection.query(insertQuery, logger: self.logger)
                }
            }
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
        if enableLogging {
            logger.info("Storing program and execution: hash=\(programHash), fuzzerId=\(fuzzerId), executionCount=\(metadata.executionCount)")
        }
        
        // Use direct connection to avoid connection pool deadlock
        guard let eventLoopGroup = databasePool.getEventLoopGroup() else {
            throw PostgreSQLStorageError.noResult
        }
        
        let connection = try await PostgresConnection.connect(
            on: eventLoopGroup.next(),
            configuration: PostgresConnection.Configuration(
                host: "localhost",
                port: 5432,
                username: "fuzzilli",
                password: "fuzzilli123",
                database: "fuzzilli_master",
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
                INSERT INTO fuzzer (program_hash, fuzzer_id, program_size, program_base64) 
                VALUES ('\(programHash)', \(fuzzerId), \(program.size), '\(programBase64)') 
                ON CONFLICT DO NOTHING
            """)
            try await connection.query(fuzzerQuery, logger: self.logger)
            
            // Insert into program table (executed programs) - use two-step upsert
            let updateQuery = PostgresQuery(stringLiteral: """
                UPDATE program SET 
                    fuzzer_id = \(fuzzerId),
                    program_size = \(program.size),
                    program_base64 = '\(programBase64)'
                WHERE program_hash = '\(programHash)'
            """)
            let updateResult = try await connection.query(updateQuery, logger: self.logger)
            let updateRows = try await updateResult.collect()
            
            // If no rows were updated, insert the new program
            if updateRows.isEmpty {
                let insertQuery = PostgresQuery(stringLiteral: """
                    INSERT INTO program (program_hash, fuzzer_id, program_size, program_base64) 
                    VALUES ('\(programHash)', \(fuzzerId), \(program.size), '\(programBase64)') 
                    ON CONFLICT DO NOTHING
                """)
                try await connection.query(insertQuery, logger: self.logger)
            }
            
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
                    program_hash, execution_type_id, mutator_type_id, 
                    execution_outcome_id, coverage_total, execution_time_ms, 
                    signal_code, exit_code, stdout, stderr, fuzzout, 
                    feedback_vector, created_at
                ) VALUES (
                    '\(programHash)', \(executionTypeId), 
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
            
            if enableLogging {
                self.logger.info("Program and execution storage successful: hash=\(programHash), executionId=\(executionId)")
            }
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
        if enableLogging {
            logger.info("Storing program: hash=\(programHash), fuzzerId=\(fuzzerId), executionCount=\(metadata.executionCount)")
        }
        
        // Use direct connection to avoid connection pool deadlock
        guard let eventLoopGroup = databasePool.getEventLoopGroup() else {
            throw PostgreSQLStorageError.noResult
        }
        
        let connection = try await PostgresConnection.connect(
            on: eventLoopGroup.next(),
            configuration: PostgresConnection.Configuration(
                host: "localhost",
                port: 5432,
                username: "fuzzilli",
                password: "fuzzilli123",
                database: "fuzzilli_master",
                tls: .disable
            ),
            id: 0,
            logger: logger
        )
        defer { Task { _ = try? await connection.close() } }
        
        // Insert into fuzzer table (corpus)
        let fuzzerQuery: PostgresQuery = """
            INSERT INTO fuzzer (program_hash, fuzzer_id, program_size, program_base64) 
            VALUES ('\(programHash)', \(fuzzerId), \(program.size), '\(programBase64)') 
            ON CONFLICT DO NOTHING
        """
        try await connection.query(fuzzerQuery, logger: self.logger)
        
        // Generate JavaScript code from the program
        let lifter = JavaScriptLifter(ecmaVersion: .es6)
        _ = lifter.lift(program, withOptions: [])
        
        // Insert into program table (executed programs) - use two-step upsert
        let updateQuery: PostgresQuery = """
            UPDATE program SET 
                fuzzer_id = \(fuzzerId),
                program_size = \(program.size),
                program_base64 = '\(programBase64)'
            WHERE program_hash = '\(programHash)'rm
        """
        let updateResult = try await connection.query(updateQuery, logger: self.logger)
        let updateRows = try await updateResult.collect()
        
        // If no rows were updated, insert the new program
        if updateRows.isEmpty {
            let insertQuery: PostgresQuery = """
                INSERT INTO program (program_hash, fuzzer_id, program_size, program_base64) 
                VALUES ('\(programHash)', \(fuzzerId), \(program.size), '\(programBase64)') 
                ON CONFLICT DO NOTHING
            """
            try await connection.query(insertQuery, logger: self.logger)
        }
        
        if enableLogging {
            self.logger.info("Program storage successful: hash=\(programHash)")
        }
        return programHash
    }
    
    /// Get program by hash
    public func getProgram(hash: String) async throws -> Program? {
        if enableLogging {
            logger.info("Getting program: hash=\(hash)")
        }
        
        // For now, return nil (program not found)
        // TODO: Implement actual database query when PostgreSQL is set up
        if enableLogging {
            logger.info("Mock program lookup: program not found")
        }
        return nil
    }
    
    /// Get program metadata for a specific fuzzer
    public func getProgramMetadata(programHash: String, fuzzerId: Int) async throws -> ExecutionMetadata? {
        if enableLogging {
            logger.info("Getting program metadata: hash=\(programHash), fuzzerId=\(fuzzerId)")
        }
        
        // For now, return nil (metadata not found)
        // TODO: Implement actual database query when PostgreSQL is set up
        if enableLogging {
            logger.info("Mock metadata lookup: metadata not found")
        }
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
                port: 5432,
                username: "fuzzilli",
                password: "fuzzilli123",
                database: "fuzzilli_master",
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
            let programHash = DatabaseUtils.calculateProgramHash(program: executionData.program)
            let _ = DatabaseUtils.encodeProgramToBase64(program: executionData.program)
            
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
                ('\(programHash)', \(executionTypeId), 
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
                    program_hash, execution_type_id, mutator_type_id, 
                    execution_outcome_id, coverage_total, execution_time_ms, 
                    signal_code, exit_code, stdout, stderr, fuzzout, 
                    feedback_vector, created_at
                ) VALUES \(executionValues.joined(separator: ", ")) RETURNING execution_id
            """
            
            let query = PostgresQuery(stringLiteral: queryString)
            let result = try await connection.query(query, logger: self.logger)
            let rows = try await result.collect()
            
            for row in rows {
                let executionId = try row.decode(Int.self, context: PostgresDecodingContext.default)
                executionIds.append(executionId)
            }

            // Insert coverage detail rows for executions that have edge data
            var coverageValues: [String] = []
            for (idx, execId) in executionIds.enumerated() {
                let edges = executions[idx].coverageEdges
                if !edges.isEmpty {
                    for edge in edges {
                        coverageValues.append("(\(execId), \(edge), 1, TRUE)")
                    }
                }
            }
            if !coverageValues.isEmpty {
                let coverageInsert = "INSERT INTO coverage_detail (execution_id, edge_index, edge_hit_count, is_new_edge) VALUES " + coverageValues.joined(separator: ", ")
                try await connection.query(PostgresQuery(stringLiteral: coverageInsert), logger: self.logger)
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
        if enableLogging {
            logger.info("Storing execution: hash=\(programHash), fuzzerId=\(fuzzerId), type=\(executionType), outcome=\(outcome), programBase64=\(programBase64)")
        }
        
        // Use direct connection to avoid connection pool deadlock
        guard let eventLoopGroup = databasePool.getEventLoopGroup() else {
            throw PostgreSQLStorageError.noResult
        }
        
        let connection = try await PostgresConnection.connect(
            on: eventLoopGroup.next(),
            configuration: PostgresConnection.Configuration(
                host: "localhost",
                port: 5432,
                username: "fuzzilli",
                password: "fuzzilli123",
                database: "fuzzilli_master",
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
                program_hash, execution_type_id, mutator_type_id, 
                execution_outcome_id, coverage_total, execution_time_ms, 
                signal_code, exit_code, stdout, stderr, fuzzout, 
                feedback_vector, created_at
            ) VALUES (
                '\(programHash)', \(executionTypeId), 
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
        if enableLogging {
            self.logger.info("Execution storage successful: executionId=\(executionId)")
        }
        return executionId
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
        if enableLogging {
            logger.info("Getting execution history: hash=\(programHash), fuzzerId=\(fuzzerId), limit=\(limit)")
        }
        
        // For now, return empty array
        // TODO: Implement actual database query when PostgreSQL is set up
        if enableLogging {
            logger.info("Mock execution history lookup: no executions found")
        }
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
        if enableLogging {
            logger.info("Storing crash: hash=\(programHash), fuzzerId=\(fuzzerId), executionId=\(executionId), type=\(crashType)")
        }
        
        // For now, return a mock crash ID
        // TODO: Implement actual database storage when PostgreSQL is set up
        let mockCrashId = Int.random(in: 1...1000)
        if enableLogging {
            logger.info("Mock crash storage successful: crashId=\(mockCrashId)")
        }
        return mockCrashId
    }
    
    // MARK: - Query Operations
    
    /// Get recent programs with metadata for a fuzzer
    public func getRecentPrograms(fuzzerId: Int, since: Date, limit: Int = 100) async throws -> [(Program, ExecutionMetadata)] {
        if enableLogging {
            logger.info("Getting recent programs: fuzzerId=\(fuzzerId), since=\(since), limit=\(limit)")
        }
        
        guard let eventLoopGroup = databasePool.getEventLoopGroup() else {
            throw PostgreSQLStorageError.noResult
        }
        
        let connection = try await PostgresConnection.connect(
            on: eventLoopGroup.next(),
            configuration: PostgresConnection.Configuration(
                host: "localhost",
                port: 5432,
                username: "fuzzilli",
                password: "fuzzilli123",
                database: "fuzzilli_master",
                tls: .disable
            ),
            id: 0,
            logger: logger
        )
        defer { Task { _ = try? await connection.close() } }
        
        // Query for recent programs with their latest execution metadata
        let queryString = """
            SELECT 
                p.program_hash,
                p.program_size,
                p.program_base64,
                p.created_at,
                eo.outcome,
                eo.description,
                e.execution_time_ms,
                e.coverage_total,
                e.signal_code,
                e.exit_code
            FROM program p
            LEFT JOIN execution e ON p.program_hash = e.program_hash
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
            let programHash = try row.decode(String.self, context: PostgresDecodingContext.default)
            _ = try row.decode(Int.self, context: PostgresDecodingContext.default) // programSize
            let programBase64 = try row.decode(String.self, context: PostgresDecodingContext.default)
            _ = try row.decode(Date.self, context: PostgresDecodingContext.default) // createdAt
            let outcome = try row.decode(String?.self, context: PostgresDecodingContext.default)
            let description = try row.decode(String?.self, context: PostgresDecodingContext.default)
            _ = try row.decode(Int?.self, context: PostgresDecodingContext.default) // executionTimeMs
            let coverageTotal = try row.decode(Double?.self, context: PostgresDecodingContext.default)
            _ = try row.decode(Int?.self, context: PostgresDecodingContext.default) // signalCode
            _ = try row.decode(Int?.self, context: PostgresDecodingContext.default) // exitCode
            
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
        
        if enableLogging {
            logger.info("Loaded \(programs.count) recent programs from database")
        }
        return programs
    }
    
    /// Update program metadata
    public func updateProgramMetadata(programHash: String, fuzzerId: Int, metadata: ExecutionMetadata) async throws {
        if enableLogging {
            logger.info("Updating program metadata: hash=\(programHash), fuzzerId=\(fuzzerId), executionCount=\(metadata.executionCount)")
        }
        
        // For now, just log the operation
        // TODO: Implement actual database update when PostgreSQL is set up
        if enableLogging {
            logger.info("Mock metadata update successful")
        }
    }
    
    // MARK: - Statistics
    
    /// Get storage statistics
    public func getStorageStatistics() async throws -> StorageStatistics {
        if enableLogging {
            logger.info("Getting storage statistics")
        }
        
        // For now, return mock statistics
        // TODO: Implement actual database statistics when PostgreSQL is set up
        let mockStats = StorageStatistics(
            totalPrograms: 0,
            totalExecutions: 0,
            totalCrashes: 0,
            activeFuzzers: 0
        )
        if enableLogging {
            logger.info("Mock statistics: \(mockStats.description)")
        }
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

// MARK: - Coverage Tracking Methods

extension PostgreSQLStorage {
    /// Execute a simple query without expecting results
    public func executeQuery(_ query: PostgresQuery) async throws {
        guard let eventLoopGroup = databasePool.getEventLoopGroup() else {
            throw PostgreSQLStorageError.noResult
        }
        
        let connection = try await PostgresConnection.connect(
            on: eventLoopGroup.next(),
            configuration: PostgresConnection.Configuration(
                host: "localhost",
                port: 5432,
                username: "fuzzilli",
                password: "fuzzilli123",
                database: "fuzzilli_master",
                tls: .disable
            ),
            id: 0,
            logger: logger
        )
        defer { Task { _ = try? await connection.close() } }
        
        try await connection.query(query, logger: self.logger)
    }
}