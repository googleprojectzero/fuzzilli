-- Fuzzilli PostgreSQL Database Initialization
-- This script sets up the database schema for Fuzzilli corpus management

-- Create the main fuzzer instance table
CREATE TABLE IF NOT EXISTS main (
    fuzzer_id SERIAL PRIMARY KEY,
    created_at TIMESTAMP DEFAULT NOW(),
    fuzzer_name VARCHAR(100) DEFAULT 'fuzzilli',
    engine_type VARCHAR(50), -- jsc, spidermonkey, v8, duktape, jerryscript
    status VARCHAR(20) DEFAULT 'active' -- active, stopped, error
);

-- Create the fuzzer programs table (corpus)
CREATE TABLE IF NOT EXISTS fuzzer (
    program_hash VARCHAR(64) PRIMARY KEY, -- SHA256 hash for deduplication
    fuzzer_id INT NOT NULL REFERENCES main(fuzzer_id) ON DELETE CASCADE,
    inserted_at TIMESTAMP DEFAULT NOW(),
    program_size INT,
    program_base64 TEXT -- Keep for backward compatibility and lookups
);

-- Create the programs table (executed programs)
CREATE TABLE IF NOT EXISTS program (
    program_hash VARCHAR(64) PRIMARY KEY, -- SHA256 hash for deduplication
    fuzzer_id INT NOT NULL REFERENCES main(fuzzer_id) ON DELETE CASCADE,
    created_at TIMESTAMP DEFAULT NOW(),
    program_size INT,
    program_base64 TEXT, -- Keep for backward compatibility and lookups
    source_mutator VARCHAR(50), -- Which mutator created this program
    parent_program_hash VARCHAR(64) REFERENCES program(program_hash) -- For mutation lineage
);

-- Create execution type lookup table
CREATE TABLE IF NOT EXISTS execution_type (
    id SERIAL PRIMARY KEY,
    title VARCHAR(50) NOT NULL UNIQUE,
    description TEXT
);

-- Preseed execution types
INSERT INTO execution_type (title, description) VALUES 
    ('Fuzzing', 'Program executed for fuzzing purposes'),
    ('Program Import', 'Program executed because it is imported from somewhere'),
    ('Minimization', 'Program executed as part of a minimization task'),
    ('Deterministic Check', 'Program executed to check for deterministic behavior'),
    ('Startup', 'Program executed as part of the startup routine'),
    ('Runtime Assisted Mutation', 'Program executed as part of a runtime-assisted mutation'),
    ('Other', 'Any other execution purpose')
ON CONFLICT (title) DO NOTHING;

-- Create mutator type lookup table
CREATE TABLE IF NOT EXISTS mutator_type (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE,
    description TEXT,
    category VARCHAR(30) -- 'instruction', 'runtime_assisted', 'base'
);

-- Preseed mutator types
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

-- Create execution outcome lookup table
CREATE TABLE IF NOT EXISTS execution_outcome (
    id SERIAL PRIMARY KEY,
    outcome VARCHAR(20) NOT NULL UNIQUE,
    description TEXT
);

-- Preseed execution outcomes
INSERT INTO execution_outcome (outcome, description) VALUES 
    ('Crashed', 'Program crashed with a signal (SIGSEGV/SIGBUS)'),
    ('Failed', 'Program failed with an exit code'),
    ('Succeeded', 'Program executed successfully'),
    ('TimedOut', 'Program execution timed out'),
    ('SigCheck', 'Program terminated with signal (SIGTRAP/SIGABRT)')
ON CONFLICT (outcome) DO NOTHING;

-- Create the main execution table
CREATE TABLE IF NOT EXISTS execution (
    execution_id SERIAL PRIMARY KEY,
    program_hash VARCHAR(64) NOT NULL REFERENCES program(program_hash) ON DELETE CASCADE,
    execution_type_id INTEGER NOT NULL REFERENCES execution_type(id),
    mutator_type_id TEXT, -- Store mutator name directly instead of ID
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
    
    -- Optimization tracking
    turbofan_optimization_bits BIGINT, -- Turbofan optimization bitmap
    feedback_nexus_count INTEGER, -- Number of feedback nexus entries
    
    -- Execution flags and environment
    execution_flags TEXT[], -- Array of flags/options used during execution
    engine_arguments TEXT[], -- JavaScript engine arguments used
    
    created_at TIMESTAMP DEFAULT NOW()
);

