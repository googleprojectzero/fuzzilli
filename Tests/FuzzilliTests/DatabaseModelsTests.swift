import XCTest
import Foundation
@testable import Fuzzilli

final class DatabaseModelsTests: XCTestCase {
    
    func testExecutionMetadataCreation() {
        let outcome = DatabaseExecutionOutcome(id: 1, outcome: "Succeeded", description: "Program executed successfully")
        let metadata = ExecutionMetadata(lastOutcome: outcome)
        
        XCTAssertEqual(metadata.executionCount, 0)
        XCTAssertEqual(metadata.lastCoverage, 0.0)
        XCTAssertEqual(metadata.lastOutcome.outcome, "Succeeded")
        XCTAssertTrue(metadata.recentExecutions.isEmpty)
        XCTAssertNil(metadata.feedbackVector)
        XCTAssertTrue(metadata.coverageEdges.isEmpty)
    }
    
    func testExecutionMetadataAddExecution() {
        let outcome = DatabaseExecutionOutcome(id: 1, outcome: "Succeeded", description: "Program executed successfully")
        var metadata = ExecutionMetadata(lastOutcome: outcome)
        
        let execution = ExecutionRecord(
            executionId: 1,
            programBase64: "test_program",
            executionTypeId: 1,
            mutatorTypeId: 1,
            executionOutcomeId: 1,
            feedbackVector: nil,
            turboshaftIr: nil,
            coverageTotal: 85.5,
            executionTimeMs: 100,
            signalCode: nil,
            exitCode: nil,
            stdout: nil,
            stderr: nil,
            fuzzout: nil,
            turbofanOptimizationBits: nil,
            feedbackNexusCount: nil,
            executionFlags: nil,
            engineArguments: nil,
            createdAt: Date()
        )
        
        metadata.addExecution(execution)
        
        XCTAssertEqual(metadata.executionCount, 1)
        XCTAssertEqual(metadata.lastCoverage, 85.5)
        XCTAssertEqual(metadata.recentExecutions.count, 1)
        XCTAssertEqual(metadata.recentExecutions.first?.executionId, 1)
    }
    
    func testExecutionMetadataMaxRecentExecutions() {
        let outcome = DatabaseExecutionOutcome(id: 1, outcome: "Succeeded", description: "Program executed successfully")
        var metadata = ExecutionMetadata(lastOutcome: outcome)
        
        // Add 15 executions (more than the limit of 10)
        for i in 1...15 {
            let execution = ExecutionRecord(
                executionId: i,
                programBase64: "test_program_\(i)",
                executionTypeId: 1,
                mutatorTypeId: 1,
                executionOutcomeId: 1,
                feedbackVector: nil,
                turboshaftIr: nil,
                coverageTotal: Double(i),
                executionTimeMs: 100,
                signalCode: nil,
                exitCode: nil,
                stdout: nil,
                stderr: nil,
                fuzzout: nil,
                turbofanOptimizationBits: nil,
                feedbackNexusCount: nil,
                executionFlags: nil,
                engineArguments: nil,
                createdAt: Date()
            )
            metadata.addExecution(execution)
        }
        
        XCTAssertEqual(metadata.executionCount, 15)
        XCTAssertEqual(metadata.recentExecutions.count, 10) // Should only keep last 10
        XCTAssertEqual(metadata.recentExecutions.first?.executionId, 6) // First should be execution 6
        XCTAssertEqual(metadata.recentExecutions.last?.executionId, 15) // Last should be execution 15
    }
    
    func testExecutionPurposeEnum() {
        XCTAssertEqual(DatabaseExecutionPurpose.fuzzing.rawValue, "Fuzzing")
        XCTAssertEqual(DatabaseExecutionPurpose.minimization.rawValue, "Minimization")
        XCTAssertEqual(DatabaseExecutionPurpose.runtimeAssistedMutation.rawValue, "Runtime Assisted Mutation")
        
        XCTAssertTrue(DatabaseExecutionPurpose.fuzzing.description.contains("fuzzing purposes"))
        XCTAssertTrue(DatabaseExecutionPurpose.minimization.description.contains("minimization task"))
    }
    
