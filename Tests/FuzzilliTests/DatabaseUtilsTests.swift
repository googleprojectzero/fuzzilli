import XCTest
import Foundation
@testable import Fuzzilli

final class DatabaseUtilsTests: XCTestCase {

    func testProgramEncodingDecoding() throws {
        // Create a simple program using ProgramBuilder
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()
        b.loadInt(42)
        b.loadString("test")
        let program = b.finalize()
        
        // Test encoding
        let base64 = DatabaseUtils.encodeProgramToBase64(program: program)
        XCTAssertFalse(base64.isEmpty, "Base64 encoding should not be empty")
        
        // Test decoding
        let decodedProgram = try DatabaseUtils.decodeProgramFromBase64(base64: base64)
        XCTAssertEqual(decodedProgram.size, program.size, "Decoded program should have same size")
    }
    
    func testProgramHashCalculation() {
        // Create a simple program using ProgramBuilder
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()
        b.loadInt(42)
        b.loadString("test")
        let program = b.finalize()
        
        // Test hash calculation
        let hash = DatabaseUtils.calculateProgramHash(program: program)
        XCTAssertEqual(hash.count, 16, "Hash should be 16 characters")
        XCTAssertTrue(hash.allSatisfy { $0.isHexDigit }, "Hash should contain only hex digits")
        
        // Test hash consistency
        let hash2 = DatabaseUtils.calculateProgramHash(program: program)
        XCTAssertEqual(hash, hash2, "Hash should be consistent for same program")
    }
    
    func testExecutionMetadataSerialization() throws {
        // Create execution metadata
        let outcome = DatabaseExecutionOutcome(id: 1, outcome: "Succeeded", description: "Program executed successfully")
        var metadata = ExecutionMetadata(lastOutcome: outcome)
        metadata.executionCount = 5
        metadata.lastCoverage = 85.5
        
        // Test serialization
        let data = DatabaseUtils.serializeExecutionMetadata(metadata: metadata)
        XCTAssertFalse(data.isEmpty, "Serialized data should not be empty")
        
        // Test deserialization
        let deserializedMetadata = try DatabaseUtils.deserializeExecutionMetadata(data: data)
        XCTAssertEqual(deserializedMetadata.executionCount, metadata.executionCount)
        XCTAssertEqual(deserializedMetadata.lastCoverage, metadata.lastCoverage, accuracy: 0.01)
        XCTAssertEqual(deserializedMetadata.lastOutcome.outcome, metadata.lastOutcome.outcome)
    }
    
    func testExecutionOutcomeMapping() {
        // Test mapping to database ID
        XCTAssertEqual(DatabaseUtils.mapExecutionOutcome(outcome: .succeeded), 1)
        XCTAssertEqual(DatabaseUtils.mapExecutionOutcome(outcome: .failed(1)), 2)
        XCTAssertEqual(DatabaseUtils.mapExecutionOutcome(outcome: .crashed(1)), 3)
        XCTAssertEqual(DatabaseUtils.mapExecutionOutcome(outcome: .timedOut), 4)
        
        // Test mapping from database ID
        XCTAssertEqual(DatabaseUtils.mapExecutionOutcomeFromId(id: 1), .succeeded)
        XCTAssertEqual(DatabaseUtils.mapExecutionOutcomeFromId(id: 2), .failed(1))
        XCTAssertEqual(DatabaseUtils.mapExecutionOutcomeFromId(id: 3), .crashed(1))
        XCTAssertEqual(DatabaseUtils.mapExecutionOutcomeFromId(id: 4), .timedOut)
        XCTAssertEqual(DatabaseUtils.mapExecutionOutcomeFromId(id: 999), .succeeded) // Invalid ID fallback
    }
    
    func testMutatorTypeMapping() {
        // Test mapping to database ID
        XCTAssertEqual(DatabaseUtils.mapMutatorType(mutator: "Splice"), 1)
        XCTAssertEqual(DatabaseUtils.mapMutatorType(mutator: "splice"), 1) // Case insensitive
        XCTAssertEqual(DatabaseUtils.mapMutatorType(mutator: "InputMutation"), 2)
        XCTAssertEqual(DatabaseUtils.mapMutatorType(mutator: "WasmType"), 19)
        XCTAssertNil(DatabaseUtils.mapMutatorType(mutator: "UnknownMutator"))
        
        // Test mapping from database ID
        XCTAssertEqual(DatabaseUtils.mapMutatorTypeFromId(id: 1), "Splice")
        XCTAssertEqual(DatabaseUtils.mapMutatorTypeFromId(id: 2), "InputMutation")
        XCTAssertEqual(DatabaseUtils.mapMutatorTypeFromId(id: 19), "WasmType")
        XCTAssertNil(DatabaseUtils.mapMutatorTypeFromId(id: 999)) // Invalid ID
    }
    
