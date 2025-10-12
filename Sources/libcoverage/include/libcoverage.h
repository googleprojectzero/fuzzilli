// Copyright 2019 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#ifndef LIBCOVERAGE_H
#define LIBCOVERAGE_H

#include <stdint.h>
#include <sys/types.h>
#if defined(_WIN32)
#include <Windows.h>
#endif

// Tracks a set of edges by their indices
struct edge_set {
    uint32_t count;
    uint32_t * edge_indices;
};

// Tracks the hit count of all edges
struct edge_counts {
    uint32_t count;
    uint32_t * edge_hit_count;
};

// Feedback nexus data structure (matches cov.cc)
struct feedback_nexus_data {
    uint32_t vector_address;        // Address of FeedbackVector in V8 heap
    uint32_t ic_state;             // InlineCacheState
};

// Tracks a set of feedback nexus data
struct feedback_nexus_set {
    uint32_t count;
    struct feedback_nexus_data * nexus_data;
};

// Size of the shared memory region. Defines an upper limit on the number of
// coverage edges that can be tracked. When bumping this number, please also
// update Target/coverage.c.
#define SHM_SIZE 0x202000
#define MAX_EDGES ((SHM_SIZE - 4) * 8)
#define MAX_FEEDBACK_NEXUS 100000

// Structure of the shared memory region.
struct shmem_data {
    uint32_t num_edges;
    uint32_t feedback_nexus_count; 
    uint32_t max_feedback_nexus;
    uint32_t turbofan_flags;
    uint64_t turbofan_optimization_bits;
    // uint32_t maglev_optimization_bits;
    struct feedback_nexus_data feedback_nexus_data[MAX_FEEDBACK_NEXUS];
    unsigned char edges[];
};

// Optimization bitmap bit indices (matches V8's OptimizedCompilationInfo::OptimizationBit)
// Update bitmap if ordering changes.
enum optimization_bit {
    BROKER_INIT_AND_SERIALIZATION = 0,
    GRAPH_BUILDER,
    INLINING,
    EARLY_GRAPH_TRIMMING,
    TYPER,
    TYPED_LOWERING,
    LOOP_PEELING,
    LOOP_EXIT_ELIMINATION,
    LOAD_ELIMINATION,
    ESCAPE_ANALYSIS,
    TYPE_ASSERTIONS,
    SIMPLIFIED_LOWERING,
    JS_WASM_INLINING,
    WASM_TYPING,
    WASM_GC_OPTIMIZATION,
    JS_WASM_LOWERING,
    WASM_OPTIMIZATION,
    UNTYPER,
    GENERIC_LOWERING,
    EARLY_OPTIMIZATION,
    SCHEDULING,
    INSTRUCTION_SELECTION,
    REGISTER_ALLOCATION,
    CODE_GENERATION,
    COUNT
};

struct cov_context {
    // Id of this coverage context.
    int id;
    
    int should_track_edges;

    // Bitmap of edges that have been discovered so far.
    uint8_t* virgin_bits;
    
    // Bitmap of edges that have been discovered in crashing samples so far.
    uint8_t* crash_bits;

    // Total number of edges in the target program.
    uint32_t num_edges;
    
    // Number of used bytes in the shmem->edges bitmap, roughly num_edges / 8.
    uint32_t bitmap_size;
    
    // Total number of edges that have been discovered so far.
    uint32_t found_edges;

#if defined(_WIN32)
    // Mapping Handle
    HANDLE hMapping;
#endif

    // Pointer into the shared memory region.
    struct shmem_data* shmem;

    // Count of occurrences per edge
    uint32_t * edge_count;
    
    // Feedback nexus tracking
    struct feedback_nexus_set * current_feedback_nexus;
    struct feedback_nexus_set * previous_feedback_nexus;

    // Turbofan optimization pass tracking
    uint64_t turbofan_optimization_bits_current;
    uint64_t turbofan_optimization_bits_previous;

    // // Maglev optimization pass tracking
    // uint32_t maglev_optimization_bits_current;
    // uint32_t maglev_optimization_bits_previous;
};

int cov_initialize(struct cov_context*);
void cov_finish_initialization(struct cov_context*, int should_track_edges);
void cov_shutdown(struct cov_context*);

int cov_evaluate(struct cov_context* context, struct edge_set* new_edges);
int cov_evaluate_crash(struct cov_context*);

int cov_compare_equal(struct cov_context*, uint32_t* edges, uint32_t num_edges);

void cov_clear_bitmap(struct cov_context*);

int cov_get_edge_counts(struct cov_context* context, struct edge_counts* edges);
void cov_clear_edge_data(struct cov_context* context, uint32_t index);
void cov_reset_state(struct cov_context* context);

// Feedback nexus functions
int cov_evaluate_feedback_nexus(struct cov_context* context);
void cov_update_feedback_nexus(struct cov_context* context);
void clear_feedback_nexus(struct cov_context* context);


// Turbofan and Maglev optimization bits functions
int cov_evaluate_optimization_bits(struct cov_context* context);
void cov_update_optimization_bits(struct cov_context* context);
void clear_optimization_bits(struct cov_context* context);

#endif