    func testMutatorNameEnum() {
        XCTAssertEqual(MutatorName.explorationMutator.rawValue, "ExplorationMutator")
        XCTAssertEqual(MutatorName.codeGenMutator.rawValue, "CodeGenMutator")
        XCTAssertEqual(MutatorName.spliceMutator.rawValue, "SpliceMutator")
        
        XCTAssertEqual(MutatorName.explorationMutator.category, "runtime_assisted")
        XCTAssertEqual(MutatorName.codeGenMutator.category, "instruction")
        XCTAssertEqual(MutatorName.concatMutator.category, "base")
        
        XCTAssertTrue(MutatorName.explorationMutator.description.contains("runtime-assisted mutations"))
        XCTAssertTrue(MutatorName.codeGenMutator.description.contains("Generates new code"))
    }
    
    func testExecutionMetadataSerialization() throws {
        let outcome = DatabaseExecutionOutcome(id: 1, outcome: "Succeeded", description: "Program executed successfully")
        let originalMetadata = ExecutionMetadata(
            executionCount: 5,
            lastExecutionTime: Date(),
            lastCoverage: 75.5,
            lastOutcome: outcome,
            recentExecutions: [],
            feedbackVector: "test_data".data(using: .utf8),
            coverageEdges: [1, 2, 3, 4, 5]
        )
        
        // Test JSON encoding/decoding
        let encoder = JSONEncoder()
        let data = try encoder.encode(originalMetadata)
        
        let decoder = JSONDecoder()
        let decodedMetadata = try decoder.decode(ExecutionMetadata.self, from: data)
        
        XCTAssertEqual(originalMetadata.executionCount, decodedMetadata.executionCount)
        XCTAssertEqual(originalMetadata.lastCoverage, decodedMetadata.lastCoverage)
        XCTAssertEqual(originalMetadata.lastOutcome.outcome, decodedMetadata.lastOutcome.outcome)
        XCTAssertEqual(originalMetadata.feedbackVector, decodedMetadata.feedbackVector)
        XCTAssertEqual(originalMetadata.coverageEdges, decodedMetadata.coverageEdges)
    }
    
    func testFuzzerInstanceCreation() {
        let fuzzer = FuzzerInstance(
            fuzzerId: 1,
            createdAt: Date(),
            fuzzerName: "test_fuzzer",
            engineType: "v8",
            status: "active"
        )
        
        XCTAssertEqual(fuzzer.fuzzerId, 1)
        XCTAssertEqual(fuzzer.fuzzerName, "test_fuzzer")
        XCTAssertEqual(fuzzer.engineType, "v8")
        XCTAssertEqual(fuzzer.status, "active")
    }
    
    func testProgramRecordCreation() {
        let program = ProgramRecord(
            programBase64: "dGVzdF9wcm9ncmFt",
            fuzzerId: 1,
            insertedAt: Date(),
            programSize: 100,
            programHash: "abc123def456"
        )
        
        XCTAssertEqual(program.programBase64, "dGVzdF9wcm9ncmFt")
        XCTAssertEqual(program.fuzzerId, 1)
        XCTAssertEqual(program.programSize, 100)
        XCTAssertEqual(program.programHash, "abc123def456")
    }
    
    func testExecutionRecordCreation() {
        let execution = ExecutionRecord(
            executionId: 1,
            programBase64: "dGVzdF9wcm9ncmFt",
            executionTypeId: 1,
            mutatorTypeId: 2,
            executionOutcomeId: 1,
            feedbackVector: "feedback_data".data(using: .utf8),
            turboshaftIr: "turboshaft_ir_data",
            coverageTotal: 85.5,
            executionTimeMs: 150,
            signalCode: nil,
            exitCode: 0,
            stdout: "stdout_data",
            stderr: "stderr_data",
            fuzzout: "fuzzout_data",
            turbofanOptimizationBits: 12345,
            feedbackNexusCount: 10,
            executionFlags: ["--flag1", "--flag2"],
            engineArguments: ["--arg1", "--arg2"],
            createdAt: Date()
        )
        
        XCTAssertEqual(execution.executionId, 1)
        XCTAssertEqual(execution.programBase64, "dGVzdF9wcm9ncmFt")
        XCTAssertEqual(execution.executionTypeId, 1)
        XCTAssertEqual(execution.mutatorTypeId, 2)
        XCTAssertEqual(execution.executionOutcomeId, 1)
        XCTAssertEqual(execution.coverageTotal, 85.5)
        XCTAssertEqual(execution.executionTimeMs, 150)
        XCTAssertEqual(execution.exitCode, 0)
        XCTAssertEqual(execution.turbofanOptimizationBits, 12345)
        XCTAssertEqual(execution.feedbackNexusCount, 10)
        XCTAssertEqual(execution.executionFlags, ["--flag1", "--flag2"])
        XCTAssertEqual(execution.engineArguments, ["--arg1", "--arg2"])
    }
}
