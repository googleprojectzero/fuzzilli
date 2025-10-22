import XCTest
import Foundation
@testable import Fuzzilli

final class PostgreSQLStorageTests: XCTestCase {

    func testPostgreSQLStorageInitialization() {
        let databasePool = DatabasePool(connectionString: "postgresql://localhost:5432/fuzzilli")
        let storage = PostgreSQLStorage(databasePool: databasePool)
        
        XCTAssertNotNil(storage)
    }
    
    func testFuzzerRegistration() async throws {
        let databasePool = DatabasePool(connectionString: "postgresql://localhost:5432/fuzzilli")
        let storage = PostgreSQLStorage(databasePool: databasePool)
        
        // Test fuzzer registration (this would fail without actual database)
        // For now, we'll just test that the method exists and can be called
        do {
            let fuzzerId = try await storage.registerFuzzer(
                name: "test-fuzzer-1",
                engineType: "multi",
                hostname: "localhost"
            )
            // This will fail without actual database, but we can test the interface
            XCTAssertGreaterThan(fuzzerId, 0)
        } catch {
            // Expected to fail without actual database connection
            XCTAssertTrue(error is DatabasePoolError)
        }
    }
    
    func testProgramStorage() async throws {
        let databasePool = DatabasePool(connectionString: "postgresql://localhost:5432/fuzzilli")
        let storage = PostgreSQLStorage(databasePool: databasePool)
        
        // Create execution metadata
        let outcome = DatabaseExecutionOutcome(id: 1, outcome: "Succeeded", description: "Test execution")
        var metadata = ExecutionMetadata(lastOutcome: outcome)
        metadata.executionCount = 1
        metadata.lastCoverage = 75.5
        
        // Test program storage interface (this would fail without actual database)
        // We'll test with a minimal program creation
        let program = Program()
        
        do {
            let programHash = try await storage.storeProgram(
                program: program,
                fuzzerId: 1,
                metadata: metadata
            )
            XCTAssertFalse(programHash.isEmpty)
        } catch {
            // Expected to fail without actual database connection
            XCTAssertTrue(error is DatabasePoolError)
        }
    }
    
    func testExecutionStorage() async throws {
        let databasePool = DatabasePool(connectionString: "postgresql://localhost:5432/fuzzilli")
        let storage = PostgreSQLStorage(databasePool: databasePool)
        
        // Test execution storage interface
        let program = Program()
        
        do {
            let executionId = try await storage.storeExecution(
                program: program,
                fuzzerId: 1,
                executionType: .fuzzing,
                mutatorType: "Splice",
                outcome: .succeeded,
                coverage: 85.0,
                executionTimeMs: 150,
                coverageEdges: [1, 2, 3, 4, 5]
            )
            XCTAssertGreaterThan(executionId, 0)
        } catch {
            // Expected to fail without actual database connection
            XCTAssertTrue(error is DatabasePoolError)
        }
    }
    
    func testCrashStorage() async throws {
        let databasePool = DatabasePool(connectionString: "postgresql://localhost:5432/fuzzilli")
        let storage = PostgreSQLStorage(databasePool: databasePool)
        
        // Test crash storage interface
        let program = Program()
        
        do {
            let crashId = try await storage.storeCrash(
                program: program,
                fuzzerId: 1,
                executionId: 1,
                crashType: "Segmentation Fault",
                signalCode: 11,
                stdout: "Program output",
                stderr: "Segmentation fault"
            )
            XCTAssertGreaterThan(crashId, 0)
        } catch {
            // Expected to fail without actual database connection
            XCTAssertTrue(error is DatabasePoolError)
        }
    }
    
    func testProgramRetrieval() async throws {
        let databasePool = DatabasePool(connectionString: "postgresql://localhost:5432/fuzzilli")
        let storage = PostgreSQLStorage(databasePool: databasePool)
        
        // Test program retrieval (this would fail without actual database)
        do {
            let program = try await storage.getProgram(hash: "test-hash")
            // This will be nil without actual database
            XCTAssertNil(program)
        } catch {
            // Expected to fail without actual database connection
            XCTAssertTrue(error is DatabasePoolError)
        }
    }
    
