void __sanitizer_cov_reset_edgeguards(void);
void __sanitizer_cov_trace_pc_guard_init(uint32_t *start, uint32_t *stop);
void __sanitizer_cov_trace_pc_guard(uint32_t *guard);

struct shmem_data {
    uint32_t num_edges;
    unsigned char edges[];
};

#define SHM_SIZE 0x100000
#define MAX_EDGES ((SHM_SIZE - 4) * 8)