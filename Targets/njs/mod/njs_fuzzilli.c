#include <njs.h>
#include <njs_unix.h>
#include <njs_arr.h>
#include <njs_queue.h>
#include <njs_rbtree.h>
#include <stdio.h>
#include <sys/types.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include "njs_coverage.h"
#include <njs_fuzzilli_shell.c>


// defs
#define REPRL_CRFD 100
#define REPRL_CWFD 101
#define REPRL_DRFD 102
#define REPRL_DWFD 103

#define SHM_SIZE 0x100000
#define MAX_EDGES ((SHM_SIZE - 4) * 8)

#define CHECK(cond) if (!(cond)) { fprintf(stderr, "\"" #cond "\" failed\n"); _exit(-1); }

// Will be imported from `njs_fuzzilli_module.o` during linking phase
extern struct shmem_data* __shmem;
extern uint32_t *__edges_start, *__edges_stop;


njs_str_t* njs_fetch_fuzz_input(void);

njs_str_t* njs_fetch_fuzz_input(void) {
    njs_str_t     *script = NULL;
    char *script_src, *ptr;
    size_t script_size = 0, remaining = 0;
    unsigned action;
    
    script_size = 0;
    CHECK(read(REPRL_CRFD, &action, 4) == 4);
    if (action == 'cexe') {
        CHECK(read(REPRL_CRFD, &script_size, 8) == 8);
    } else {
        fprintf(stderr, "Unknown action: %u\n", action);
        _exit(-1);
    }
    
    script_src = malloc(script_size+1);
    ptr = script_src;
    remaining = script_size;

    while (remaining > 0) {
        ssize_t rv = read(REPRL_DRFD, ptr, remaining);
        if (rv <= 0) {
            fprintf(stderr, "Failed to load script\n");
            _exit(-1);
        }
        remaining -= rv;
        ptr += rv;
    }

    script = malloc(sizeof(njs_str_t));
    script_src[script_size] = '\0';
    script->start = (u_char*)script_src;
    script->length = script_size;

    return script;
}


static njs_int_t
njs_main_fuzzable(njs_opts_t *opts)
{
    njs_int_t     ret;
    njs_engine_t  *engine;

    engine = njs_create_engine(opts);
    if (engine == NULL) {
        return NJS_ERROR;
    }

    ret = njs_console_init(opts, &njs_console);
    if (njs_slow_path(ret != NJS_OK)) {
        njs_stderror("njs_console_init() failed\n");
        return NJS_ERROR;
    }

    ret = njs_process_script(engine, &njs_console, &opts->command);
    engine->destroy(engine);
    return ret;
}


int
main(int argc, char **argv)
{
    njs_opts_t  opts;
    njs_memzero(&opts, sizeof(njs_opts_t));
    int result=0, status=0;

    if(argc < 2) {
        printf("usage: ./%s <opt>\navailable opts: \n\t'filename.js' - path of js file to be executed\n\tfuzz - entering REPRL mode(fuzzilli)\n", argv[0]);
        return NJS_ERROR;
    }

    if(!strcmp(argv[1], "fuzz")) {
        char helo[] = "HELO";
        if (write(REPRL_CWFD, helo, 4) != 4 || read(REPRL_CRFD, helo, 4) != 4) {
            printf("Invalid HELO response from parent\n");
            _exit(-1);
        }

        if (memcmp(helo, "HELO", 4) != 0) {
            printf("Invalid response from parent\n");
            _exit(-1);
        }

        while(1) {
            njs_str_t* fuzzer_input = njs_fetch_fuzz_input();

            opts.file = (char *) "fuzzer";
            opts.command.start   = fuzzer_input->start;
            opts.command.length  = fuzzer_input->length;
            opts.suppress_stdout = 0;
            result = njs_main_fuzzable(&opts);

            free(fuzzer_input->start);
            free(fuzzer_input);

            status = (result & 0xff) << 8;
            CHECK(write(REPRL_CWFD, &status, 4) == 4);
            __sanitizer_cov_reset_edgeguards();
        }
    } else {
        njs_int_t     ret;
        njs_engine_t  *engine;

        opts.file = argv[1];
        engine = njs_create_engine(&opts);
        if (engine == NULL) {
            return NJS_ERROR;
        }

        ret = njs_console_init(&opts, &njs_console);
        if (njs_slow_path(ret != NJS_OK)) {
            njs_stderror("njs_console_init() failed\n");
            return NJS_ERROR;
        }
        result = njs_process_file(&opts);
        engine->destroy(engine);

    }

    return result;
}

