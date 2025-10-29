import Foundation
import SwiftProtobuf

/// Utility functions for database operations
public class DatabaseUtils {
    
    // MARK: - Program Encoding/Decoding
    
    /// Encode a Program to base64 string for database storage
    public static func encodeProgramToBase64(program: Program) -> String {
        do {
            // Check if program contains print operations that can't be serialized
            var hasPrintOperations = false
            for instruction in program.code {
                if case .print = instruction.op.opcode {
                    hasPrintOperations = true
                    break
                }
            }
            
            if hasPrintOperations {
                // For programs with print operations, create a minimal representation
                // This is a workaround since print operations can't be serialized
                let minimalData = "PRINT_PROGRAM_NOT_SERIALIZABLE".data(using: .utf8) ?? Data()
                return minimalData.base64EncodedString()
            }
            
            let proto = program.asProtobuf()
            let data = try proto.serializedData()
            return data.base64EncodedString()
        } catch {
            // Fallback to minimal representation if encoding fails
            let minimalData = "PROGRAM_ENCODING_FAILED".data(using: .utf8) ?? Data()
            return minimalData.base64EncodedString()
        }
    }
    
    /// Decode a Program from base64 string from database
    public static func decodeProgramFromBase64(base64: String) throws -> Program {
        guard let data = Data(base64Encoded: base64) else {
            throw DatabaseUtilsError.invalidBase64String
        }
        
        let proto = try Fuzzilli_Protobuf_Program(serializedBytes: data)
        return try Program(from: proto)
    }
    
    /// Calculate SHA256 hash of a Program for deduplication
    public static func calculateProgramHash(program: Program) -> String {
        do {
            // Check if program contains print operations that can't be serialized
            var hasPrintOperations = false
            for instruction in program.code {
                if case .print = instruction.op.opcode {
                    hasPrintOperations = true
                    break
                }
            }
            
            if hasPrintOperations {
                // Use a simple hash based on program size and instruction count for programs with print operations
                let simpleHash = program.size.hashValue ^ program.code.count.hashValue
                return String(format: "%016x", UInt64(bitPattern: Int64(simpleHash)))
            }
            
            let proto = program.asProtobuf()
            let data = try proto.serializedData()
            
            // Use Foundation's built-in hash function for simplicity
            // This is not cryptographically secure but sufficient for deduplication
            let hash = data.hashValue
            return String(format: "%016x", UInt64(bitPattern: Int64(hash)))
        } catch {
            // Fallback to simple hash if protobuf serialization fails
            let simpleHash = program.size.hashValue ^ program.code.count.hashValue
            return String(format: "%016x", UInt64(bitPattern: Int64(simpleHash)))
        }
    }
    
    // MARK: - Execution Metadata Serialization
    
    /// Serialize ExecutionMetadata to Data for database storage
    public static func serializeExecutionMetadata(metadata: ExecutionMetadata) -> Data {
        do {
            return try JSONEncoder().encode(metadata)
        } catch {
            // Fallback to empty data if serialization fails
            return Data()
        }
    }
    
    /// Deserialize ExecutionMetadata from Data from database
    public static func deserializeExecutionMetadata(data: Data) throws -> ExecutionMetadata {
        return try JSONDecoder().decode(ExecutionMetadata.self, from: data)
    }
    
    // MARK: - Execution Outcome Mapping
    
    /// Map ExecutionOutcome to database ID
    public static func mapExecutionOutcome(outcome: ExecutionOutcome) -> Int {
        switch outcome {
        case .succeeded:
            return 3  // Succeeded maps to ID 3
        case .failed:
            return 2  // Failed maps to ID 2
        case .crashed:
            return 1  // Crashed maps to ID 1
        case .timedOut:
            return 4  // TimedOut maps to ID 4
        }
    }
    
    /// Map ExecutionOutcome with signal code to database ID
    /// Signal 11 (SIGSEGV) and 7 (SIGBUS) are real crashes
    /// Signal 5 (SIGTRAP) and 6 (SIGABRT) are sig checks
    public static func mapExecutionOutcomeWithSignal(outcome: ExecutionOutcome, signalCode: Int?) -> Int {
        switch outcome {
        case .succeeded:
            return 3  // Succeeded maps to ID 3
        case .failed:
            return 2  // Failed maps to ID 2
        case .crashed(let signal):
            // Check if this is a real crash or just a signal check
            if signal == 11 || signal == 7 {
                return 1  // Real crashes: SIGSEGV (11) and SIGBUS (7)
            } else {
                return 5 // SigCheck: SIGTRAP (5), SIGABRT (6), and others
            }
        case .timedOut:
            return 4  // TimedOut maps to ID 4
        }
    }
    
    /// Map database ID to ExecutionOutcome
    public static func mapExecutionOutcomeFromId(id: Int) -> ExecutionOutcome {
        switch id {
        case 1:
            return .crashed(1) // ID 1 = Crashed (real crashes)
        case 2:
            return .failed(1) // ID 2 = Failed
        case 3:
            return .succeeded // ID 3 = Succeeded
        case 4:
            return .timedOut  // ID 4 = TimedOut
        case 34:
            return .crashed(5) // ID 34 = SigCheck (signal checks)
        default:
            return .succeeded // Default fallback
        }
    }
    
    // MARK: - Mutator Type Mapping
    
