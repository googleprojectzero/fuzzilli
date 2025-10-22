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
        logger.info("Registering fuzzer: name=\(name), engineType=\(engineType), hostname=\(hostname ?? "none")")
        
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
        
        let query: PostgresQuery = """
            INSERT INTO main (fuzzer_name, engine_type, status) 
            VALUES (\(name), \(engineType), 'active') 
            RETURNING fuzzer_id
        """
        
        let result = try await connection.query(query, logger: self.logger)
        let rows = try await result.collect()
        guard let row = rows.first else {
            throw PostgreSQLStorageError.noResult
        }
        
        let fuzzerId = try row.decode(Int.self, context: .default)
        self.logger.info("Fuzzer registration successful: fuzzerId=\(fuzzerId)")
        return fuzzerId
    }
    
    /// Get fuzzer instance by name
    public func getFuzzer(name: String) async throws -> FuzzerInstance? {
        logger.info("Getting fuzzer: name=\(name)")
        
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
        
        self.logger.info("Fuzzer found: \(fuzzerName) (ID: \(fuzzerId))")
        return fuzzer
    }
    
    // MARK: - Program Management
    
    /// Store a program in the database with execution metadata
    public func storeProgram(program: Program, fuzzerId: Int, metadata: ExecutionMetadata) async throws -> String {
        let programHash = DatabaseUtils.calculateProgramHash(program: program)
        let programBase64 = DatabaseUtils.encodeProgramToBase64(program: program)
        logger.info("Storing program: hash=\(programHash), fuzzerId=\(fuzzerId), executionCount=\(metadata.executionCount)")
        
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
            VALUES (\(programBase64), \(fuzzerId), \(program.size), \(programHash)) 
            ON CONFLICT (program_base64) DO NOTHING
        """
        try await connection.query(fuzzerQuery, logger: self.logger)
        
        // Insert into program table (executed programs)
        let programQuery: PostgresQuery = """
            INSERT INTO program (program_base64, fuzzer_id, program_size, program_hash) 
            VALUES (\(programBase64), \(fuzzerId), \(program.size), \(programHash)) 
            ON CONFLICT (program_base64) DO NOTHING
        """
        try await connection.query(programQuery, logger: self.logger)
        
        self.logger.info("Program storage successful: hash=\(programHash)")
        return programHash
    }
    
    /// Get program by hash
    public func getProgram(hash: String) async throws -> Program? {
        logger.info("Getting program: hash=\(hash)")
        
        // For now, return nil (program not found)
        // TODO: Implement actual database query when PostgreSQL is set up
        logger.info("Mock program lookup: program not found")
        return nil
    }
    
    /// Get program metadata for a specific fuzzer
    public func getProgramMetadata(programHash: String, fuzzerId: Int) async throws -> ExecutionMetadata? {
        logger.info("Getting program metadata: hash=\(programHash), fuzzerId=\(fuzzerId)")
        
        // For now, return nil (metadata not found)
        // TODO: Implement actual database query when PostgreSQL is set up
        logger.info("Mock metadata lookup: metadata not found")
        return nil
    }
    
    // MARK: - Execution Management
    
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
        coverageEdges: Set<Int> = []
    ) async throws -> Int {
        let programHash = DatabaseUtils.calculateProgramHash(program: program)
        let programBase64 = DatabaseUtils.encodeProgramToBase64(program: program)
        logger.info("Storing execution: hash=\(programHash), fuzzerId=\(fuzzerId), type=\(executionType), outcome=\(outcome)")
        
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
        let outcomeId = DatabaseUtils.mapExecutionOutcome(outcome: outcome)
        
        let query: PostgresQuery = """
            INSERT INTO execution (
                program_base64, execution_type_id, mutator_type_id, 
                execution_outcome_id, coverage_total, execution_time_ms, 
                feedback_vector, created_at
            ) VALUES (
                \(programBase64), \(executionTypeId), 
                \(mutatorType ?? "NULL"), \(outcomeId), \(coverage), 
                \(executionTimeMs), \(feedbackVector?.base64EncodedString() ?? "NULL"), 
                NOW()
            ) RETURNING execution_id
        """
        
        let result = try await connection.query(query, logger: self.logger)
        let rows = try await result.collect()
        guard let row = rows.first else {
            throw PostgreSQLStorageError.noResult
        }
        
        let executionId = try row.decode(Int.self, context: .default)
        self.logger.info("Execution storage successful: executionId=\(executionId)")
        return executionId
    }
    
    /// Get execution history for a program
    public func getExecutionHistory(programHash: String, fuzzerId: Int, limit: Int = 100) async throws -> [ExecutionRecord] {
        logger.info("Getting execution history: hash=\(programHash), fuzzerId=\(fuzzerId), limit=\(limit)")
        
        // For now, return empty array
        // TODO: Implement actual database query when PostgreSQL is set up
        logger.info("Mock execution history lookup: no executions found")
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
        logger.info("Storing crash: hash=\(programHash), fuzzerId=\(fuzzerId), executionId=\(executionId), type=\(crashType)")
        
        // For now, return a mock crash ID
        // TODO: Implement actual database storage when PostgreSQL is set up
        let mockCrashId = Int.random(in: 1...1000)
        logger.info("Mock crash storage successful: crashId=\(mockCrashId)")
        return mockCrashId
    }
    
    // MARK: - Query Operations
    
    /// Get recent programs with metadata for a fuzzer
    public func getRecentPrograms(fuzzerId: Int, since: Date, limit: Int = 100) async throws -> [(Program, ExecutionMetadata)] {
        logger.info("Getting recent programs: fuzzerId=\(fuzzerId), since=\(since), limit=\(limit)")
        
        // For now, return empty array
        // TODO: Implement actual database query when PostgreSQL is set up
        logger.info("Mock recent programs lookup: no programs found")
        return []
    }
    
    /// Update program metadata
    public func updateProgramMetadata(programHash: String, fuzzerId: Int, metadata: ExecutionMetadata) async throws {
        logger.info("Updating program metadata: hash=\(programHash), fuzzerId=\(fuzzerId), executionCount=\(metadata.executionCount)")
        
        // For now, just log the operation
        // TODO: Implement actual database update when PostgreSQL is set up
        logger.info("Mock metadata update successful")
    }
    
    // MARK: - Statistics
    
    /// Get storage statistics
    public func getStorageStatistics() async throws -> StorageStatistics {
        logger.info("Getting storage statistics")
        
        // For now, return mock statistics
        // TODO: Implement actual database statistics when PostgreSQL is set up
        let mockStats = StorageStatistics(
            totalPrograms: 0,
            totalExecutions: 0,
            totalCrashes: 0,
            activeFuzzers: 0
        )
        logger.info("Mock statistics: \(mockStats.description)")
        return mockStats
    }
}

// MARK: - Supporting Types

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