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

#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/time.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

#include "libforkserver.h"

// 1337 might be too high if a file handle ulimit is set...
#define FD 137

#define CHECK_SUCCESS(cond) if((cond) < 0) { perror(#cond); abort(); }
#define CHECK(cond) if(!(cond)) { fprintf(stderr, "(" #cond ") failed!"); abort(); }

extern char** environ;

static uint64_t current_millis()
{
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    return ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

struct forkserver spinup_forkserver(char** argv)
{
    struct forkserver server;
    
    // We need to make sure that our fds don't end up being 137 - 139
    if (fcntl(FD, F_GETFD) == -1) {
        int devnull = open("/dev/null", O_RDWR);
        dup2(devnull, FD);
        dup2(devnull, FD + 1);
        dup2(devnull, FD + 2);
        close(devnull);
    }
    
    int rpipe[2];           // forkserver communication forkserver -> fuzzer
    int wpipe[2];           // forkserver communication fuzzer -> forkserver
    int outpipe[2];         // output channel fuzzee -> fuzzer

    if (pipe(wpipe) != 0 || pipe(rpipe) != 0) {
        fprintf(stderr, "[Forkserver] Failed to create pipe\n");
        _exit(-1);
    }

    if (pipe(outpipe) != 0) {
        fprintf(stderr, "[Forkserver] Failed to create pipe\n");
        _exit(-1);
    }

    server.rfd = rpipe[0];
    server.wfd = wpipe[1];
    server.outfd = outpipe[0];

    int flags;
    flags = fcntl(server.outfd, F_GETFL, 0);
    fcntl(server.outfd, F_SETFL, flags | O_NONBLOCK);

    int pid = fork();
    if (pid == 0) {
        close(wpipe[1]);
        close(rpipe[0]);
        close(outpipe[0]);

        dup2(wpipe[0], FD);
        dup2(rpipe[1], FD + 1);
        dup2(outpipe[1], FD + 2);
        close(wpipe[0]);
        close(rpipe[1]);
        close(outpipe[1]);
        
        int devnull = open("/dev/null", O_RDWR);
        dup2(devnull, 0);
        dup2(devnull, 1);
        dup2(devnull, 2);
        close(devnull);

        execve(argv[0], argv, environ);
        fprintf(stderr, "[Forkserver] Failed to spawn child process\n");
        _exit(-1);
    } else if (pid < 0) {
        fprintf(stderr, "[Forkserver] Failed to fork\n");
        _exit(-1);
    }

    close(rpipe[1]);
    close(wpipe[0]);
    close(outpipe[1]);

    int helo;
    if (read(server.rfd, &helo, 4) != 4 || write(server.wfd, &helo, 4) != 4) {
        fprintf(stderr, "[Forkserver] Failed to communicate with child process\n");
        _exit(-1);
    }

    return server;
}

static char* fetch_output(int fd, size_t* outsize)
{
    size_t rv;
    *outsize = 0;
    size_t remaining = 0x1000;
    char* outbuf = malloc(remaining + 1);
    
    do {
        rv = read(fd, outbuf + *outsize, remaining);
        if (rv == -1) {
            if (errno != EAGAIN) {
                fprintf(stderr, "[Forkserver] Error while receiving data: %s\n", strerror(errno));
            }
            break;
        }
        
        *outsize += rv;
        remaining -= rv;
        
        if (remaining == 0) {
            remaining = *outsize;
            outbuf = realloc(outbuf, *outsize * 2 + 1);
            if (!outbuf) {
                fprintf(stderr, "[Forkserver] Could not allocate output buffer");
                _exit(-1);
            }
        }
    } while (rv > 0);
    
    outbuf[*outsize] = 0;

    return outbuf;
}

// Fork a worker process, wait for its completion, and return the result.
struct forkserver_spawn_result forkserver_spawn(int rfd, int wfd, int outfd, int timeout)
{
    uint64_t start_time = current_millis();
    
    pid_t pid;
    write(wfd, "fork", 4);
    read(rfd, &pid, 4);
    
    struct pollfd fds = {.fd = rfd, .events = POLLIN, .revents = 0};
    if (poll(&fds, 1, timeout) == 0)
        kill(pid, SIGKILL);
    
    struct forkserver_spawn_result result;
    read(rfd, &result.status, 4);
    result.output = fetch_output(outfd, &result.output_size);
    
    result.pid = pid;
    result.exec_time = current_millis() - start_time;
    
    return result;
}
