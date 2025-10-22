import XCTest
import Foundation
@testable import Fuzzilli

final class DatabasePoolSimpleTests: XCTestCase {
    
    func testDatabasePoolCreation() {
        let pool = DatabasePool(connectionString: "postgresql://test:test@localhost:5432/testdb")
        XCTAssertNotNil(pool)
        XCTAssertFalse(pool.isReady)
    }
    
    func testConnectionStringParsing() {
        let validConnectionStrings = [
            "postgresql://user:pass@localhost:5432/db",
            "postgresql://user@localhost:5432/db",
            "postgresql://user:pass@localhost/db"
        ]
        
        for connectionString in validConnectionStrings {
            let pool = DatabasePool(connectionString: connectionString)
            XCTAssertNotNil(pool)
        }
    }
    
    func testInvalidConnectionString() {
        let invalidConnectionStrings = [
            "invalid://user:pass@localhost:5432/db",
            "not-a-url",
            "",
            "mysql://user:pass@localhost:5432/db"
        ]
        
        for connectionString in invalidConnectionStrings {
            let pool = DatabasePool(connectionString: connectionString)
            XCTAssertNotNil(pool)
            // The pool creation should succeed, but initialization will fail
        }
    }
    
    func testPoolConfiguration() {
        let pool = DatabasePool(
            connectionString: "postgresql://test:test@localhost:5432/testdb",
            maxConnections: 15,
            connectionTimeout: 5.0,
            retryAttempts: 1
        )
        XCTAssertNotNil(pool)
    }
    
    func testPoolStatsStructure() {
        let stats = PoolStats(
            totalConnections: 10,
            activeConnections: 3,
            idleConnections: 7,
            isHealthy: true
        )
        
        XCTAssertEqual(stats.totalConnections, 10)
        XCTAssertEqual(stats.activeConnections, 3)
        XCTAssertEqual(stats.idleConnections, 7)
        XCTAssertTrue(stats.isHealthy)
    }
    
    func testDatabasePoolErrorDescriptions() {
        let errors: [DatabasePoolError] = [
            .notInitialized,
            .initializationFailed("test error"),
            .invalidConnectionString("invalid format"),
            .connectionTimeout,
            .poolExhausted
        ]
        
        for error in errors {
            let description = error.errorDescription
            XCTAssertNotNil(description)
            XCTAssertFalse(description!.isEmpty)
        }
    }
    
    func testDefaultConfiguration() {
        let pool = DatabasePool(connectionString: "postgresql://test:test@localhost:5432/testdb")
        XCTAssertNotNil(pool)
    }
}