-- Create feedback vector details table
CREATE TABLE IF NOT EXISTS feedback_vector_detail (
    id SERIAL PRIMARY KEY,
    execution_id INTEGER NOT NULL REFERENCES execution(execution_id) ON DELETE CASCADE,
    feedback_slot_index INTEGER NOT NULL,
    feedback_slot_kind VARCHAR(50), -- From V8 feedback slot kinds
    feedback_data JSONB, -- Detailed feedback data for this slot
    created_at TIMESTAMP DEFAULT NOW()
);

-- Create coverage details table
CREATE TABLE IF NOT EXISTS coverage_detail (
    id SERIAL PRIMARY KEY,
    execution_id INTEGER NOT NULL REFERENCES execution(execution_id) ON DELETE CASCADE,
    edge_index INTEGER NOT NULL,
    edge_hit_count INTEGER DEFAULT 0,
    is_new_edge BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Create crash analysis table
CREATE TABLE IF NOT EXISTS crash_analysis (
    id SERIAL PRIMARY KEY,
    execution_id INTEGER NOT NULL REFERENCES execution(execution_id) ON DELETE CASCADE,
    crash_type VARCHAR(50), -- Segmentation fault, assertion failure, etc.
    crash_location TEXT, -- Where the crash occurred
    crash_context JSONB, -- Additional crash context
    is_reproducible BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT NOW()
);

-- Coverage tracking over time
CREATE TABLE IF NOT EXISTS coverage_snapshot (
    snapshot_id SERIAL PRIMARY KEY,
    fuzzer_id INTEGER NOT NULL,
    coverage_percentage NUMERIC(10, 8) NOT NULL,
    program_hash TEXT,
    edges_found INTEGER,
    total_edges INTEGER,
    created_at TIMESTAMP DEFAULT NOW(),
    
    FOREIGN KEY (fuzzer_id) REFERENCES main(fuzzer_id)
);

CREATE INDEX IF NOT EXISTS idx_coverage_snapshot_fuzzer ON coverage_snapshot(fuzzer_id);
CREATE INDEX IF NOT EXISTS idx_coverage_snapshot_created ON coverage_snapshot(created_at);

-- Create performance indexes
CREATE INDEX IF NOT EXISTS idx_execution_program ON execution(program_hash);
CREATE INDEX IF NOT EXISTS idx_execution_type ON execution(execution_type_id);
CREATE INDEX IF NOT EXISTS idx_execution_mutator ON execution(mutator_type_id);
CREATE INDEX IF NOT EXISTS idx_execution_outcome ON execution(execution_outcome_id);
CREATE INDEX IF NOT EXISTS idx_execution_created ON execution(created_at);
CREATE INDEX IF NOT EXISTS idx_execution_coverage ON execution(coverage_total);

CREATE INDEX IF NOT EXISTS idx_feedback_vector_execution ON feedback_vector_detail(execution_id);
CREATE INDEX IF NOT EXISTS idx_coverage_detail_execution ON coverage_detail(execution_id);
CREATE INDEX IF NOT EXISTS idx_crash_analysis_execution ON crash_analysis(execution_id);

-- Create foreign key constraint for program table
ALTER TABLE program
ADD CONSTRAINT IF NOT EXISTS fk_program_fuzzer
FOREIGN KEY (program_hash)
REFERENCES fuzzer(program_hash);

-- Create views for common queries
CREATE OR REPLACE VIEW execution_summary AS
SELECT 
    e.execution_id,
    e.program_hash,
    et.title as execution_type,
    e.mutator_type_id as mutator_type, -- Use the TEXT field directly
    eo.outcome as execution_outcome,
    e.coverage_total,
    e.execution_time_ms,
    e.created_at
FROM execution e
JOIN execution_type et ON e.execution_type_id = et.id
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
WHERE eo.outcome IN ('Crashed', 'Failed', 'SigCheck');

-- Create function to get coverage statistics
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

-- Grant permissions
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO fuzzilli;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO fuzzilli;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO fuzzilli;
