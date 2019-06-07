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

#ifndef __LIBCOVERAGE_H__
#define __LIBCOVERAGE_H__

#include <stdint.h>
#include <sys/types.h>

struct edge_set {
    uint64_t count;
    unsigned int* edges;
};

#define SHM_SIZE 0x100000
#define MAX_EDGES ((SHM_SIZE - 4) * 8)

// Structure of the shared memory region.
struct shmem_data {
    uint32_t num_edges;
    uint8_t edges[];
};

struct cov_context {
    // Id of this coverage context.
    int id;
    
    // Bitmap of edges that have been discovered so far.
    uint8_t* virgin_bits;
    
    // Bitmap of edges that have been discovered in crashing samples so far.
    uint8_t* crash_bits;

    // Total number of edges in the target program.
    uint64_t num_edges;
    
    // Number of used bytes in the shmem->edges bitmap, roughly num_edges / 8.
    uint64_t bitmap_size;
    
    // Total number of edges that have been discovered so far.
    uint64_t found_edges;
    
    // Pointer into the shared memory region.
    struct shmem_data* shmem;
};

int cov_initialize(struct cov_context*);
void cov_finish_initialization(struct cov_context*);
void cov_shutdown(struct cov_context*);

int cov_evaluate(struct cov_context*, struct edge_set* new_edges);
int cov_evaluate_crash(struct cov_context*);

int cov_compare_equal(struct cov_context*, unsigned int* edges, uint64_t num_edges);

void cov_clear_bitmap(struct cov_context*);

#endif
