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
    
    // MARK: - Helper Methods
    
    /// Create a direct connection using the database pool's configuration
    private func createDirectConnection() async throws -> PostgresConnection {
        guard let eventLoopGroup = databasePool.getEventLoopGroup() else {
            throw PostgreSQLStorageError.noResult
        }
        
        // Get the connection string and parse it
        let connectionString = databasePool.getConnectionString()
        guard let url = URL(string: connectionString) else {
            throw PostgreSQLStorageError.connectionFailed
        }
        
        guard url.scheme == "postgresql" || url.scheme == "postgres" else {
            throw PostgreSQLStorageError.connectionFailed
        }
        
        let host = url.host ?? "localhost"
        let port = url.port ?? 5432
        let username = url.user ?? "postgres"
        let password = url.password ?? ""
        let database = url.path.isEmpty ? nil : String(url.path.dropFirst()) // Remove leading slash
        
        if enableLogging {
            logger.info("Creating direct connection to: host=\(host), port=\(port), database=\(database ?? "none")")
        }
        
        return try await PostgresConnection.connect(
            on: eventLoopGroup.next(),
            configuration: PostgresConnection.Configuration(
                host: host,
                port: port,
                username: username,
                password: password,
                database: database,
                tls: .disable // For now, disable TLS
            ),
            id: 0,
            logger: logger
        )
    }
    
    // MARK: - Fuzzer Management
    
    /// Register a new fuzzer instance in the database
    public func registerFuzzer(name: String, engineType: String, hostname: String? = nil) async throws -> Int {
        if enableLogging {
            logger.info("Registering fuzzer: name=\(name), engineType=\(engineType), hostname=\(hostname ?? "none")")
        }
        
        // Use direct connection to avoid connection pool deadlock
        let connection: PostgresConnection
        do {
            connection = try await createDirectConnection()
            if enableLogging {
                let connString = databasePool.getConnectionString()
                logger.info("Created direct connection to: \(connString)")
            }
        } catch {
            if enableLogging {
                logger.error("Failed to create direct connection: \(error)")
            }
            throw error
        }
        defer { Task { _ = try? await connection.close() } }
        
        // First, check if a fuzzer with this name already exists
        // Escape single quotes in name
        let escapedName = name.replacingOccurrences(of: "'", with: "''")
        let checkQuery = PostgresQuery(stringLiteral: "SELECT fuzzer_id, status FROM main WHERE fuzzer_name = '\(escapedName)'")
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
        // Escape single quotes in engine type (name already escaped above)
        let escapedEngineType = engineType.replacingOccurrences(of: "'", with: "''")
        let insertQuery = PostgresQuery(stringLiteral: """
            INSERT INTO main (fuzzer_name, engine_type, status) 
            VALUES ('\(escapedName)', '\(escapedEngineType)', 'active') 
            RETURNING fuzzer_id
        """)
        
        if enableLogging {
            logger.info("Executing INSERT query to create new fuzzer")
        }
        
        let result: PostgresRowSequence
        do {
            if enableLogging {
                logger.info("Executing INSERT query: INSERT INTO main (fuzzer_name, engine_type, status) VALUES ('\(escapedName)', '\(escapedEngineType)', 'active') RETURNING fuzzer_id")
            }
            result = try await connection.query(insertQuery, logger: self.logger)
        } catch {
            if enableLogging {
                logger.error("INSERT query failed with error: \(error)")
            }
            throw error
        }
        
        let rows: [PostgresRow]
        do {
            rows = try await result.collect()
            if enableLogging {
                logger.info("INSERT query returned \(rows.count) rows")
            }
        } catch {
            if enableLogging {
                logger.error("Failed to collect rows from INSERT query: \(error)")
            }
            throw error
        }
        
        guard let row = rows.first else {
            if enableLogging {
                logger.error("INSERT query returned no rows - registration failed. This might indicate a connection issue or the query didn't execute properly.")
            }
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
        let connection = try await createDirectConnection()
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
        let connection = try await createDirectConnection()
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
        let connection = try await createDirectConnection()
        defer { Task { _ = try? await connection.close() } }
        
        var programHashes: [String] = []
        var fuzzerBatchData: [(String, Int, Int, String)] = []
        
        // Prepare batch data - store tuples instead of strings to avoid SQL injection
        for (program, _) in programs {
            let programHash = DatabaseUtils.calculateProgramHash(program: program)
            let programBase64 = DatabaseUtils.encodeProgramToBase64(program: program)
            programHashes.append(programHash)
            fuzzerBatchData.append((programHash, fuzzerId, program.size, programBase64))
        }
        
        // Batch insert into fuzzer table (corpus) using parameterized queries
        if !fuzzerBatchData.isEmpty {
            // Use a transaction for better performance
            try await connection.query("BEGIN", logger: self.logger)
            
            do {
                // Batch insert into fuzzer table
                for (programHash, fuzzerId, programSize, programBase64) in fuzzerBatchData {
                    // Escape single quotes in base64 string
                    let escapedProgramBase64 = programBase64.replacingOccurrences(of: "'", with: "''")
                    
                    let fuzzerQuery = PostgresQuery(stringLiteral: """
                        INSERT INTO fuzzer (program_hash, fuzzer_id, program_size, program_base64) 
                        VALUES ('\(programHash)', \(fuzzerId), \(programSize), '\(escapedProgramBase64)') 
                        ON CONFLICT (program_hash) DO UPDATE SET
                            fuzzer_id = EXCLUDED.fuzzer_id,
                            program_size = EXCLUDED.program_size,
                            program_base64 = EXCLUDED.program_base64
                    """)
                    try await connection.query(fuzzerQuery, logger: self.logger)
                }
                
                // Batch insert/update into program table
                for (programHash, fuzzerId, programSize, programBase64) in fuzzerBatchData {
                    // Escape single quotes in base64 string
                    let escapedProgramBase64 = programBase64.replacingOccurrences(of: "'", with: "''")
                    
                    // Use INSERT ... ON CONFLICT for atomic upsert
                    let programQuery = PostgresQuery(stringLiteral: """
                        INSERT INTO program (program_hash, fuzzer_id, program_size, program_base64) 
                        VALUES ('\(programHash)', \(fuzzerId), \(programSize), '\(escapedProgramBase64)') 
                        ON CONFLICT (program_hash) DO UPDATE SET
                            fuzzer_id = EXCLUDED.fuzzer_id,
                            program_size = EXCLUDED.program_size,
                            program_base64 = EXCLUDED.program_base64
                    """)
                    try await connection.query(programQuery, logger: self.logger)
                }
                
                // Commit transaction
                try await connection.query("COMMIT", logger: self.logger)
                
                if enableLogging {
                    logger.info("Successfully batch stored \(programHashes.count) programs in database")
                }
            } catch {
                // Rollback on error
                try? await connection.query("ROLLBACK", logger: self.logger)
                throw error
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
        let connection = try await createDirectConnection()
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
        let connection = try await createDirectConnection()
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
            WHERE program_hash = '\(programHash)'
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
    
    // MARK: - Execution Management
    
    /// Store multiple executions in batch for better performance
    public func storeExecutionsBatch(executions: [ExecutionBatchData], fuzzerId: Int) async throws -> [Int] {
        guard !executions.isEmpty else { return [] }
        
        // Use direct connection to avoid connection pool deadlock
        let connection = try await createDirectConnection()
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
        let connection = try await createDirectConnection()
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
    
    // MARK: - Query Operations
    
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
        // Use direct connection to avoid connection pool deadlock
        let connection = try await createDirectConnection()
        defer { Task { _ = try? await connection.close() } }
        
        try await connection.query(query, logger: self.logger)
    }
}