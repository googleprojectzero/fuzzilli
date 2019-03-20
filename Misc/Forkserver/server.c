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
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>

#define FD 137

// This functions only ever returns in child processes.
void forkserver()
{
    int rfd = FD;
    int wfd = FD + 1;

    char helo[] = "HELO";
    if (write(wfd, helo, 4) != 4 ||
        read(rfd, helo, 4) != 4) {
        fprintf(stderr, "Failed to communicate with parent\n");
    }

    if (memcmp(helo, "HELO", 4) != 0) {
        fprintf(stderr, "Invalid response from parent\n");
        _exit(-1);
    }

    while (1) {
        char buf[4];
        ssize_t n = read(rfd, &buf, 4);
        if (n == 0)
            exit(0);

        if (n < 0) {
            fprintf(stderr, "Failed to communicate with parent\n");
            _exit(-1);
        }

        int pid = fork();
        if (pid == 0) {
            close(FD);
            close(FD + 1);
            return;
        } else if (pid < 0) {
            fprintf(stderr, "Failed to fork\n");
            _exit(-1);
        }

        write(wfd, &pid, 4);

        int status;
        waitpid(pid, &status, 0);

        write(wfd, &status, 4);
    }
}

int main(int argc, char** argv)
{
    forkserver();

    puts("Hello World!");

    return 0;
}
