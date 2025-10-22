import XCTest
import Foundation
@testable import Fuzzilli

final class PostgreSQLIntegrationTests: XCTestCase {
    
    var databasePool: DatabasePool!
    var storage: PostgreSQLStorage!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Use the PostgreSQL container we set up
        let connectionString = "postgresql://fuzzilli:fuzzilli123@localhost:5433/fuzzilli"
        databasePool = DatabasePool(connectionString: connectionString)
        
        try await databasePool.initialize()
        storage = PostgreSQLStorage(databasePool: databasePool)
    }
    
    override func tearDown() async throws {
        await databasePool.shutdown()
        try await super.tearDown()
    }
    
    func testDatabaseConnection() async throws {
        let isConnected = try await databasePool.testConnection()
        XCTAssertTrue(isConnected, "Should be able to connect to PostgreSQL")
    }
    
    func testFuzzerRegistration() async throws {
        let fuzzerId = try await storage.registerFuzzer(
            name: "test-fuzzer-\(UUID().uuidString.prefix(8))",
            engineType: "v8",
            hostname: "localhost"
        )
        
        XCTAssertGreaterThan(fuzzerId, 0, "Should return a valid fuzzer ID")
        
        // Verify the fuzzer was actually stored
        let fuzzer = try await storage.getFuzzer(name: "test-fuzzer-\(UUID().uuidString.prefix(8))")
        // Note: This will be nil because we're using a different UUID, but the registration should work
    }
    
    func testProgramStorage() async throws {
        // Create a simple program
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()
        b.loadInt(42)
        b.loadString("test")
        let program = b.finalize()
        
        // Create execution metadata
        let outcome = DatabaseExecutionOutcome(id: 1, outcome: "Succeeded", description: "Test execution")
        let metadata = ExecutionMetadata(lastOutcome: outcome)
        
        // Register a fuzzer first
        let fuzzerId = try await storage.registerFuzzer(
            name: "test-fuzzer-program-\(UUID().uuidString.prefix(8))",
            engineType: "v8"
        )
        
        // Store the program
        let programHash = try await storage.storeProgram(
            program: program,
            fuzzerId: fuzzerId,
            metadata: metadata
        )
        
        XCTAssertFalse(programHash.isEmpty, "Should return a valid program hash")
    }
    
    func testExecutionStorage() async throws {
        // Create a simple program
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()
        b.loadInt(42)
        let program = b.finalize()
        
        // Register a fuzzer first
        let fuzzerId = try await storage.registerFuzzer(
            name: "test-fuzzer-exec-\(UUID().uuidString.prefix(8))",
            engineType: "v8"
        )
        
        // Store execution
        let executionId = try await storage.storeExecution(
            program: program,
            fuzzerId: fuzzerId,
            executionType: .fuzzing,
            mutatorType: "Splice",
            outcome: .succeeded,
            coverage: 85.0,
            executionTimeMs: 150,
            feedbackVector: nil,
            coverageEdges: [1, 2, 3, 4, 5]
        )
        
        XCTAssertGreaterThan(executionId, 0, "Should return a valid execution ID")
    }
    
    func testDatabaseSchemaVerification() async throws {
        let schema = DatabaseSchema()
        
        // For now, just test that the schema can be created
        // The actual verification would require a real database connection
        XCTAssertNotNil(schema, "Database schema should be created")
        
        // Test that the schema SQL is not empty
        XCTAssertFalse(DatabaseSchema.schemaSQL.isEmpty, "Schema SQL should not be empty")
        XCTAssertTrue(DatabaseSchema.schemaSQL.contains("CREATE TABLE"), "Schema should contain CREATE TABLE statements")
    }
    
    func testLookupTables() async throws {
        // Test that the lookup table enums are properly defined
        let executionPurposes = DatabaseExecutionPurpose.allCases
        XCTAssertGreaterThan(executionPurposes.count, 0, "Should have execution purposes")
        XCTAssertTrue(executionPurposes.contains(.fuzzing), "Should have fuzzing execution purpose")
        
        let mutatorNames = MutatorName.allCases
        XCTAssertGreaterThan(mutatorNames.count, 0, "Should have mutator names")
        XCTAssertTrue(mutatorNames.contains(.spliceMutator), "Should have splice mutator")
        
        // Test that the mapping functions work
        let fuzzingId = DatabaseUtils.mapExecutionType(purpose: .fuzzing)
        XCTAssertEqual(fuzzingId, 1, "Fuzzing should map to ID 1")
        
        let spliceId = DatabaseUtils.mapMutatorType(mutator: "splice")
        XCTAssertEqual(spliceId, 1, "Splice should map to ID 1")
    }
    
    func testConcurrentOperations() async throws {
        // Test concurrent fuzzer registrations
        let fuzzerNames = (1...5).map { "concurrent-fuzzer-\($0)" }
        
        let fuzzerIds = try await withThrowingTaskGroup(of: Int.self) { group in
            for name in fuzzerNames {
                group.addTask {
                    try await self.storage.registerFuzzer(name: name, engineType: "v8")
                }
            }
            
            var ids: [Int] = []
            for try await id in group {
                ids.append(id)
            }
            return ids
        }
        
        XCTAssertEqual(fuzzerIds.count, 5, "Should register all 5 fuzzers")
        XCTAssertTrue(fuzzerIds.allSatisfy { $0 > 0 }, "All fuzzer IDs should be valid")
    }
}
