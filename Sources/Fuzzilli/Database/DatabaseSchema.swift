import Foundation
import PostgresNIO

/// Manages database schema creation and verification
public class DatabaseSchema {
    private let logger: Logger
    private let enableLogging: Bool
    
    public init(enableLogging: Bool = false) {
        self.enableLogging = enableLogging
        self.logger = Logger(withLabel: "DatabaseSchema")
    }
    
    /// The complete database schema SQL
    public static let schemaSQL = """
    -- Fuzzilli PostgreSQL Database Schema
    -- This schema integrates with the Fuzzilli Docker container and Redis streaming

    -- Main fuzzer instance table
    CREATE TABLE IF NOT EXISTS main (
        fuzzer_id SERIAL PRIMARY KEY,
        created_at TIMESTAMP DEFAULT NOW(),
        fuzzer_name VARCHAR(100) DEFAULT 'fuzzilli',
        engine_type VARCHAR(50), -- jsc, spidermonkey, v8, duktape, jerryscript
        status VARCHAR(20) DEFAULT 'active' -- active, stopped, error
    );

    -- Fuzzer programs table (corpus)
    CREATE TABLE IF NOT EXISTS fuzzer (
        program_hash VARCHAR(64) PRIMARY KEY, -- SHA256 hash for deduplication
        fuzzer_id INT NOT NULL REFERENCES main(fuzzer_id) ON DELETE CASCADE,
        inserted_at TIMESTAMP DEFAULT NOW(),
        program_size INT,
        program_base64 TEXT -- Keep for backward compatibility and lookups
    );

    -- Programs table (executed programs)
    CREATE TABLE IF NOT EXISTS program (
        program_hash VARCHAR(64) PRIMARY KEY, -- SHA256 hash for deduplication
        fuzzer_id INT NOT NULL REFERENCES main(fuzzer_id) ON DELETE CASCADE,
        created_at TIMESTAMP DEFAULT NOW(),
        program_size INT,
        program_base64 TEXT, -- Keep for backward compatibility and lookups
        source_mutator VARCHAR(50), -- Which mutator created this program
        parent_program_hash VARCHAR(64) REFERENCES program(program_hash) -- For mutation lineage
    );

    -- Execution Type lookup table (based on Fuzzilli execution purposes and mutators)
    CREATE TABLE IF NOT EXISTS execution_type (
        id SERIAL PRIMARY KEY,
        title VARCHAR(50) NOT NULL UNIQUE,
        description TEXT
    );

    -- Preseed execution types based on Fuzzilli codebase analysis
    INSERT INTO execution_type (title, description) VALUES 
        ('Fuzzing', 'Program executed for fuzzing purposes'),
        ('Program Import', 'Program executed because it is imported from somewhere'),
        ('Minimization', 'Program executed as part of a minimization task'),
        ('Deterministic Check', 'Program executed to check for deterministic behavior'),
        ('Startup', 'Program executed as part of the startup routine'),
        ('Runtime Assisted Mutation', 'Program executed as part of a runtime-assisted mutation'),
        ('Other', 'Any other execution purpose')
    ON CONFLICT (title) DO NOTHING;

    -- Mutator Type lookup table (based on Fuzzilli mutators)
    CREATE TABLE IF NOT EXISTS mutator_type (
        id SERIAL PRIMARY KEY,
        name VARCHAR(50) NOT NULL UNIQUE,
        description TEXT,
        category VARCHAR(30) -- 'instruction', 'runtime_assisted', 'base'
    );

    -- Preseed mutator types based on Fuzzilli mutators
    INSERT INTO mutator_type (name, description, category) VALUES 
        ('ExplorationMutator', 'Explores new code paths through runtime-assisted mutations', 'runtime_assisted'),
        ('CodeGenMutator', 'Generates new code and inserts it into programs', 'instruction'),
        ('SpliceMutator', 'Splices instructions from one program into another', 'instruction'),
        ('ProbingMutator', 'Probes for new behaviors through runtime-assisted mutations', 'runtime_assisted'),
        ('InputMutator', 'Changes input variables of instructions', 'instruction'),
        ('OperationMutator', 'Mutates operation parameters', 'instruction'),
        ('CombineMutator', 'Combines programs by inserting one into another', 'instruction'),
        ('ConcatMutator', 'Concatenates programs together', 'base'),
        ('FixupMutator', 'Fixes up programs through runtime-assisted mutations', 'runtime_assisted'),
        ('RuntimeAssistedMutator', 'Base class for runtime-assisted mutations', 'runtime_assisted')
    ON CONFLICT (name) DO NOTHING;

    -- Execution Outcome lookup table
    CREATE TABLE IF NOT EXISTS execution_outcome (
        id SERIAL PRIMARY KEY,
        outcome VARCHAR(20) NOT NULL UNIQUE,
        description TEXT
    );

    -- Preseed execution outcomes
    INSERT INTO execution_outcome (outcome, description) VALUES 
        ('Crashed', 'Program crashed with a signal'),
        ('Failed', 'Program failed with an exit code'),
        ('Succeeded', 'Program executed successfully'),
        ('TimedOut', 'Program execution timed out')
    ON CONFLICT (outcome) DO NOTHING;

    -- Main execution table
    CREATE TABLE IF NOT EXISTS execution (
        execution_id SERIAL PRIMARY KEY,
        program_hash VARCHAR(64) NOT NULL REFERENCES program(program_hash) ON DELETE CASCADE,
        execution_type_id INTEGER NOT NULL REFERENCES execution_type(id),
        mutator_type_id INTEGER REFERENCES mutator_type(id),
        execution_outcome_id INTEGER NOT NULL REFERENCES execution_outcome(id),
        
        -- Execution results
        feedback_vector JSONB, -- JSON structure containing execution feedback data
        turboshaft_ir TEXT, -- Turboshaft intermediate representation output
        coverage_total NUMERIC(5,2), -- Total code coverage percentage (0.00 to 999.99)
        
        -- Execution metadata
        execution_time_ms INTEGER, -- Execution time in milliseconds
        signal_code INTEGER, -- Signal code if crashed
        exit_code INTEGER, -- Exit code if failed
        stdout TEXT, -- Standard output
        stderr TEXT, -- Standard error
        fuzzout TEXT, -- Fuzzilli specific output
        
        -- Optimization tracking (from libcoverage)
        turbofan_optimization_bits BIGINT, -- Turbofan optimization bitmap
        feedback_nexus_count INTEGER, -- Number of feedback nexus entries
        
        -- Execution flags and environment
        execution_flags TEXT[], -- Array of flags/options used during execution
        engine_arguments TEXT[], -- JavaScript engine arguments used
        
        created_at TIMESTAMP DEFAULT NOW()
    );

    -- Feedback Vector Details table (for detailed feedback analysis)
    CREATE TABLE IF NOT EXISTS feedback_vector_detail (
        id SERIAL PRIMARY KEY,
        execution_id INTEGER NOT NULL REFERENCES execution(execution_id) ON DELETE CASCADE,
        feedback_slot_index INTEGER NOT NULL,
        feedback_slot_kind VARCHAR(50), -- From V8 feedback slot kinds
        feedback_data JSONB, -- Detailed feedback data for this slot
        created_at TIMESTAMP DEFAULT NOW()
    );

    -- Coverage Details table (for edge coverage tracking)
    CREATE TABLE IF NOT EXISTS coverage_detail (
        id SERIAL PRIMARY KEY,
        execution_id INTEGER NOT NULL REFERENCES execution(execution_id) ON DELETE CASCADE,
        edge_index INTEGER NOT NULL,
        edge_hit_count INTEGER DEFAULT 0,
        is_new_edge BOOLEAN DEFAULT FALSE,
        created_at TIMESTAMP DEFAULT NOW()
    );

    -- Crash Analysis table (for crash tracking and analysis)
    CREATE TABLE IF NOT EXISTS crash_analysis (
        id SERIAL PRIMARY KEY,
        execution_id INTEGER NOT NULL REFERENCES execution(execution_id) ON DELETE CASCADE,
        crash_type VARCHAR(50), -- Segmentation fault, assertion failure, etc.
        crash_location TEXT, -- Where the crash occurred
        crash_context JSONB, -- Additional crash context
        is_reproducible BOOLEAN DEFAULT TRUE,
        created_at TIMESTAMP DEFAULT NOW()
    );

    -- Performance indexes for common queries
    CREATE INDEX IF NOT EXISTS idx_execution_program ON execution(program_hash);
    CREATE INDEX IF NOT EXISTS idx_execution_type ON execution(execution_type_id);
    CREATE INDEX IF NOT EXISTS idx_execution_mutator ON execution(mutator_type_id);
    CREATE INDEX IF NOT EXISTS idx_execution_outcome ON execution(execution_outcome_id);
    CREATE INDEX IF NOT EXISTS idx_execution_created ON execution(created_at);
    CREATE INDEX IF NOT EXISTS idx_execution_coverage ON execution(coverage_total);

    CREATE INDEX IF NOT EXISTS idx_feedback_vector_execution ON feedback_vector_detail(execution_id);
    CREATE INDEX IF NOT EXISTS idx_coverage_detail_execution ON coverage_detail(execution_id);
    CREATE INDEX IF NOT EXISTS idx_crash_analysis_execution ON crash_analysis(execution_id);

    -- Foreign key constraint for program table
    ALTER TABLE program
    ADD CONSTRAINT IF NOT EXISTS fk_program_fuzzer
    FOREIGN KEY (program_hash)
    REFERENCES fuzzer(program_hash);

    -- Views for common queries
    CREATE OR REPLACE VIEW execution_summary AS
    SELECT 
        e.execution_id,
        e.program_hash,
        et.title as execution_type,
        mt.name as mutator_type,
        eo.outcome as execution_outcome,
        e.coverage_total,
        e.execution_time_ms,
        e.created_at
    FROM execution e
    JOIN execution_type et ON e.execution_type_id = et.id
    LEFT JOIN mutator_type mt ON e.mutator_type_id = mt.id
    JOIN execution_outcome eo ON e.execution_outcome_id = eo.id;

    CREATE OR REPLACE VIEW crash_summary AS
    SELECT 
        e.execution_id,
        e.program_hash,
        eo.outcome,
        e.signal_code,
        e.exit_code,
        ca.crash_type,
        ca.is_reproducible,
        e.created_at
    FROM execution e
    JOIN execution_outcome eo ON e.execution_outcome_id = eo.id
    LEFT JOIN crash_analysis ca ON e.execution_id = ca.execution_id
    WHERE eo.outcome IN ('Crashed', 'Failed');

    -- Function to get coverage statistics
    CREATE OR REPLACE FUNCTION get_coverage_stats(fuzzer_instance_id INTEGER)
    RETURNS TABLE (
        total_executions BIGINT,
        avg_coverage NUMERIC,
        max_coverage NUMERIC,
        min_coverage NUMERIC,
        crash_count BIGINT
    ) AS $$
    BEGIN
        RETURN QUERY
        SELECT 
            COUNT(*) as total_executions,
            AVG(e.coverage_total) as avg_coverage,
            MAX(e.coverage_total) as max_coverage,
            MIN(e.coverage_total) as min_coverage,
            COUNT(CASE WHEN eo.outcome = 'Crashed' THEN 1 END) as crash_count
        FROM execution e
        JOIN program p ON e.program_hash = p.program_hash
        JOIN execution_outcome eo ON e.execution_outcome_id = eo.id
        WHERE p.fuzzer_id = fuzzer_instance_id;
    END;
    $$ LANGUAGE plpgsql;
    """
    
