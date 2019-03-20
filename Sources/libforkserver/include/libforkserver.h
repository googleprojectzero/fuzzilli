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

#ifndef __LIBFORKSERVER_H__
#define __LIBFORKSERVER_H__

#include <sys/types.h>

struct forkserver {
    // Pipe file descriptor to receive messages from the forkserver.
    int rfd;
    
    // Pipe file descriptor to send messages to the forkserver.
    int wfd;
    
    // Pipe file descriptor to receive program output.
    int outfd;
};

struct forkserver_spawn_result {
    int status;
    int pid;
    unsigned long exec_time;
    char* output;
    size_t output_size;
};

// Start a new forkserver instance.
struct forkserver spinup_forkserver(char** argv);

// Fork a process, wait for its completion, and return the result.
struct forkserver_spawn_result forkserver_spawn(int rfd, int wfd, int outfd, int timeout);

#endif