    func testExecutionTypeMapping() {
        // Test mapping to database ID
        XCTAssertEqual(DatabaseUtils.mapExecutionType(purpose: .fuzzing), 1)
        XCTAssertEqual(DatabaseUtils.mapExecutionType(purpose: .programImport), 2)
        XCTAssertEqual(DatabaseUtils.mapExecutionType(purpose: .minimization), 3)
        XCTAssertEqual(DatabaseUtils.mapExecutionType(purpose: .other), 7)
        
        // Test mapping from database ID
        XCTAssertEqual(DatabaseUtils.mapExecutionTypeFromId(id: 1), .fuzzing)
        XCTAssertEqual(DatabaseUtils.mapExecutionTypeFromId(id: 2), .programImport)
        XCTAssertEqual(DatabaseUtils.mapExecutionTypeFromId(id: 3), .minimization)
        XCTAssertEqual(DatabaseUtils.mapExecutionTypeFromId(id: 7), .other)
        XCTAssertEqual(DatabaseUtils.mapExecutionTypeFromId(id: 999), .other) // Invalid ID
    }
    
    func testDataValidation() {
        // Test base64 validation
        XCTAssertTrue(DatabaseUtils.isValidBase64("SGVsbG8gV29ybGQ=")) // "Hello World"
        XCTAssertFalse(DatabaseUtils.isValidBase64("Invalid base64!"))
        XCTAssertFalse(DatabaseUtils.isValidBase64(""))
        
        // Test program hash validation
        let validHash = "a1b2c3d4e5f67890"
        XCTAssertTrue(DatabaseUtils.isValidProgramHash(validHash))
        XCTAssertFalse(DatabaseUtils.isValidProgramHash("invalid hash"))
        XCTAssertFalse(DatabaseUtils.isValidProgramHash("short"))
        XCTAssertFalse(DatabaseUtils.isValidProgramHash(""))
        
        // Test execution metadata validation
        let outcome = DatabaseExecutionOutcome(id: 1, outcome: "Succeeded", description: "Test")
        let metadata = ExecutionMetadata(lastOutcome: outcome)
        let validData = DatabaseUtils.serializeExecutionMetadata(metadata: metadata)
        XCTAssertTrue(DatabaseUtils.isValidExecutionMetadata(validData))
        XCTAssertFalse(DatabaseUtils.isValidExecutionMetadata(Data("invalid json".utf8)))
    }
    
    func testUtilityFunctions() {
        // Test program ID generation
        let fuzzer = makeMockFuzzer()
        let b = fuzzer.makeBuilder()
        b.loadInt(42)
        let program = b.finalize()
        let programId = DatabaseUtils.generateProgramId(program: program)
        XCTAssertTrue(programId.hasPrefix("prog_"))
        XCTAssertEqual(programId.count, 21) // "prog_" + 16 hex chars
        
        // Test execution ID generation
        let executionId = DatabaseUtils.generateExecutionId()
        XCTAssertTrue(executionId.hasPrefix("exec_"))
        XCTAssertTrue(executionId.contains("_"))
        
        // Test coverage formatting
        XCTAssertEqual(DatabaseUtils.formatCoveragePercentage(85.5), "85.50%")
        XCTAssertEqual(DatabaseUtils.formatCoveragePercentage(0.0), "0.00%")
        XCTAssertEqual(DatabaseUtils.formatCoveragePercentage(100.0), "100.00%")
        
        // Test execution time formatting
        XCTAssertEqual(DatabaseUtils.formatExecutionTime(500), "500ms")
        XCTAssertEqual(DatabaseUtils.formatExecutionTime(1500), "1.5s")
        XCTAssertEqual(DatabaseUtils.formatExecutionTime(65000), "1m 5s")
        XCTAssertEqual(DatabaseUtils.formatExecutionTime(125000), "2m 5s")
    }
    
    func testExecutionSummary() {
        let outcome = DatabaseExecutionOutcome(id: 1, outcome: "Succeeded", description: "Test")
        var metadata = ExecutionMetadata(lastOutcome: outcome)
        metadata.executionCount = 10
        metadata.lastCoverage = 75.5
        
        let summary = DatabaseUtils.createExecutionSummary(metadata: metadata)
        XCTAssertTrue(summary.contains("Executions: 10"))
        XCTAssertTrue(summary.contains("Coverage: 75.50%"))
        XCTAssertTrue(summary.contains("Last: Succeeded"))
    }
    
    func testDatabaseUtilsErrorDescriptions() {
        XCTAssertEqual(DatabaseUtilsError.invalidBase64String.errorDescription, "Invalid base64 string")
        XCTAssertEqual(DatabaseUtilsError.invalidProgramData.errorDescription, "Invalid program data")
        XCTAssertEqual(DatabaseUtilsError.serializationFailed.errorDescription, "Failed to serialize data")
        XCTAssertEqual(DatabaseUtilsError.deserializationFailed.errorDescription, "Failed to deserialize data")
        XCTAssertEqual(DatabaseUtilsError.invalidHash.errorDescription, "Invalid hash format")
        XCTAssertEqual(DatabaseUtilsError.invalidMetadata.errorDescription, "Invalid metadata format")
    }
    
    func testCharacterHexDigitExtension() {
        XCTAssertTrue("0".first!.isHexDigit)
        XCTAssertTrue("9".first!.isHexDigit)
        XCTAssertTrue("a".first!.isHexDigit)
        XCTAssertTrue("f".first!.isHexDigit)
        XCTAssertTrue("A".first!.isHexDigit)
        XCTAssertTrue("F".first!.isHexDigit)
        XCTAssertFalse("g".first!.isHexDigit)
        XCTAssertFalse("Z".first!.isHexDigit)
        XCTAssertFalse("@".first!.isHexDigit)
    }
}
