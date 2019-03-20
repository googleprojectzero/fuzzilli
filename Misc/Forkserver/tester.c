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
#include <unistd.h>
#include <sys/time.h>
#include <sys/mman.h>
#include <sys/stat.h>

#define FD 137
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

    // Setup forkserver and spawn child
    int rpipe[2];
    int wpipe[2];

    CHECK(pipe(wpipe));
    CHECK(pipe(rpipe));

    int rfd = rpipe[0];
    int wfd = wpipe[1];

    int pid = fork();
    if (pid == 0) {
        CHECK(close(rpipe[0]));
        CHECK(close(wpipe[1]));

        CHECK(dup2(wpipe[0], FD));
        CHECK(dup2(rpipe[1], FD + 1));
        CHECK(close(wpipe[0]));
        CHECK(close(rpipe[1]));

        execve(argv[1], &argv[1], environ);
        fprintf(stderr, "Failed to spawn server");
        _exit(-1);
    }

    CHECK(close(rpipe[1]));
    CHECK(close(wpipe[0]));

    int helo;
    CHECK_EQ(read(rfd, &helo, 4), 4);
    CHECK_EQ(write(wfd, &helo, 4), 4);

    while (1) {
        printf("What to do? ");
        int c = getchar();
        if (c == EOF)
            return 0;

        if (c == 'r') {
            write(wfd, "fork", 4);

            int pid = -1;
            read(rfd, &pid, 4);
            printf("Child pid: %d\n", pid);

            unsigned long start = current_millis();

            int status = -1;
            read(rfd, &status, 4);

            unsigned long end = current_millis();

            if (WIFSIGNALED(status)) {
                printf("Died from signal %d\n", WTERMSIG(status));
            } else if (WIFEXITED(status)) {
                printf("Exited normally, status: %d\n", WEXITSTATUS(status));
            }
            printf("Execution took %lums\n", end - start);
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

