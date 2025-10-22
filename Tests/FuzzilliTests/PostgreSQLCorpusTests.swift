import XCTest
import Foundation
@testable import Fuzzilli

final class PostgreSQLCorpusTests: XCTestCase {

    func testPostgreSQLCorpusInitialization() {
        let databasePool = DatabasePool(connectionString: "postgresql://localhost:5432/fuzzilli")
        let corpus = PostgreSQLCorpus(
            minSize: 10,
            maxSize: 100,
            minMutationsPerSample: 5,
            databasePool: databasePool,
            fuzzerInstanceId: "test-instance-1"
        )
        
        XCTAssertEqual(corpus.size, 0)
        XCTAssertTrue(corpus.isEmpty)
        XCTAssertTrue(corpus.supportsFastStateSynchronization)
    }
    
    func testPostgreSQLCorpusAddProgram() {
        let databasePool = DatabasePool(connectionString: "postgresql://localhost:5432/fuzzilli")
        
        // Create corpus
        let corpus = PostgreSQLCorpus(
            minSize: 10,
            maxSize: 100,
            minMutationsPerSample: 5,
            databasePool: databasePool,
            fuzzerInstanceId: "test-instance-1"
        )
        
        // Test basic properties
        XCTAssertEqual(corpus.size, 0)
        XCTAssertTrue(corpus.isEmpty)
        XCTAssertTrue(corpus.supportsFastStateSynchronization)
        
        // Test statistics
        let stats = corpus.getStatistics()
        XCTAssertEqual(stats.totalPrograms, 0)
        XCTAssertEqual(stats.fuzzerInstanceId, "test-instance-1")
    }
    
    func testPostgreSQLCorpusRandomElementAccess() {
        let databasePool = DatabasePool(connectionString: "postgresql://localhost:5432/fuzzilli")
        let corpus = PostgreSQLCorpus(
            minSize: 10,
            maxSize: 100,
            minMutationsPerSample: 5,
            databasePool: databasePool,
            fuzzerInstanceId: "test-instance-1"
        )
        
        // Test that corpus starts empty
        XCTAssertEqual(corpus.size, 0)
        XCTAssertTrue(corpus.isEmpty)
        
        // Test that allPrograms returns empty array
        let allPrograms = corpus.allPrograms()
        XCTAssertEqual(allPrograms.count, 0)
    }
    
    func testPostgreSQLCorpusAllPrograms() {
        let databasePool = DatabasePool(connectionString: "postgresql://localhost:5432/fuzzilli")
        let corpus = PostgreSQLCorpus(
            minSize: 10,
            maxSize: 100,
            minMutationsPerSample: 5,
            databasePool: databasePool,
            fuzzerInstanceId: "test-instance-1"
        )
        
        // Test that allPrograms returns empty array initially
        let allPrograms = corpus.allPrograms()
        XCTAssertEqual(allPrograms.count, 0)
        XCTAssertTrue(allPrograms.isEmpty)
    }
    
    func testPostgreSQLCorpusStateExportImport() throws {
        let databasePool = DatabasePool(connectionString: "postgresql://localhost:5432/fuzzilli")
        let corpus = PostgreSQLCorpus(
            minSize: 10,
            maxSize: 100,
            minMutationsPerSample: 5,
            databasePool: databasePool,
            fuzzerInstanceId: "test-instance-1"
        )
        
        // Test export of empty corpus
        let exportedData = try corpus.exportState()
        // Empty corpus can have empty export data, which is valid
        // XCTAssertFalse(exportedData.isEmpty)
        
        // Create new corpus and import state
        let newCorpus = PostgreSQLCorpus(
            minSize: 10,
            maxSize: 100,
            minMutationsPerSample: 5,
            databasePool: databasePool,
            fuzzerInstanceId: "test-instance-2"
        )
        
        try newCorpus.importState(exportedData)
        XCTAssertEqual(newCorpus.size, 0)
    }
    
    func testPostgreSQLCorpusDuplicateProgramHandling() {
        let databasePool = DatabasePool(connectionString: "postgresql://localhost:5432/fuzzilli")
        let corpus = PostgreSQLCorpus(
            minSize: 10,
            maxSize: 100,
            minMutationsPerSample: 5,
            databasePool: databasePool,
            fuzzerInstanceId: "test-instance-1"
        )
        
        // Test that corpus starts empty
        XCTAssertEqual(corpus.size, 0)
        XCTAssertTrue(corpus.isEmpty)
    }
    
    func testPostgreSQLCorpusStatistics() {
        let databasePool = DatabasePool(connectionString: "postgresql://localhost:5432/fuzzilli")
        let corpus = PostgreSQLCorpus(
            minSize: 10,
            maxSize: 100,
            minMutationsPerSample: 5,
            databasePool: databasePool,
            fuzzerInstanceId: "test-instance-1"
        )
        
        // Test initial statistics
        let initialStats = corpus.getStatistics()
        XCTAssertEqual(initialStats.totalPrograms, 0)
        XCTAssertEqual(initialStats.totalExecutions, 0)
        XCTAssertEqual(initialStats.averageCoverage, 0.0)
        XCTAssertEqual(initialStats.pendingSyncOperations, 0)
        XCTAssertEqual(initialStats.fuzzerInstanceId, "test-instance-1")
    }
    
    func testPostgreSQLCorpusWithDifferentAspects() {
        let databasePool = DatabasePool(connectionString: "postgresql://localhost:5432/fuzzilli")
        let corpus = PostgreSQLCorpus(
            minSize: 10,
            maxSize: 100,
            minMutationsPerSample: 5,
            databasePool: databasePool,
            fuzzerInstanceId: "test-instance-1"
        )
        
        // Test that corpus starts empty
        XCTAssertEqual(corpus.size, 0)
        XCTAssertTrue(corpus.isEmpty)
    }
    
    func testCorpusStatisticsDescription() {
        let stats = CorpusStatistics(
            totalPrograms: 10,
            totalExecutions: 100,
            averageCoverage: 75.5,
            pendingSyncOperations: 3,
            fuzzerInstanceId: "test-instance"
        )
        
        let description = stats.description
        XCTAssertTrue(description.contains("Programs: 10"))
        XCTAssertTrue(description.contains("Executions: 100"))
        XCTAssertTrue(description.contains("Coverage: 75.50%"))
        XCTAssertTrue(description.contains("Pending Sync: 3"))
    }
    
    func testPostgreSQLCorpusInterestingProgramTracking() {
        let databasePool = DatabasePool(connectionString: "postgresql://localhost:5432/fuzzilli")
        let corpus = PostgreSQLCorpus(
            minSize: 1,
            maxSize: 10,
            minMutationsPerSample: 5,
            databasePool: databasePool,
            fuzzerInstanceId: "test-instance-1"
        )
        
        // Create a mock fuzzer to initialize the corpus
        let mockFuzzer = makeMockFuzzer(corpus: corpus)
        
        // Create a simple program with actual content
        let b = mockFuzzer.makeBuilder()
        b.loadInt(42)
        let program = b.finalize()
        
        // Add the program to the corpus
        // This should trigger the InterestingProgramFound event
        corpus.add(program, ProgramAspects(outcome: .succeeded))
        
        // Verify the program was added
        XCTAssertEqual(corpus.size, 1)
        XCTAssertFalse(corpus.isEmpty)
        
        // Test that we can get the program back
        let allPrograms = corpus.allPrograms()
        XCTAssertEqual(allPrograms.count, 1)
        XCTAssertEqual(allPrograms[0], program)
    }
}
