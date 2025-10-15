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

#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#if !defined(_WIN32)
#include <sys/mman.h>
#include <sys/time.h>
#include <sys/types.h>
#endif

// `unistd.h` is the Unix Standard header.  It is available on all unices.
// macOS wishes to be treated as a unix platform though does not claim to be
// one.
#if defined(__unix__) || (defined(__APPLE__) && defined(__MACH__))
#include <unistd.h>
#endif

#include "libcoverage.h"

#define unlikely(cond) __builtin_expect(!!(cond), 0)

static_assert(MAX_EDGES <= UINT32_MAX, "Edges must be addressable using a 32-bit index");

static inline int edge(const uint8_t* bits, uint64_t index)
{
    return (bits[index / 8] >> (index % 8)) & 0x1;
}

static inline void set_edge(uint8_t* bits, uint64_t index)
{
    bits[index / 8] |= 1 << (index % 8);
}

static inline void clear_edge(uint8_t* bits, uint64_t index)
{
    bits[index / 8] &= ~(1u << (index % 8));
}

int cov_initialize(struct cov_context* context)
{
#if defined(_WIN32)
    char key[1024];
    _snprintf(key, sizeof(key), "shm_id_%u_%u",
              GetCurrentProcessId(), context->id);
    context->hMapping =
            CreateFileMappingA(INVALID_HANDLE_VALUE, NULL, PAGE_READWRITE, 0,
                               SHM_SIZE, key);
    if (!context->hMapping) {
        fprintf(stderr, "[LibCoverage] unable to create file mapping: %lu",
                GetLastError());
        return -1;
    }

    context->shmem =
            MapViewOfFile(context->hMapping, FILE_MAP_ALL_ACCESS, 0, 0, SHM_SIZE);
    if (!context->shmem) {
        CloseHandle(context->hMapping);
        context->hMapping = INVALID_HANDLE_VALUE;
        return -1;
    }
#else
    char shm_key[1024];
    snprintf(shm_key, 1024, "shm_id_%d_%d", getpid(), context->id);

    int fd = shm_open(shm_key, O_RDWR | O_CREAT, S_IREAD | S_IWRITE);
    if (fd <= -1) {
        fprintf(stderr, "[LibCoverage] Failed to create shared memory region\n");
        return -1;
    }
    ftruncate(fd, SHM_SIZE);
    context->shmem = mmap(0, SHM_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    close(fd);
#endif

    // Initialize turbofan optimization bits tracking
    // Perform the initialzation here instead of cov_finish_initialization so when cov_clear_bitmap calls clear_optimization_bits,
    // we don't lose track of the previous optimziation bits
    context->turbofan_optimization_bits_current = 0;
    context->turbofan_optimization_bits_previous = 0;

    return 0;
}

void cov_finish_initialization(struct cov_context* context, int should_track_edges)
{
    uint32_t num_edges = context->shmem->num_edges;
    if (num_edges == 0) {
        fprintf(stderr, "[LibCoverage] Coverage bitmap size could not be determined, is the engine instrumentation working properly?\n");
        exit(-1);
    }

    // Llvm's sanitizer coverage ignores edges whose guard is zero, and our instrumentation stores the bitmap indices in the guard values.
    // To keep the coverage instrumentation as simple as possible, we simply start indexing edges at one and thus ignore the zeroth edge.
    num_edges += 1;

    if (num_edges > MAX_EDGES) {
        fprintf(stderr, "[LibCoverage] Too many edges\n");
        exit(-1);           // TODO
    }

    // Compute the bitmap size in bytes required for the given number of edges and
    // make sure that the allocation size is rounded up to the next 8-byte boundary.
    // We need this because evaluate iterates over the bitmap in 8-byte words.
    uint32_t bitmap_size = (num_edges + 7) / 8;
    bitmap_size += (7 - ((bitmap_size - 1) % 8));

    context->num_edges = num_edges;
    context->bitmap_size = bitmap_size;

    context->should_track_edges = should_track_edges;

    context->virgin_bits = malloc(bitmap_size);
    context->crash_bits = malloc(bitmap_size);

    memset(context->virgin_bits, 0xff, bitmap_size);
    memset(context->crash_bits, 0xff, bitmap_size);

    if (should_track_edges) {
        context->edge_count = malloc(sizeof(uint32_t) * num_edges);
        memset(context->edge_count, 0, sizeof(uint32_t) * num_edges);
    } else {
        context->edge_count = NULL;
    }
    
    // Initialize feedback nexus tracking
    context->current_feedback_nexus = NULL;
    context->previous_feedback_nexus = NULL;

    // Zeroth edge is ignored, see above.
    clear_edge(context->virgin_bits, 0);
    clear_edge(context->crash_bits, 0);
}

void cov_shutdown(struct cov_context* context)
{
#if defined(_WIN32)
    (void)UnmapViewOfFile(context->shmem);
    CloseHandle(context->hMapping);
#else
    char shm_key[1024];
    snprintf(shm_key, 1024, "shm_id_%d_%d", getpid(), context->id);
    shm_unlink(shm_key);
#endif
}

static uint32_t internal_evaluate(struct cov_context* context, uint8_t* virgin_bits, struct edge_set* new_edges)
{
    // Calculate offset to edges array (after feedback nexus data)
    unsigned char* edges_ptr = (unsigned char*)context->shmem + offsetof(struct shmem_data, edges);
    uint64_t* current = (uint64_t*)edges_ptr;
    uint64_t* end = (uint64_t*)(edges_ptr + context->bitmap_size);
    uint64_t* virgin = (uint64_t*)virgin_bits;
    new_edges->count = 0;
    new_edges->edge_indices = NULL;

    // Perform the initial pass regardless of the setting for tracking how often invidual edges are hit
    while (current < end) {
        if (*current && unlikely(*current & *virgin)) {
            // New edge(s) found!
            // We know that we have <= UINT32_MAX edges, so every index can safely be truncated to 32 bits.
            uint32_t index = (uint32_t)((uintptr_t)current - (uintptr_t)edges_ptr) * 8;
            for (uint32_t i = index; i < index + 64; i++) {
                if (edge(edges_ptr, i) == 1 && edge(virgin_bits, i) == 1) {
                    clear_edge(virgin_bits, i);
                    new_edges->count += 1;
                    size_t new_num_entries = new_edges->count;
                    new_edges->edge_indices = realloc(new_edges->edge_indices, new_num_entries * sizeof(uint64_t));
                    new_edges->edge_indices[new_edges->count - 1] = i;
                }
            }
        }

        current++;
        virgin++;
    }

    // Perform a second pass to update edge counts, if the corpus manager requires it.
    // This is in a separate block to increase readability, with a negligible performance penalty in practice,
    // as this pass takes 10-20x as long as the first pass
    if (context->should_track_edges) {
        current = (uint64_t*)edges_ptr;
        while (current < end) {
            uint64_t index = ((uintptr_t)current - (uintptr_t)edges_ptr) * 8;
            for (uint64_t i = index; i < index + 64; i++) {
                if (edge(edges_ptr, i) == 1) {
                    context->edge_count[i]++;
                }
            }
            current++;
        }
    } 
    return new_edges->count;
}

int cov_evaluate(struct cov_context* context, struct edge_set* new_edges)
{
    uint32_t num_new_edges = internal_evaluate(context, context->virgin_bits, new_edges);
    // TODO found_edges should also include crash bits
    context->found_edges += num_new_edges;

    // Checks for feedback nexus and optimziation delta are done separetly in evaluate in ProgramCoverageEvaluator.swift
    // so just update the feedback nexus and optimization bits here and return whether new edges were found.
    cov_update_feedback_nexus(context);
    cov_update_optimization_bits(context);

    // Return 1 if either new edges found
    return (num_new_edges > 0);
}

int cov_evaluate_crash(struct cov_context* context)
{
    struct edge_set new_edges;
    uint32_t num_new_edges = internal_evaluate(context, context->crash_bits, &new_edges);
    free(new_edges.edge_indices);
    return num_new_edges > 0;
}

int cov_compare_equal(struct cov_context* context, uint32_t* edges, uint32_t num_edges)
{
    // Calculate offset to edges array (after feedback nexus data)
    unsigned char* edges_ptr = (unsigned char*)context->shmem + offsetof(struct shmem_data, edges);
    
    for (int i = 0; i < num_edges; i++) {
        int idx = edges[i];
        if (edge(edges_ptr, idx) == 0)
            return 0;
    }

    return 1;
}

void cov_clear_bitmap(struct cov_context* context)
{
    // Calculate offset to edges array (after feedback nexus data)
    unsigned char* edges_ptr = (unsigned char*)context->shmem + offsetof(struct shmem_data, edges);
    memset(edges_ptr, 0, context->bitmap_size);
    clear_feedback_nexus(context);
    clear_optimization_bits(context);
}

int cov_get_edge_counts(struct cov_context* context, struct edge_counts* edges)
{
    if(!context->should_track_edges) {
        return -1;
    }
    edges->edge_hit_count = context->edge_count;
    edges->count = context->num_edges;
    return 0;
}

void cov_clear_edge_data(struct cov_context* context, uint32_t index)
{
    if (context->should_track_edges) {
        assert(context->edge_count[index]);
        context->edge_count[index] = 0;
    }
    context->found_edges -= 1;
    assert(!edge(context->virgin_bits, index));
    set_edge(context->virgin_bits, index);
}

void cov_reset_state(struct cov_context* context) {
    memset(context->virgin_bits, 0xff, context->bitmap_size);
    memset(context->crash_bits, 0xff, context->bitmap_size);

    if (context->edge_count != NULL) {
        memset(context->edge_count, 0, sizeof(uint32_t) * context->num_edges);
    }

    // Zeroth edge is ignored, see above.
    clear_edge(context->virgin_bits, 0);
    clear_edge(context->crash_bits, 0);

    context->found_edges = 0;
    
    // Reset feedback nexus tracking
    if (context->current_feedback_nexus) {
        free(context->current_feedback_nexus->nexus_data);
        free(context->current_feedback_nexus);
        context->current_feedback_nexus = NULL;
    }
    if (context->previous_feedback_nexus) {
        free(context->previous_feedback_nexus->nexus_data);
        free(context->previous_feedback_nexus);
        context->previous_feedback_nexus = NULL;
    }

    // Reset turbofan optimization bits tracking
    context->turbofan_optimization_bits_current = 0;
    context->turbofan_optimization_bits_previous = 0;

    // // Reset maglev optimization bits tracking
    // context->maglev_optimization_bits_current = 0;
    // context->maglev_optimization_bits_previous = 0;
}

int cov_evaluate_feedback_nexus(struct cov_context* context) {
    if (!context->current_feedback_nexus || !context->previous_feedback_nexus) {
        return 0;
    }
    
    if (context->current_feedback_nexus->count != context->previous_feedback_nexus->count) {
        return 1; // delta in # of feedback nexus
    }
    
    // check for delta in feedback nexus data
    for (uint32_t i = 0; i < context->current_feedback_nexus->count; i++) {
        struct feedback_nexus_data* current = &context->current_feedback_nexus->nexus_data[i];
        struct feedback_nexus_data* previous = &context->previous_feedback_nexus->nexus_data[i];
        
        if (current->vector_address != previous->vector_address ||
            current->ic_state != previous->ic_state) {
            return 1;
        }
    }
    return 0;
}

void cov_update_feedback_nexus(struct cov_context* context) {
    if (!context->shmem) return;
    
    // allocate current feedback nexus if not already allocated
    if (!context->current_feedback_nexus) {
        context->current_feedback_nexus = malloc(sizeof(struct feedback_nexus_set));
        context->current_feedback_nexus->nexus_data = malloc(sizeof(struct feedback_nexus_data) * MAX_FEEDBACK_NEXUS);
    }
    
    // copy data from shared memory
    context->current_feedback_nexus->count = context->shmem->feedback_nexus_count;
    for (uint32_t i = 0; i < context->current_feedback_nexus->count && i < MAX_FEEDBACK_NEXUS; i++) {
        context->current_feedback_nexus->nexus_data[i] = context->shmem->feedback_nexus_data[i];
    }
}

void clear_feedback_nexus(struct cov_context* context) {
    struct feedback_nexus_set* temp = context->previous_feedback_nexus;
    context->previous_feedback_nexus = context->current_feedback_nexus;
    context->current_feedback_nexus = temp;
    if (context->current_feedback_nexus) {
        context->current_feedback_nexus->count = 0;
    }
}   

int cov_evaluate_optimization_bits(struct cov_context* context) {
    if (!context->shmem) return 0;
    uint8_t delta = 0;
    // Only check for a delta if current is not 0 and previous is "something"
    // Otherwise if previous is 0, then there is no delta anyway
    if (context->turbofan_optimization_bits_current != 0)
        delta = (uint8_t)(context->turbofan_optimization_bits_current != context->turbofan_optimization_bits_previous);
    return delta;
}

void cov_update_optimization_bits(struct cov_context* context) {
    if (!context->shmem) return;
    context->turbofan_optimization_bits_current = context->shmem->turbofan_optimization_bits;
}

void clear_optimization_bits(struct cov_context* context) {
    context->turbofan_optimization_bits_previous = context->turbofan_optimization_bits_current;
    context->shmem->turbofan_optimization_bits = 0;
}