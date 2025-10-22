import Foundation

// MARK: - Database Models

/// Represents a fuzzer instance in the main table
public struct FuzzerInstance: Codable {
    public let fuzzerId: Int
    public let createdAt: Date
    public let fuzzerName: String
    public let engineType: String
    public let status: String
    
    public init(fuzzerId: Int, createdAt: Date, fuzzerName: String, engineType: String, status: String) {
        self.fuzzerId = fuzzerId
        self.createdAt = createdAt
        self.fuzzerName = fuzzerName
        self.engineType = engineType
        self.status = status
    }
}

/// Represents a program in the fuzzer table (corpus)
public struct ProgramRecord: Codable {
    public let programBase64: String
    public let fuzzerId: Int
    public let insertedAt: Date
    public let programSize: Int
    public let programHash: String
    
    public init(programBase64: String, fuzzerId: Int, insertedAt: Date, programSize: Int, programHash: String) {
        self.programBase64 = programBase64
        self.fuzzerId = fuzzerId
        self.insertedAt = insertedAt
        self.programSize = programSize
        self.programHash = programHash
    }
}

/// Represents an execution record in the execution table
public struct ExecutionRecord: Codable {
    public let executionId: Int
    public let programBase64: String
    public let executionTypeId: Int
    public let mutatorTypeId: Int?
    public let executionOutcomeId: Int
    public let feedbackVector: Data?
    public let turboshaftIr: String?
    public let coverageTotal: Double?
    public let executionTimeMs: Int?
    public let signalCode: Int?
    public let exitCode: Int?
    public let stdout: String?
    public let stderr: String?
    public let fuzzout: String?
    public let turbofanOptimizationBits: Int64?
    public let feedbackNexusCount: Int?
    public let executionFlags: [String]?
    public let engineArguments: [String]?
    public let createdAt: Date
    
    public init(executionId: Int, programBase64: String, executionTypeId: Int, mutatorTypeId: Int?, executionOutcomeId: Int, feedbackVector: Data?, turboshaftIr: String?, coverageTotal: Double?, executionTimeMs: Int?, signalCode: Int?, exitCode: Int?, stdout: String?, stderr: String?, fuzzout: String?, turbofanOptimizationBits: Int64?, feedbackNexusCount: Int?, executionFlags: [String]?, engineArguments: [String]?, createdAt: Date) {
        self.executionId = executionId
        self.programBase64 = programBase64
        self.executionTypeId = executionTypeId
        self.mutatorTypeId = mutatorTypeId
        self.executionOutcomeId = executionOutcomeId
        self.feedbackVector = feedbackVector
        self.turboshaftIr = turboshaftIr
        self.coverageTotal = coverageTotal
        self.executionTimeMs = executionTimeMs
        self.signalCode = signalCode
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.fuzzout = fuzzout
        self.turbofanOptimizationBits = turbofanOptimizationBits
        self.feedbackNexusCount = feedbackNexusCount
        self.executionFlags = executionFlags
        self.engineArguments = engineArguments
        self.createdAt = createdAt
    }
}

/// Represents feedback vector details
public struct FeedbackVectorDetail: Codable {
    public let id: Int
    public let executionId: Int
    public let feedbackSlotIndex: Int
    public let feedbackSlotKind: String?
    public let feedbackData: Data?
    public let createdAt: Date
    
    public init(id: Int, executionId: Int, feedbackSlotIndex: Int, feedbackSlotKind: String?, feedbackData: Data?, createdAt: Date) {
        self.id = id
        self.executionId = executionId
        self.feedbackSlotIndex = feedbackSlotIndex
        self.feedbackSlotKind = feedbackSlotKind
        self.feedbackData = feedbackData
        self.createdAt = createdAt
    }
}

/// Represents coverage details
public struct CoverageDetail: Codable {
    public let id: Int
    public let executionId: Int
    public let edgeIndex: Int
    public let edgeHitCount: Int
    public let isNewEdge: Bool
    public let createdAt: Date
    
    public init(id: Int, executionId: Int, edgeIndex: Int, edgeHitCount: Int, isNewEdge: Bool, createdAt: Date) {
        self.id = id
        self.executionId = executionId
        self.edgeIndex = edgeIndex
        self.edgeHitCount = edgeHitCount
        self.isNewEdge = isNewEdge
        self.createdAt = createdAt
    }
}

/// Represents crash analysis
public struct CrashAnalysis: Codable {
    public let id: Int
    public let executionId: Int
    public let crashType: String?
    public let crashLocation: String?
    public let crashContext: Data?
    public let isReproducible: Bool
    public let createdAt: Date
    
    public init(id: Int, executionId: Int, crashType: String?, crashLocation: String?, crashContext: Data?, isReproducible: Bool, createdAt: Date) {
        self.id = id
        self.executionId = executionId
        self.crashType = crashType
        self.crashLocation = crashLocation
        self.crashContext = crashContext
        self.isReproducible = isReproducible
        self.createdAt = createdAt
    }
}

// MARK: - Lookup Tables

/// Execution type lookup table
public struct ExecutionType: Codable {
    public let id: Int
    public let title: String
    public let description: String?
    
    public init(id: Int, title: String, description: String?) {
        self.id = id
        self.title = title
        self.description = description
    }
}

