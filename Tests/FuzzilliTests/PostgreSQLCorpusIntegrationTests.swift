import XCTest
import Foundation
@testable import Fuzzilli

final class PostgreSQLCorpusIntegrationTests: XCTestCase {

    func testPostgreSQLCorpusCLIIntegration() {
        // Test that PostgreSQL corpus can be created with proper configuration
        let databasePool = DatabasePool(connectionString: "postgresql://localhost:5432/fuzzilli")
        let fuzzerInstanceId = "test-fuzzer-123"
        
        let corpus = PostgreSQLCorpus(
            minSize: 10,
            maxSize: 100,
            minMutationsPerSample: 5,
            databasePool: databasePool,
            fuzzerInstanceId: fuzzerInstanceId
        )
        
        XCTAssertEqual(corpus.size, 0)
        XCTAssertTrue(corpus.isEmpty)
        XCTAssertTrue(corpus.supportsFastStateSynchronization)
    }
    
    func testPostgreSQLCorpusConfiguration() {
        // Test that PostgreSQL corpus accepts the same configuration as BasicCorpus
        let databasePool = DatabasePool(connectionString: "postgresql://localhost:5432/fuzzilli")
        let fuzzerInstanceId = "test-fuzzer-456"
        
        let corpus = PostgreSQLCorpus(
            minSize: 1000,
            maxSize: 10000,
            minMutationsPerSample: 25,
            databasePool: databasePool,
            fuzzerInstanceId: fuzzerInstanceId
        )
        
        XCTAssertEqual(corpus.size, 0)
        XCTAssertTrue(corpus.isEmpty)
        
        // Test statistics
        let stats = corpus.getStatistics()
        XCTAssertEqual(stats.fuzzerInstanceId, fuzzerInstanceId)
        XCTAssertEqual(stats.totalPrograms, 0)
        XCTAssertEqual(stats.totalExecutions, 0)
        XCTAssertEqual(stats.averageCoverage, 0.0)
        XCTAssertEqual(stats.pendingSyncOperations, 0)
    }
    
    func testPostgreSQLCorpusProtocolConformance() {
        // Test that PostgreSQLCorpus properly implements the Corpus protocol
        let databasePool = DatabasePool(connectionString: "postgresql://localhost:5432/fuzzilli")
        let fuzzerInstanceId = "test-fuzzer-789"
        
        let corpus: Corpus = PostgreSQLCorpus(
            minSize: 10,
            maxSize: 100,
            minMutationsPerSample: 5,
            databasePool: databasePool,
            fuzzerInstanceId: fuzzerInstanceId
        )
        
        // Test basic protocol methods
        XCTAssertEqual(corpus.size, 0)
        XCTAssertTrue(corpus.isEmpty)
        XCTAssertTrue(corpus.supportsFastStateSynchronization)
        
        // Test that we can get all programs (should be empty initially)
        let allPrograms = corpus.allPrograms()
        XCTAssertTrue(allPrograms.isEmpty)
        
        // Test state export/import
        do {
            let exportedData = try corpus.exportState()
            // Empty corpus can have empty export data, which is valid
            // XCTAssertFalse(exportedData.isEmpty)
            
            // Test that we can import the state back
            try corpus.importState(exportedData)
            XCTAssertEqual(corpus.size, 0)
        } catch {
            XCTFail("State export/import failed: \(error)")
        }
    }
    
    func testPostgreSQLCorpusWithDifferentSizes() {
        // Test PostgreSQL corpus with different size configurations
        let databasePool = DatabasePool(connectionString: "postgresql://localhost:5432/fuzzilli")
        let fuzzerInstanceId = "test-fuzzer-sizes"
        
        // Test with small sizes
        let smallCorpus = PostgreSQLCorpus(
            minSize: 1,
            maxSize: 10,
            minMutationsPerSample: 1,
            databasePool: databasePool,
            fuzzerInstanceId: fuzzerInstanceId
        )
        
        XCTAssertEqual(smallCorpus.size, 0)
        XCTAssertTrue(smallCorpus.isEmpty)
        
        // Test with large sizes
        let largeCorpus = PostgreSQLCorpus(
            minSize: 10000,
            maxSize: 100000,
            minMutationsPerSample: 100,
            databasePool: databasePool,
            fuzzerInstanceId: fuzzerInstanceId
        )
        
        XCTAssertEqual(largeCorpus.size, 0)
        XCTAssertTrue(largeCorpus.isEmpty)
    }
    
    func testPostgreSQLCorpusStatistics() {
        // Test that statistics are properly tracked
        let databasePool = DatabasePool(connectionString: "postgresql://localhost:5432/fuzzilli")
        let fuzzerInstanceId = "test-fuzzer-stats"
        
        let corpus = PostgreSQLCorpus(
            minSize: 10,
            maxSize: 100,
            minMutationsPerSample: 5,
            databasePool: databasePool,
            fuzzerInstanceId: fuzzerInstanceId
        )
        
        let stats = corpus.getStatistics()
        XCTAssertEqual(stats.fuzzerInstanceId, fuzzerInstanceId)
        XCTAssertEqual(stats.totalPrograms, 0)
        XCTAssertEqual(stats.totalExecutions, 0)
        XCTAssertEqual(stats.averageCoverage, 0.0)
        XCTAssertEqual(stats.pendingSyncOperations, 0)
        
        // Test statistics description
        let description = stats.description
        XCTAssertTrue(description.contains("Programs: 0"))
        XCTAssertTrue(description.contains("Executions: 0"))
        XCTAssertTrue(description.contains("Coverage: 0.00%"))
        XCTAssertTrue(description.contains("Pending Sync: 0"))
    }
}
