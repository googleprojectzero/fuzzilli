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

#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <unistd.h>
#include <sys/time.h>
#include <sys/mman.h>
#include <sys/stat.h>

// Well-defined file descriptor numbers for fuzzer <-> fuzzee communication, child process side
#define CRFD 100
#define CWFD 101
#define DRFD 102
#define DWFD 103

#define SHM_SIZE 0x100000

#define CHECK(cond) if ((cond) < 0) { perror(#cond); abort(); }
#define CHECK_EQ(cond, v) if ((cond) != v) { fprintf(stderr, #cond " failed"); abort(); }

struct shmem_data {
    uint32_t num_edges;
    uint8_t edges[];
};

extern char **environ;

unsigned long current_millis()
{
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return tv.tv_sec * 1000 + tv.tv_usec / 1000;
}

// File descriptors for communication with the child process
int crfd, cwfd, drfd, dwfd;

char script[] = "print(typeof(v));"
                "v = 42;"
                "print(v);";
                //"crash(0);";

int spawn(char** argv)
{
    // Setup forkserver and spawn child
    int crpipe[2];          // control channel child -> fuzzer
    int cwpipe[2];          // control channel fuzzer -> child
    int drpipe[2];          // data channel child -> fuzzer
    int dwpipe[2];          // data channel fuzzer -> child

    if (pipe(crpipe) != 0 || pipe(cwpipe) != 0) {
        fprintf(stderr, "[REPRL] Failed to create pipe\n");
        _exit(-1);
    }

    if (pipe(drpipe) != 0 || pipe(dwpipe) != 0) {
        fprintf(stderr, "[REPRL] Failed to create pipe\n");
        _exit(-1);
    }

    crfd = crpipe[0];
    cwfd = cwpipe[1];
    drfd = drpipe[0];
    dwfd = dwpipe[1];

    int pid = fork();
    if (pid == 0) {
        close(cwpipe[1]);
        close(crpipe[0]);
        close(dwpipe[1]);
        close(drpipe[0]);

        dup2(cwpipe[0], CRFD);
        dup2(crpipe[1], CWFD);
        dup2(dwpipe[0], DRFD);
        dup2(drpipe[1], DWFD);
        close(cwpipe[0]);
        close(crpipe[1]);
        close(dwpipe[0]);
        close(drpipe[1]);

        execve(argv[1], &argv[1], environ);
        fprintf(stderr, "Failed to spawn server");
        _exit(-1);
    }

    close(crpipe[1]);
    close(cwpipe[0]);
    close(drpipe[1]);
    close(dwpipe[0]);

    int helo;
    CHECK_EQ(read(crfd, &helo, 4), 4);
    CHECK_EQ(write(cwfd, &helo, 4), 4);

    return pid;
}

int main(int argc, char** argv)
{
    if (argc < 2) {
        printf("Usage: %s path/to/program [args]\n", argv[0]);
        return 0;
    }

    char shm_key[1024];
    snprintf(shm_key, 1024, "shm_id_%d", getpid());
    setenv("SHM_ID", shm_key, 1);

    // Create shared memory region
    int fd = shm_open(shm_key, O_RDWR | O_CREAT, S_IREAD | S_IWRITE);
    if (fd <= -1) {
        perror("shm_open");
        return -1;
    }
    ftruncate(fd, SHM_SIZE);
    struct shmem_data* shmem = mmap(0, SHM_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    close(fd);

    int pid = spawn(argv);

    while (1) {
        printf("What to do? ");
        int c = getchar();
        if (c == EOF)
            return 0;

        if (c == 'r') {
            char* script_ptr = script;
            size_t script_length = strlen(script);

            write(cwfd, "exec", 4);
            write(cwfd, &script_length, 8);

            int64_t remaining = script_length;
            while (remaining > 0) {
                ssize_t rv = write(dwfd, script_ptr, remaining);
                if (rv <= 0) {
                    fprintf(stderr, "[REPRL] Failed to send script to child process");
                    _exit(-1);
                }
                remaining -= rv;
                script_ptr += rv;
            }

            int needs_restart = 0;
            unsigned long start = current_millis();

            int status = -1;
            ssize_t rv = read(crfd, &status, 4);
            if (rv != 4) {
                waitpid(pid, &status, 0);
                needs_restart = 1;
            }

            unsigned long end = current_millis();

            if (WIFSIGNALED(status)) {
                printf("Died from signal %d\n", WTERMSIG(status));
            } else if (WIFEXITED(status)) {
                printf("Exited normally, status: %d\n", WEXITSTATUS(status));
            }
            printf("Execution took %lums\n", end - start);

            if (needs_restart) {
                close(crfd);
                close(cwfd);
                close(drfd);
                close(dwfd);
                pid = spawn(argv);
            }

            fflush(0);
        } else if (c == 'q') {
            puts("Bye");
            break;
        }
    }

    printf("Have %u edges\n", shmem->num_edges);

    for (uint32_t i = 0; i < shmem->num_edges / 8; i++)
        printf("%x", shmem->edges[i]);
    puts("");

    shm_unlink(shm_key);

    return 0;
}

