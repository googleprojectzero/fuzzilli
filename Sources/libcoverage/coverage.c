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
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/types.h>
#include <unistd.h>

#include "libcoverage.h"

#define unlikely(cond) __builtin_expect(!!(cond), 0)

#define SHM_SIZE 0x100000
#define MAX_EDGES ((SHM_SIZE - 4) * 8)


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
    
    return 0;
}

void cov_finish_initialization(struct cov_context* context, int should_track_edges)
{
    uint64_t num_edges = context->shmem->num_edges;
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

    uint64_t bitmap_size = (num_edges + 7) / 8; //Num edges in bytes

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

    // Zeroth edge is ignored, see above.
    clear_edge(context->virgin_bits, 0);
    clear_edge(context->crash_bits, 0);
}

void cov_shutdown(struct cov_context* context)
{
    char shm_key[1024];
    snprintf(shm_key, 1024, "shm_id_%d_%d", getpid(), context->id);
    shm_unlink(shm_key);
}

static int internal_evaluate(struct cov_context* context, uint8_t* virgin_bits, struct edge_set* new_edges)
{
    uint64_t* current = (uint64_t*)context->shmem->edges;
    uint64_t* end = (uint64_t*)(context->shmem->edges + context->bitmap_size);
    uint64_t* virgin = (uint64_t*)virgin_bits;
    new_edges->count = 0;
    new_edges->edge_indices = NULL;

    // Perform the initial pass regardless of the setting for tracking how often invidual edges are hit
    while (current < end) {
        if (*current && unlikely(*current & *virgin)) {
            // New edge(s) found!
            uint64_t index = ((uintptr_t)current - (uintptr_t)context->shmem->edges) * 8;
            for (uint64_t i = index; i < index + 64; i++) {
                if (edge(context->shmem->edges, i) == 1 && edge(virgin_bits, i) == 1) {
                    clear_edge(virgin_bits, i);
                    new_edges->count += 1;
                    new_edges->edge_indices = realloc(new_edges->edge_indices, new_edges->count * sizeof(uint64_t));
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
        current = (uint64_t*)context->shmem->edges;
        while (current < end) {
            uint64_t index = ((uintptr_t)current - (uintptr_t)context->shmem->edges) * 8;
            for (uint64_t i = index; i < index + 64; i++) {
                if (edge(context->shmem->edges, i) == 1) {
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
    int num_new_edges = internal_evaluate(context, context->virgin_bits, new_edges);
    // TODO found_edges should also include crash bits
    context->found_edges += num_new_edges;
    return num_new_edges > 0;
}

int cov_evaluate_crash(struct cov_context* context)
{
    struct edge_set new_edges;
    int num_new_edges = internal_evaluate(context, context->crash_bits, &new_edges);
    free(new_edges.edge_indices);
    return num_new_edges > 0;
}

int cov_compare_equal(struct cov_context* context, uint32_t* edges, uint64_t num_edges)
{
    for (int i = 0; i < num_edges; i++) {
        int idx = edges[i];
        if (edge(context->shmem->edges, idx) == 0)
            return 0;
    }

    return 1;
}

void cov_clear_bitmap(struct cov_context* context)
{
    memset(context->shmem->edges, 0, context->bitmap_size);
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

void cov_clear_edge_data(struct cov_context* context, uint64_t index)
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
}