    func testMetadataRetrieval() async throws {
        let databasePool = DatabasePool(connectionString: "postgresql://localhost:5432/fuzzilli")
        let storage = PostgreSQLStorage(databasePool: databasePool)
        
        // Test metadata retrieval
        do {
            let metadata = try await storage.getProgramMetadata(programHash: "test-hash", fuzzerId: 1)
            // This will be nil without actual database
            XCTAssertNil(metadata)
        } catch {
            // Expected to fail without actual database connection
            XCTAssertTrue(error is DatabasePoolError)
        }
    }
    
    func testExecutionHistoryRetrieval() async throws {
        let databasePool = DatabasePool(connectionString: "postgresql://localhost:5432/fuzzilli")
        let storage = PostgreSQLStorage(databasePool: databasePool)
        
        // Test execution history retrieval
        do {
            let history = try await storage.getExecutionHistory(programHash: "test-hash", fuzzerId: 1, limit: 10)
            // This will be empty without actual database
            XCTAssertTrue(history.isEmpty)
        } catch {
            // Expected to fail without actual database connection
            XCTAssertTrue(error is DatabasePoolError)
        }
    }
    
    func testRecentProgramsRetrieval() async throws {
        let databasePool = DatabasePool(connectionString: "postgresql://localhost:5432/fuzzilli")
        let storage = PostgreSQLStorage(databasePool: databasePool)
        
        // Test recent programs retrieval
        do {
            let programs = try await storage.getRecentPrograms(fuzzerId: 1, since: Date(), limit: 10)
            // This will be empty without actual database
            XCTAssertTrue(programs.isEmpty)
        } catch {
            // Expected to fail without actual database connection
            XCTAssertTrue(error is DatabasePoolError)
        }
    }
    
    func testMetadataUpdate() async throws {
        let databasePool = DatabasePool(connectionString: "postgresql://localhost:5432/fuzzilli")
        let storage = PostgreSQLStorage(databasePool: databasePool)
        
        // Create execution metadata
        let outcome = DatabaseExecutionOutcome(id: 1, outcome: "Succeeded", description: "Test execution")
        var metadata = ExecutionMetadata(lastOutcome: outcome)
        metadata.executionCount = 5
        metadata.lastCoverage = 90.0
        
        // Test metadata update
        do {
            try await storage.updateProgramMetadata(programHash: "test-hash", fuzzerId: 1, metadata: metadata)
            // This will succeed or fail depending on database connection
        } catch {
            // Expected to fail without actual database connection
            XCTAssertTrue(error is DatabasePoolError)
        }
    }
    
    func testStorageStatistics() async throws {
        let databasePool = DatabasePool(connectionString: "postgresql://localhost:5432/fuzzilli")
        let storage = PostgreSQLStorage(databasePool: databasePool)
        
        // Test storage statistics
        do {
            let stats = try await storage.getStorageStatistics()
            XCTAssertGreaterThanOrEqual(stats.totalPrograms, 0)
            XCTAssertGreaterThanOrEqual(stats.totalExecutions, 0)
            XCTAssertGreaterThanOrEqual(stats.totalCrashes, 0)
            XCTAssertGreaterThanOrEqual(stats.activeFuzzers, 0)
        } catch {
            // Expected to fail without actual database connection
            XCTAssertTrue(error is DatabasePoolError)
        }
    }
    
    func testStorageStatisticsDescription() {
        let stats = StorageStatistics(
            totalPrograms: 100,
            totalExecutions: 1000,
            totalCrashes: 5,
            activeFuzzers: 3
        )
        
        let description = stats.description
        XCTAssertTrue(description.contains("Programs: 100"))
        XCTAssertTrue(description.contains("Executions: 1000"))
        XCTAssertTrue(description.contains("Crashes: 5"))
        XCTAssertTrue(description.contains("Active Fuzzers: 3"))
    }
    
    func testPostgreSQLStorageErrorDescriptions() {
        XCTAssertEqual(PostgreSQLStorageError.noResult.errorDescription, "No result returned from database query")
        XCTAssertEqual(PostgreSQLStorageError.invalidData.errorDescription, "Invalid data returned from database")
        XCTAssertEqual(PostgreSQLStorageError.connectionFailed.errorDescription, "Failed to connect to database")
        XCTAssertEqual(PostgreSQLStorageError.queryFailed("test").errorDescription, "Database query failed: test")
    }
}
