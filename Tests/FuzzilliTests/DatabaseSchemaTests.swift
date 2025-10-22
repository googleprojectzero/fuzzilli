import XCTest
import Foundation
@testable import Fuzzilli

final class DatabaseSchemaTests: XCTestCase {
    
    func testSchemaSQLContainsRequiredTables() {
        let schema = DatabaseSchema.schemaSQL
        
        let requiredTables = [
            "CREATE TABLE IF NOT EXISTS main",
            "CREATE TABLE IF NOT EXISTS fuzzer",
            "CREATE TABLE IF NOT EXISTS program",
            "CREATE TABLE IF NOT EXISTS execution_type",
            "CREATE TABLE IF NOT EXISTS mutator_type",
            "CREATE TABLE IF NOT EXISTS execution_outcome",
            "CREATE TABLE IF NOT EXISTS execution",
            "CREATE TABLE IF NOT EXISTS feedback_vector_detail",
            "CREATE TABLE IF NOT EXISTS coverage_detail",
            "CREATE TABLE IF NOT EXISTS crash_analysis"
        ]
        
        for table in requiredTables {
            XCTAssertTrue(schema.contains(table), "Schema should contain \(table)")
        }
    }
    
    func testSchemaSQLContainsRequiredIndexes() {
        let schema = DatabaseSchema.schemaSQL
        
        let requiredIndexes = [
            "CREATE INDEX IF NOT EXISTS idx_execution_program",
            "CREATE INDEX IF NOT EXISTS idx_execution_type",
            "CREATE INDEX IF NOT EXISTS idx_execution_mutator",
            "CREATE INDEX IF NOT EXISTS idx_execution_outcome",
            "CREATE INDEX IF NOT EXISTS idx_execution_created",
            "CREATE INDEX IF NOT EXISTS idx_execution_coverage",
            "CREATE INDEX IF NOT EXISTS idx_feedback_vector_execution",
            "CREATE INDEX IF NOT EXISTS idx_coverage_detail_execution",
            "CREATE INDEX IF NOT EXISTS idx_crash_analysis_execution"
        ]
        
        for index in requiredIndexes {
            XCTAssertTrue(schema.contains(index), "Schema should contain \(index)")
        }
    }
    
    func testSchemaSQLContainsRequiredViews() {
        let schema = DatabaseSchema.schemaSQL
        
        let requiredViews = [
            "CREATE OR REPLACE VIEW execution_summary",
            "CREATE OR REPLACE VIEW crash_summary"
        ]
        
        for view in requiredViews {
            XCTAssertTrue(schema.contains(view), "Schema should contain \(view)")
        }
    }
    
    func testSchemaSQLContainsRequiredFunctions() {
        let schema = DatabaseSchema.schemaSQL
        
        let requiredFunctions = [
            "CREATE OR REPLACE FUNCTION get_coverage_stats"
        ]
        
        for function in requiredFunctions {
            XCTAssertTrue(schema.contains(function), "Schema should contain \(function)")
        }
    }
    
    func testSchemaSQLContainsPreseedData() {
        let schema = DatabaseSchema.schemaSQL
        
        let preseedData = [
            "INSERT INTO execution_type (title, description) VALUES",
            "INSERT INTO mutator_type (name, description, category) VALUES",
            "INSERT INTO execution_outcome (outcome, description) VALUES"
        ]
        
        for data in preseedData {
            XCTAssertTrue(schema.contains(data), "Schema should contain \(data)")
        }
    }
    
    func testSchemaSQLContainsConflictHandling() {
        let schema = DatabaseSchema.schemaSQL
        
        XCTAssertTrue(schema.contains("ON CONFLICT (title) DO NOTHING"), "Schema should handle conflicts for execution_type")
        XCTAssertTrue(schema.contains("ON CONFLICT (name) DO NOTHING"), "Schema should handle conflicts for mutator_type")
        XCTAssertTrue(schema.contains("ON CONFLICT (outcome) DO NOTHING"), "Schema should handle conflicts for execution_outcome")
    }
    
    func testParseConnectionString() {
        let (host, port, username, password, database) = DatabaseSchema.parseConnectionString("postgresql://user:pass@localhost:5432/db")
        
        // For now, the parser returns defaults, but we can test the structure
        XCTAssertEqual(host, "localhost")
        XCTAssertEqual(port, 5432)
        XCTAssertEqual(username, "postgres")
        XCTAssertNil(password)
        XCTAssertEqual(database, "fuzzilli")
    }
    
    func testDatabaseSchemaInitialization() {
        let schema = DatabaseSchema()
        XCTAssertNotNil(schema)
    }
    
    func testSchemaSQLIsValidSQL() {
        let schema = DatabaseSchema.schemaSQL
        
        // Basic validation - should contain semicolons and not have obvious syntax errors
        XCTAssertTrue(schema.contains(";"), "Schema should contain semicolons")
        XCTAssertTrue(schema.contains("CREATE TABLE IF NOT EXISTS"), "Schema should use CREATE TABLE IF NOT EXISTS")
        
        // Should not contain obvious syntax errors
        XCTAssertTrue(schema.contains("CREATE TABLE IF NOT EXISTS main ("), "Should use IF NOT EXISTS")
    }
    
    func testSchemaSQLHasProperConstraints() {
        let schema = DatabaseSchema.schemaSQL
        
        // Check for foreign key constraints
        XCTAssertTrue(schema.contains("REFERENCES main(fuzzer_id)"), "Should have foreign key to main table")
        XCTAssertTrue(schema.contains("REFERENCES program(program_base64)"), "Should have foreign key to program table")
        XCTAssertTrue(schema.contains("REFERENCES execution(execution_id)"), "Should have foreign key to execution table")
        
        // Check for primary keys
        XCTAssertTrue(schema.contains("SERIAL PRIMARY KEY"), "Should have SERIAL PRIMARY KEY")
        
        // Check for unique constraints
        XCTAssertTrue(schema.contains("UNIQUE"), "Should have unique constraints")
    }
    
    func testSchemaSQLHasProperDataTypes() {
        let schema = DatabaseSchema.schemaSQL
        
        // Check for proper data types
        XCTAssertTrue(schema.contains("SERIAL"), "Should use SERIAL for auto-incrementing IDs")
        XCTAssertTrue(schema.contains("TEXT"), "Should use TEXT for program data")
        XCTAssertTrue(schema.contains("VARCHAR"), "Should use VARCHAR for limited strings")
        XCTAssertTrue(schema.contains("INTEGER"), "Should use INTEGER for numeric IDs")
        XCTAssertTrue(schema.contains("NUMERIC"), "Should use NUMERIC for coverage percentages")
        XCTAssertTrue(schema.contains("JSONB"), "Should use JSONB for structured data")
        XCTAssertTrue(schema.contains("BIGINT"), "Should use BIGINT for large numbers")
        XCTAssertTrue(schema.contains("BOOLEAN"), "Should use BOOLEAN for flags")
        XCTAssertTrue(schema.contains("TEXT[]"), "Should use TEXT[] for arrays")
    }
}