    /// Create all database tables and indexes
    public func createTables(connection: PostgresConnection) async throws {
        if enableLogging {
            logger.info("Creating database schema...")
        }
        
        do {
            let query = PostgresQuery(stringLiteral: DatabaseSchema.schemaSQL)
            _ = try await connection.query(query, logger: Logging.Logger(label: "DatabaseSchema"))
            if enableLogging {
                logger.info("Database schema created successfully")
                logger.info("Schema SQL length: \(DatabaseSchema.schemaSQL.count) characters")
            }
        } catch {
            logger.error("Failed to create database schema: \(error)")
            throw error
        }
    }
    
    /// Verify that all required tables exist
    public func verifySchema(connection: PostgresConnection) async throws -> Bool {
        if enableLogging {
            logger.info("Verifying database schema...")
        }
        
        let requiredTables = ["main", "fuzzer", "program", "execution_type", "mutator_type", "execution_outcome", "execution", "feedback_vector_detail", "coverage_detail", "crash_analysis"]
        
        for table in requiredTables {
            let query: PostgresQuery = "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_schema = 'public' AND table_name = \(table))"
            let result = try await connection.query(query, logger: Logging.Logger(label: "DatabaseSchema"))
            
            var exists = false
            for try await row in result {
                exists = try row.decode(Bool.self, context: .default)
                break // We only need the first row
            }
            
            if !exists {
                logger.error("Required table \(table) does not exist")
                return false
            }
        }
        
        if enableLogging {
            logger.info("Database schema verification successful")
        }
        return true
    }
    