/// Mutator type lookup table
public struct MutatorType: Codable {
    public let id: Int
    public let name: String
    public let description: String?
    public let category: String?
    
    public init(id: Int, name: String, description: String?, category: String?) {
        self.id = id
        self.name = name
        self.description = description
        self.category = category
    }
}

/// Execution outcome lookup table
public struct DatabaseExecutionOutcome: Codable {
    public let id: Int
    public let outcome: String
    public let description: String?
    
    public init(id: Int, outcome: String, description: String?) {
        self.id = id
        self.outcome = outcome
        self.description = description
    }
}

// MARK: - In-Memory Execution Metadata

/// Execution metadata for in-memory tracking
public struct ExecutionMetadata: Codable {
    public var executionCount: Int
    public var lastExecutionTime: Date
    public var lastCoverage: Double
    public var lastOutcome: DatabaseExecutionOutcome
    public var recentExecutions: [ExecutionRecord] // Last 10 executions
    public var feedbackVector: Data?
    public var coverageEdges: Set<Int>
    
    public init(executionCount: Int = 0, lastExecutionTime: Date = Date(), lastCoverage: Double = 0.0, lastOutcome: DatabaseExecutionOutcome, recentExecutions: [ExecutionRecord] = [], feedbackVector: Data? = nil, coverageEdges: Set<Int> = []) {
        self.executionCount = executionCount
        self.lastExecutionTime = lastExecutionTime
        self.lastCoverage = lastCoverage
        self.lastOutcome = lastOutcome
        self.recentExecutions = recentExecutions
        self.feedbackVector = feedbackVector
        self.coverageEdges = coverageEdges
    }
    
    /// Add a new execution to the recent executions list, keeping only the last 10
    public mutating func addExecution(_ execution: ExecutionRecord) {
        recentExecutions.append(execution)
        if recentExecutions.count > 10 {
            recentExecutions.removeFirst()
        }
        
        // Update metadata
        executionCount += 1
        lastExecutionTime = execution.createdAt
        if let coverage = execution.coverageTotal {
            lastCoverage = coverage
        }
        
        // Update outcome (we'll need to map from executionOutcomeId)
        // This will be handled by the caller who has access to the lookup table
    }
    
    /// Update the last outcome (called after adding execution)
    public mutating func updateLastOutcome(_ outcome: DatabaseExecutionOutcome) {
        self.lastOutcome = outcome
    }
}

// MARK: - Execution Purpose Enum

/// Execution purpose for mapping to execution_type_id
public enum DatabaseExecutionPurpose: String, CaseIterable {
    case fuzzing = "Fuzzing"
    case programImport = "Program Import"
    case minimization = "Minimization"
    case deterministicCheck = "Deterministic Check"
    case startup = "Startup"
    case runtimeAssistedMutation = "Runtime Assisted Mutation"
    case other = "Other"
    
    public var description: String {
        switch self {
        case .fuzzing:
            return "Program executed for fuzzing purposes"
        case .programImport:
            return "Program executed because it is imported from somewhere"
        case .minimization:
            return "Program executed as part of a minimization task"
        case .deterministicCheck:
            return "Program executed to check for deterministic behavior"
        case .startup:
            return "Program executed as part of the startup routine"
        case .runtimeAssistedMutation:
            return "Program executed as part of a runtime-assisted mutation"
        case .other:
            return "Any other execution purpose"
        }
    }
}

// MARK: - Mutator Name Enum

/// Mutator names for mapping to mutator_type_id
public enum MutatorName: String, CaseIterable {
    case explorationMutator = "ExplorationMutator"
    case codeGenMutator = "CodeGenMutator"
    case spliceMutator = "SpliceMutator"
    case probingMutator = "ProbingMutator"
    case inputMutator = "InputMutator"
    case operationMutator = "OperationMutator"
    case combineMutator = "CombineMutator"
    case concatMutator = "ConcatMutator"
    case fixupMutator = "FixupMutator"
    case runtimeAssistedMutator = "RuntimeAssistedMutator"
    
    public var description: String {
        switch self {
        case .explorationMutator:
            return "Explores new code paths through runtime-assisted mutations"
        case .codeGenMutator:
            return "Generates new code and inserts it into programs"
        case .spliceMutator:
            return "Splices instructions from one program into another"
        case .probingMutator:
            return "Probes for new behaviors through runtime-assisted mutations"
        case .inputMutator:
            return "Changes input variables of instructions"
        case .operationMutator:
            return "Mutates operation parameters"
        case .combineMutator:
            return "Combines programs by inserting one into another"
        case .concatMutator:
            return "Concatenates programs together"
        case .fixupMutator:
            return "Fixes up programs through runtime-assisted mutations"
        case .runtimeAssistedMutator:
            return "Base class for runtime-assisted mutations"
        }
    }
    
    public var category: String {
        switch self {
        case .explorationMutator, .probingMutator, .fixupMutator, .runtimeAssistedMutator:
            return "runtime_assisted"
        case .codeGenMutator, .spliceMutator, .inputMutator, .operationMutator, .combineMutator:
            return "instruction"
        case .concatMutator:
            return "base"
        }
    }
}