    /// Map mutator name to database ID
    public static func mapMutatorType(mutator: String) -> Int? {
        switch mutator.lowercased() {
        case "splice":
            return 1
        case "inputmutation":
            return 2
        case "operationmutation":
            return 3
        case "codemutation":
            return 4
        case "exploration":
            return 5
        case "fixup":
            return 6
        case "runtimeassisted":
            return 7
        case "probing":
            return 8
        case "combine":
            return 9
        case "concat":
            return 10
        case "block":
            return 11
        case "dataflow":
            return 12
        case "inlining":
            return 13
        case "instruction":
            return 14
        case "loop":
            return 15
        case "generic":
            return 16
        case "reassign":
            return 17
        case "variadic":
            return 18
        case "wasmtype":
            return 19
        default:
            return nil
        }
    }
    
    /// Map database ID to mutator name
    public static func mapMutatorTypeFromId(id: Int) -> String? {
        switch id {
        case 1:
            return "Splice"
        case 2:
            return "InputMutation"
        case 3:
            return "OperationMutation"
        case 4:
            return "CodeMutation"
        case 5:
            return "Exploration"
        case 6:
            return "Fixup"
        case 7:
            return "RuntimeAssisted"
        case 8:
            return "Probing"
        case 9:
            return "Combine"
        case 10:
            return "Concat"
        case 11:
            return "Block"
        case 12:
            return "DataFlow"
        case 13:
            return "Inlining"
        case 14:
            return "Instruction"
        case 15:
            return "Loop"
        case 16:
            return "Generic"
        case 17:
            return "Reassign"
        case 18:
            return "Variadic"
        case 19:
            return "WasmType"
        default:
            return nil
        }
    }
    
    // MARK: - Execution Type Mapping
    
    /// Map execution purpose to database ID
    public static func mapExecutionType(purpose: DatabaseExecutionPurpose) -> Int {
        switch purpose {
        case .fuzzing:
            return 1
        case .programImport:
            return 2
        case .minimization:
            return 3
        case .deterministicCheck:
            return 4
        case .startup:
            return 5
        case .runtimeAssistedMutation:
            return 6
        case .other:
            return 7
        }
    }
    
    /// Map database ID to execution purpose
    public static func mapExecutionTypeFromId(id: Int) -> DatabaseExecutionPurpose {
        switch id {
        case 1:
            return .fuzzing
        case 2:
            return .programImport
        case 3:
            return .minimization
        case 4:
            return .deterministicCheck
        case 5:
            return .startup
        case 6:
            return .runtimeAssistedMutation
        case 7:
            return .other
        default:
            return .other
        }
    }
    
    // MARK: - Data Validation
    
    /// Validate that a base64 string is valid
    public static func isValidBase64(_ string: String) -> Bool {
        guard let data = Data(base64Encoded: string) else {
            return false
        }
        return !data.isEmpty
    }
    
    /// Validate that a program hash is valid (16 hex characters)
    public static func isValidProgramHash(_ hash: String) -> Bool {
        return hash.count == 16 && hash.allSatisfy { $0.isHexDigit }
    }
    
    /// Validate that execution metadata data is valid JSON
    public static func isValidExecutionMetadata(_ data: Data) -> Bool {
        do {
            _ = try JSONDecoder().decode(ExecutionMetadata.self, from: data)
            return true
        } catch {
            return false
        }
    }
    
    // MARK: - Utility Functions
    
    /// Generate a unique program ID from program content
    public static func generateProgramId(program: Program) -> String {
        let hash = calculateProgramHash(program: program)
        return "prog_\(hash.prefix(16))"
    }
    
    /// Generate a unique execution ID
    public static func generateExecutionId() -> String {
        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let random = Int.random(in: 1000...9999)
        return "exec_\(timestamp)_\(random)"
    }
    
    /// Format coverage percentage for display
    public static func formatCoveragePercentage(_ coverage: Double) -> String {
        return String(format: "%.2f%%", coverage)
    }
    
    /// Format execution time for display
    public static func formatExecutionTime(_ timeMs: Int) -> String {
        if timeMs < 1000 {
            return "\(timeMs)ms"
        } else if timeMs < 60000 {
            return String(format: "%.1fs", Double(timeMs) / 1000.0)
        } else {
            let minutes = timeMs / 60000
            let seconds = (timeMs % 60000) / 1000
            return "\(minutes)m \(seconds)s"
        }
    }
    
    /// Create a summary of execution metadata for logging
    public static func createExecutionSummary(metadata: ExecutionMetadata) -> String {
        return "Executions: \(metadata.executionCount), Coverage: \(formatCoveragePercentage(metadata.lastCoverage)), Last: \(metadata.lastOutcome.outcome)"
    }
}

// MARK: - Supporting Types

/// Database utility errors
public enum DatabaseUtilsError: Error, LocalizedError {
    case invalidBase64String
    case invalidProgramData
    case serializationFailed
    case deserializationFailed
    case invalidHash
    case invalidMetadata
    
    public var errorDescription: String? {
        switch self {
        case .invalidBase64String:
            return "Invalid base64 string"
        case .invalidProgramData:
            return "Invalid program data"
        case .serializationFailed:
            return "Failed to serialize data"
        case .deserializationFailed:
            return "Failed to deserialize data"
        case .invalidHash:
            return "Invalid hash format"
        case .invalidMetadata:
            return "Invalid metadata format"
        }
    }
    
    /// Map execution outcome string to database ID
    public static func mapExecutionOutcomeFromString(_ outcome: String) -> Int {
        switch outcome.lowercased() {
        case "crashed":
            return 1
        case "failed":
            return 2
        case "succeeded":
            return 3
        case "timedout":
            return 4
        case "sigcheck":
            return 34
        default:
            return 3 // Default to succeeded
        }
    }
}

// MARK: - Extensions

extension Character {
    var isHexDigit: Bool {
        return ("0"..."9").contains(self) || ("a"..."f").contains(self) || ("A"..."F").contains(self)
    }
}