    /// Parse connection string and extract components
    public static func parseConnectionString(_ connectionString: String) -> (host: String, port: Int, username: String, password: String?, database: String?) {
        // Simple parsing for postgresql://user:password@host:port/database format
        // For now, return defaults - this can be enhanced later
        return (
            host: "localhost",
            port: 5432,
            username: "postgres",
            password: nil,
            database: "fuzzilli"
        )
    }
    
    /// Get lookup table data
    public func getExecutionTypes(connection: PostgresConnection) async throws -> [ExecutionType] {
        if enableLogging {
            logger.info("Getting execution types from database...")
        }
        
        let query: PostgresQuery = "SELECT id, title, description FROM execution_type ORDER BY id"
        let result = try await connection.query(query, logger: Logging.Logger(label: "DatabaseSchema"))
        
        var executionTypes: [ExecutionType] = []
        for try await row in result {
            let id = try row.decode(Int.self, context: .default)
            let title = try row.decode(String.self, context: .default)
            let description = try row.decode(String?.self, context: .default)
            executionTypes.append(ExecutionType(id: id, title: title, description: description))
        }
        
        if enableLogging {
            logger.info("Retrieved \(executionTypes.count) execution types")
        }
        return executionTypes
    }
    
    public func getMutatorTypes(connection: PostgresConnection) async throws -> [MutatorType] {
        if enableLogging {
            logger.info("Getting mutator types from database...")
        }
        
        let query: PostgresQuery = "SELECT id, name, description, category FROM mutator_type ORDER BY id"
        let result = try await connection.query(query, logger: Logging.Logger(label: "DatabaseSchema"))
        
        var mutatorTypes: [MutatorType] = []
        for try await row in result {
            let id = try row.decode(Int.self, context: .default)
            let name = try row.decode(String.self, context: .default)
            let description = try row.decode(String?.self, context: .default)
            let category = try row.decode(String?.self, context: .default)
            mutatorTypes.append(MutatorType(id: id, name: name, description: description, category: category))
        }
        
        if enableLogging {
            logger.info("Retrieved \(mutatorTypes.count) mutator types")
        }
        return mutatorTypes
    }
    
    public func getExecutionOutcomes(connection: PostgresConnection) async throws -> [DatabaseExecutionOutcome] {
        if enableLogging {
            logger.info("Getting execution outcomes from database...")
        }
        
        let query: PostgresQuery = "SELECT id, outcome, description FROM execution_outcome ORDER BY id"
        let result = try await connection.query(query, logger: Logging.Logger(label: "DatabaseSchema"))
        
        var executionOutcomes: [DatabaseExecutionOutcome] = []
        for try await row in result {
            let id = try row.decode(Int.self, context: .default)
            let outcome = try row.decode(String.self, context: .default)
            let description = try row.decode(String?.self, context: .default)
            executionOutcomes.append(DatabaseExecutionOutcome(id: id, outcome: outcome, description: description))
        }
        
        if enableLogging {
            logger.info("Retrieved \(executionOutcomes.count) execution outcomes")
        }
        return executionOutcomes
    }
}
