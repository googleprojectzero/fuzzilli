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


#include "libreprl.h"

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#if !defined(_WIN32)
#include <poll.h>
#endif
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#if !defined(_WIN32)
#include <sys/mman.h>
#include <sys/time.h>
#endif
#include <sys/types.h>
#if !defined(_WIN32)
#include <sys/wait.h>
#endif
#include <time.h>
#if defined(__unix__)
#include <unistd.h>
#endif

#if defined(_WIN32)
#define NOMINMAX
#include <Windows.h>
#endif

#if !defined(_WIN32)
// Well-known file descriptor numbers for reprl <-> child communication, child
// process side
//
// On Windows, we transact only in HANDLEs rather than file descriptors, so
// these values are never used.  This also avoids the need for FD_CLOEXEC as
// handles are implicitly closed at process termination.
#define REPRL_CHILD_CTRL_IN 100
#define REPRL_CHILD_CTRL_OUT 101
#define REPRL_CHILD_DATA_IN 102
#define REPRL_CHILD_DATA_OUT 103
#endif

#define MIN(x, y) ((x) < (y) ? (x) : (y))

static uint64_t current_usecs()
{
#if defined(_WIN32)
    ULONGLONG ullUnbiasedTime;
    QueryUnbiasedInterruptTime(&ullUnbiasedTime);
    return ullUnbiasedTime / 10;
#else
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000000 + ts.tv_nsec / 1000;
#endif
}

static char** copy_string_array(const char** orig)
{
    size_t num_entries = 0;
    for (const char** current = orig; *current; current++) {
        num_entries += 1;
    }
    char** copy = calloc(num_entries + 1, sizeof(char*));
    for (size_t i = 0; i < num_entries; i++) {
#if defined(_WIN32)
        copy[i] = _strdup(orig[i]);
#else
        copy[i] = strdup(orig[i]);
#endif
    }
    return copy;
}

static void free_string_array(char** arr)
{
    if (!arr) return;
    for (char** current = arr; *current; current++) {
        free(*current);
    }
    free(arr);
}

// A unidirectional communication channel for larger amounts of data, up to a maximum size (REPRL_MAX_DATA_SIZE).
// Implemented as a (RAM-backed) file for which the file descriptor is shared with the child process and which is mapped into our address space.
struct data_channel {
    // File descriptor of the underlying file. Directly shared with the child process.
#if defined(_WIN32)
    HANDLE hFile;
#else
    int fd;
#endif
    // Memory mapping of the file, always of size REPRL_MAX_DATA_SIZE.
    char* mapping;
};

#if defined(_WIN32)
typedef DWORD ProcessID;
#else
typedef pid_t ProcessID;
#endif

struct reprl_context {
    // Whether reprl_initialize has been successfully performed on this context.
    int initialized;

#if defined(_WIN32)
    HANDLE hControlRead;
    HANDLE hControlWrite;
#else
    // Read file descriptor of the control pipe. Only valid if a child process is running (i.e. pid is nonzero).
    int ctrl_in;
    // Write file descriptor of the control pipe. Only valid if a child process is running (i.e. pid is nonzero).
    int ctrl_out;
#endif

    // Data channel REPRL -> Child
    struct data_channel* data_in;
    // Data channel Child -> REPRL
    struct data_channel* data_out;
    
    // Optional data channel for the child's stdout and stderr.
    struct data_channel* child_stdout;
    struct data_channel* child_stderr;
    
    // PID of the child process. Will be zero if no child process is currently running.
#if defined(_WIN32)
    HANDLE hChild;
#else
    ProcessID pid;
#endif
    
    // Arguments and environment for the child process.
    char** argv;
    char** envp;
    
    // A malloc'd string containing a description of the last error that occurred.
    char* last_error;
};

#if defined(_WIN32)
static int vasprintf(char **strp, const char *fmt, va_list ap) {
    va_list argp;
    va_copy(argp, ap);

    int len = _vscprintf(fmt, ap);
    if (len < 0) {
        va_end(argp);
        return -1;
    }

    *strp = malloc(len + 1);
    if (!*strp) {
        va_end(argp);
        return -1;
    }

    len = vsprintf_s(*strp, len + 1, fmt, argp);
    va_end(argp);
    return len;
}
#endif

static int reprl_error(struct reprl_context* ctx, const char *format, ...)
{
    va_list args;
    va_start(args, format);
    free(ctx->last_error);
    vasprintf(&ctx->last_error, format, args);
    return -1;
}

static struct data_channel* reprl_create_data_channel(struct reprl_context* ctx)
{
#if defined(_WIN32)
    SECURITY_ATTRIBUTES sa = { sizeof(sa), NULL, TRUE };
    HANDLE hFile = CreateFileMappingW(INVALID_HANDLE_VALUE, &sa, PAGE_READWRITE, 0, REPRL_MAX_DATA_SIZE, NULL);
    if (hFile == INVALID_HANDLE_VALUE)
        return NULL;

    LPVOID mapping = MapViewOfFile(hFile, FILE_MAP_ALL_ACCESS, 0, 0, REPRL_MAX_DATA_SIZE);
    if (mapping == NULL) {
        CloseHandle(hFile);
        return NULL;
    }

    struct data_channel *channel = malloc(sizeof(struct data_channel));
    channel->hFile = hFile;
    channel->mapping = mapping;
    return channel;
#else
#ifdef __linux__
    int fd = memfd_create("REPRL_DATA_CHANNEL", MFD_CLOEXEC);
#else
    char path[] = "/tmp/reprl_data_channel_XXXXXXXX";
    if (mktemp(path) < 0) {
        reprl_error(ctx, "Failed to create temporary filename for data channel: %s", strerror(errno));
        return NULL;
    }
    int fd = open(path, O_RDWR | O_CREAT| O_CLOEXEC);
    unlink(path);
#endif
    if (fd == -1 || ftruncate(fd, REPRL_MAX_DATA_SIZE) != 0) {
        reprl_error(ctx, "Failed to create data channel file: %s", strerror(errno));
        return NULL;
    }
    char* mapping = mmap(0, REPRL_MAX_DATA_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (mapping == MAP_FAILED) {
        reprl_error(ctx, "Failed to mmap data channel file: %s", strerror(errno));
        return NULL;
    }
    
    struct data_channel* channel = malloc(sizeof(struct data_channel));
    channel->fd = fd;
    channel->mapping = mapping;
    return channel;
#endif
}

static void reprl_destroy_data_channel(struct data_channel* channel)
{
    if (!channel) return;
#if defined(_WIN32)
    UnmapViewOfFile(channel->mapping);
    CloseHandle(channel->hFile);
#else
    close(channel->fd);
    munmap(channel->mapping, REPRL_MAX_DATA_SIZE);
#endif
    free(channel);
}

static void reprl_child_terminated(struct reprl_context* ctx)
{
#if defined(_WIN32)
    if (ctx->hChild == INVALID_HANDLE_VALUE)
        return;
    ctx->hChild = INVALID_HANDLE_VALUE;
    CloseHandle(ctx->hControlRead);
    CloseHandle(ctx->hControlWrite);
#else
    if (!ctx->pid) return;
    ctx->pid = 0;
    close(ctx->ctrl_in);
    close(ctx->ctrl_out);
#endif
}

static void reprl_terminate_child(struct reprl_context* ctx)
{
#if defined(_WIN32)
    if (ctx->hChild == INVALID_HANDLE_VALUE)
        return;
    (void)TerminateProcess(ctx->hChild, -9);
    (void)WaitForSingleObject(ctx->hChild, INFINITE);
    CloseHandle(ctx->hChild);
#else
    if (!ctx->pid) return;
    int status;
    kill(ctx->pid, SIGKILL);
    waitpid(ctx->pid, &status, 0);
#endif
    reprl_child_terminated(ctx);
}

static int reprl_spawn_child(struct reprl_context* ctx)
{
#if defined(_WIN32)
    HANDLE hFiles[4] = {
        ctx->data_in->hFile,
        ctx->data_out->hFile,
        ctx->child_stdout ? ctx->child_stdout->hFile : INVALID_HANDLE_VALUE,
        ctx->child_stderr ? ctx->child_stderr->hFile : INVALID_HANDLE_VALUE,
    };

    for (int index = 0; index < (sizeof(hFiles) / sizeof(*hFiles)); ++index) {
        if (hFiles[index] == INVALID_HANDLE_VALUE)
            continue;
        assert(REPRL_MAX_DATA_SIZE <= INT32_MAX && "need to adjust SetFilePointer invocation");
        SetFilePointer(hFiles[index], REPRL_MAX_DATA_SIZE, NULL, FILE_BEGIN);
        SetEndOfFile(hFiles[index]);
    }

    SECURITY_ATTRIBUTES sa = {sizeof(sa), NULL, TRUE};

    enum { PI_READ, PI_WRITE, PI_PIPES };

    HANDLE output[PI_PIPES] = {INVALID_HANDLE_VALUE,INVALID_HANDLE_VALUE}; // control pipe child -> reprl
    if (CreatePipe(&output[PI_READ], &output[PI_WRITE], &sa, 0))
        return reprl_error(ctx, "Could not create pipe for REPRL communication: %d", GetLastError());
    (void)SetHandleInformation(output[PI_READ], HANDLE_FLAG_INHERIT, 0);

    HANDLE input[PI_PIPES] = {INVALID_HANDLE_VALUE,INVALID_HANDLE_VALUE}; // control pipe reprl -> child
    if (CreatePipe(&input[PI_READ], &input[PI_WRITE], &sa, 0)) {
        CloseHandle(output[PI_READ]);
        CloseHandle(output[PI_WRITE]);
        return reprl_error(ctx, "Could not create pipe for REPRL communication: %d", GetLastError());
    }
    (void)SetHandleInformation(input[PI_WRITE], HANDLE_FLAG_INHERIT, 0);

    ctx->hControlRead = output[PI_READ];
    ctx->hControlWrite = input[PI_WRITE];

    PROCESS_INFORMATION pi;
    ZeroMemory(&pi, sizeof(pi));

    STARTUPINFO si;
    ZeroMemory(&si, sizeof(si));
    si.cb = sizeof(si);
    si.hStdError = ctx->child_stderr ? ctx->child_stderr->hFile : INVALID_HANDLE_VALUE;
    si.hStdOutput = output[PI_WRITE];
    si.hStdInput = input[PI_READ];
    si.dwFlags = STARTF_USESTDHANDLES;

    // Build a commandline from argv.
    // TODO(compnerd) fix quoting for the command line.
    size_t length = 0;
    for (char **arg = ctx->argv; *arg; ++arg)
        length += 1 + strlen(*arg);
    char *commandline = calloc(length + 1, sizeof(char));
    if (!commandline)
        return reprl_error(ctx, "unable to allocate memory");
    for (char *pointer = commandline, **arg = ctx->argv; *arg; ++arg) {
        size_t len = strlen(*arg);
        strncpy_s(pointer, commandline - pointer + 1, *arg, len);
        pointer += len;
        *pointer++ = ' ';
    }

    // FIXME(compnerd) this can be problemtic if the process or command line
    // arguments contains non-ASCII characters.
    if (!CreateProcessA(NULL, commandline, NULL, NULL, TRUE, 0, ctx->envp, NULL, &si, &pi))
        fprintf(stderr, "Failed to execute child process %s: %lu\n", ctx->argv[0], GetLastError());

    free(commandline);

    CloseHandle(output[PI_WRITE]);
    CloseHandle(input[PI_READ]);

    // We require the following services:
    // PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_TERMINATE | SYNCHRONIZE
    ctx->hChild = pi.hProcess;

    DWORD dwResult;
    char buffer[5] = {0};
    if (!ReadFile(ctx->hControlRead, buffer, 4, &dwResult, NULL) || dwResult != 4) {
        reprl_terminate_child(ctx);
        return reprl_error(ctx, "Did not receive HELO message from child: %lu", GetLastError());
    }
    if (strncmp(buffer, "HELO", 4)) {
        reprl_terminate_child(ctx);
        return reprl_error(ctx, "Received invalid HELO message from child: %s", buffer);
    }
    if (!WriteFile(ctx->hControlWrite, buffer, 4, &dwResult, NULL) || dwResult != 4) {
        reprl_terminate_child(ctx);
        return reprl_error(ctx, "Faile dto send HELO reply message to child: %lu", GetLastError());
    }

    return 0;
#else
    // This is also a good time to ensure the data channel backing files don't grow too large.
    ftruncate(ctx->data_in->fd, REPRL_MAX_DATA_SIZE);
    ftruncate(ctx->data_out->fd, REPRL_MAX_DATA_SIZE);
    if (ctx->child_stdout) ftruncate(ctx->child_stdout->fd, REPRL_MAX_DATA_SIZE);
    if (ctx->child_stderr) ftruncate(ctx->child_stderr->fd, REPRL_MAX_DATA_SIZE);
    
    int crpipe[2] = { 0, 0 };          // control pipe child -> reprl
    int cwpipe[2] = { 0, 0 };          // control pipe reprl -> child

    if (pipe(crpipe) != 0) {
        return reprl_error(ctx, "Could not create pipe for REPRL communication: %s", strerror(errno));
    }
    if (pipe(cwpipe) != 0) {
        close(crpipe[0]);
        close(crpipe[1]);
        return reprl_error(ctx, "Could not create pipe for REPRL communication: %s", strerror(errno));
    }

    ctx->ctrl_in = crpipe[0];
    ctx->ctrl_out = cwpipe[1];
    fcntl(ctx->ctrl_in, F_SETFD, FD_CLOEXEC);
    fcntl(ctx->ctrl_out, F_SETFD, FD_CLOEXEC);

#ifdef __linux__
    // Use vfork() on Linux as that considerably improves the fuzzer performance. See also https://github.com/googleprojectzero/fuzzilli/issues/174
    // Due to vfork, the code executed in the child process *must not* modify any memory apart from its stack, as it will share the page table of its parent.
    ProcessID pid = vfork();
#else
    ProcessID pid = fork();
#endif
    if (pid == 0) {
        if (dup2(cwpipe[0], REPRL_CHILD_CTRL_IN) < 0 ||
            dup2(crpipe[1], REPRL_CHILD_CTRL_OUT) < 0 ||
            dup2(ctx->data_out->fd, REPRL_CHILD_DATA_IN) < 0 ||
            dup2(ctx->data_in->fd, REPRL_CHILD_DATA_OUT) < 0) {
            fprintf(stderr, "dup2 failed in the child: %s\n", strerror(errno));
            _exit(-1);
        }

        // Unblock any blocked signals. It seems that libdispatch sometimes blocks delivery of certain signals.
        sigset_t newset;
        sigemptyset(&newset);
        if (sigprocmask(SIG_SETMASK, &newset, NULL) != 0) {
            fprintf(stderr, "sigprocmask failed in the child: %s\n", strerror(errno));
            _exit(-1);
        }

        close(cwpipe[0]);
        close(crpipe[1]);

        int devnull = open("/dev/null", O_RDWR);
        dup2(devnull, 0);
        if (ctx->child_stdout) dup2(ctx->child_stdout->fd, 1);
        else dup2(devnull, 1);
        if (ctx->child_stderr) dup2(ctx->child_stderr->fd, 2);
        else dup2(devnull, 2);
        close(devnull);
        
        // close all other FDs. We try to use FD_CLOEXEC everywhere, but let's be extra sure we don't leak any fds to the child.
        int tablesize = getdtablesize();
        for (int i = 3; i < tablesize; i++) {
            if (i == REPRL_CHILD_CTRL_IN || i == REPRL_CHILD_CTRL_OUT || i == REPRL_CHILD_DATA_IN || i == REPRL_CHILD_DATA_OUT) {
                continue;
            }
            close(i);
        }

        execve(ctx->argv[0], ctx->argv, ctx->envp);
        
        fprintf(stderr, "Failed to execute child process %s: %s\n", ctx->argv[0], strerror(errno));
        fflush(stderr);
        _exit(-1);
    }
    
    close(crpipe[1]);
    close(cwpipe[0]);
    
    if (pid < 0) {
        close(ctx->ctrl_in);
        close(ctx->ctrl_out);
        return reprl_error(ctx, "Failed to fork: %s", strerror(errno));
    }
    ctx->pid = pid;

    char helo[5] = { 0 };
    if (read(ctx->ctrl_in, helo, 4) != 4) {
        reprl_terminate_child(ctx);
        return reprl_error(ctx, "Did not receive HELO message from child: %s", strerror(errno));
    }
    
    if (strncmp(helo, "HELO", 4) != 0) {
        reprl_terminate_child(ctx);
        return reprl_error(ctx, "Received invalid HELO message from child: %s", helo);
    }
    
    if (write(ctx->ctrl_out, helo, 4) != 4) {
        reprl_terminate_child(ctx);
        return reprl_error(ctx, "Failed to send HELO reply message to child: %s", strerror(errno));
    }

    return 0;
#endif
}

struct reprl_context* reprl_create_context()
{
#if !defined(_WIN32)
    // "Reserve" the well-known REPRL fds so no other fd collides with them.
    // This would cause various kinds of issues in reprl_spawn_child.
    // It would be enough to do this once per process in the case of multiple
    // REPRL instances, but it's probably not worth the implementation effort.
    int devnull = open("/dev/null", O_RDWR);
    dup2(devnull, REPRL_CHILD_CTRL_IN);
    dup2(devnull, REPRL_CHILD_CTRL_OUT);
    dup2(devnull, REPRL_CHILD_DATA_IN);
    dup2(devnull, REPRL_CHILD_DATA_OUT);
    close(devnull);
#endif

    return calloc(1, sizeof(struct reprl_context));
}
                    
int reprl_initialize_context(struct reprl_context* ctx, const char** argv, const char** envp, int capture_stdout, int capture_stderr)
{
    if (ctx->initialized) {
        return reprl_error(ctx, "Context is already initialized");
    }
    
#if !defined(_WIN32)
    // We need to ignore SIGPIPE since we could end up writing to a pipe after our child process has exited.
    signal(SIGPIPE, SIG_IGN);
#endif

    ctx->argv = copy_string_array(argv);
    ctx->envp = copy_string_array(envp);
    
    ctx->data_in = reprl_create_data_channel(ctx);
    ctx->data_out = reprl_create_data_channel(ctx);
    if (capture_stdout) {
        ctx->child_stdout = reprl_create_data_channel(ctx);
    }
    if (capture_stderr) {
        ctx->child_stderr = reprl_create_data_channel(ctx);
    }
    if (!ctx->data_in || !ctx->data_out || (capture_stdout && !ctx->child_stdout) || (capture_stderr && !ctx->child_stderr)) {
        // Proper error message will have been set by reprl_create_data_channel
        return -1;
    }
    
    ctx->initialized = 1;
    return 0;
}

void reprl_destroy_context(struct reprl_context* ctx)
{
    reprl_terminate_child(ctx);
    
    free_string_array(ctx->argv);
    free_string_array(ctx->envp);
    
    reprl_destroy_data_channel(ctx->data_in);
    reprl_destroy_data_channel(ctx->data_out);
    reprl_destroy_data_channel(ctx->child_stdout);
    reprl_destroy_data_channel(ctx->child_stderr);
    
    free(ctx->last_error);
    free(ctx);
}

int reprl_execute(struct reprl_context* ctx, const char* script, uint64_t script_length, uint64_t timeout, uint64_t* execution_time, int fresh_instance)
{
    if (!ctx->initialized) {
        return reprl_error(ctx, "REPRL context is not initialized");
    }
    if (script_length > REPRL_MAX_DATA_SIZE) {
        return reprl_error(ctx, "Script too large");
    }

#if defined(_WIN32)
    if (fresh_instance && ctx->hChild != INVALID_HANDLE_VALUE)
        reprl_terminate_child(ctx);

    SetFilePointer(ctx->data_out->hFile, 0, 0, FILE_BEGIN);
    SetFilePointer(ctx->data_in->hFile, 0, 0, FILE_BEGIN);
    if (ctx->child_stdout)
        SetFilePointer(ctx->child_stdout->hFile, 0, 0, FILE_BEGIN);
    if (ctx->child_stderr)
        SetFilePointer(ctx->child_stderr->hFile, 0, 0, FILE_BEGIN);

    if (ctx->hChild == INVALID_HANDLE_VALUE) {
        int r = reprl_spawn_child(ctx);
        if (r)
            return r;
    }
#else
    // Terminate any existing instance if requested.
    if (fresh_instance && ctx->pid) {
        reprl_terminate_child(ctx);
    }

    // Reset file position so the child can simply read(2) and write(2) to these fds.
    lseek(ctx->data_out->fd, 0, SEEK_SET);
    lseek(ctx->data_in->fd, 0, SEEK_SET);
    if (ctx->child_stdout) {
        lseek(ctx->child_stdout->fd, 0, SEEK_SET);
    }
    if (ctx->child_stderr) {
        lseek(ctx->child_stderr->fd, 0, SEEK_SET);
    }
    
    // Spawn a new instance if necessary.
    if (!ctx->pid) {
        int r = reprl_spawn_child(ctx);
        if (r != 0) return r;
    }
#endif

    // Copy the script to the data channel.
    memcpy(ctx->data_out->mapping, script, script_length);

    // Tell child to execute the script.
#if defined(_WIN32)
    DWORD dwBytesWritten;
    if (!WriteFile(ctx->hControlWrite, "exec", 4, &dwBytesWritten, NULL) || dwBytesWritten != 4) {
        DWORD dwExitCode;
        if (GetExitCodeProcess(ctx->hChild, &dwExitCode) != STILL_ACTIVE) {
            reprl_child_terminated(ctx);
            return reprl_error(ctx, "Child unexpected terminated with status %u between executions", dwExitCode);
        }
        return reprl_error(ctx, "Failed to send command to child process: %d", GetLastError());
    }
    if (!WriteFile(ctx->hControlWrite, &script_length, sizeof(script_length), &dwBytesWritten, NULL) || dwBytesWritten != sizeof(script_length)) {
        DWORD dwExitCode;
        if (GetExitCodeProcess(ctx->hChild, &dwExitCode) != STILL_ACTIVE) {
            reprl_child_terminated(ctx);
            return reprl_error(ctx, "Child unexpected terminated with status %u between executions", dwExitCode);
        }
        return reprl_error(ctx, "Failed to send command to child process: %d", GetLastError());
    }

    switch (WaitForSingleObject(ctx->hChild, timeout / 1000)) {
    case WAIT_TIMEOUT:
        reprl_terminate_child(ctx);
        return 1 << 16;
    case WAIT_OBJECT_0:
        break;
    default:
        return reprl_error(ctx, "WaitForSingleObject error: %d", GetLastError());
    }

    int status;
    DWORD dwBytesRead;
    if (!ReadFile(ctx->hControlRead, &status, sizeof(status), &dwBytesRead, NULL))
        return reprl_error(ctx, "unable to read from control pipe: %d", GetLastError());
    if (dwBytesRead == sizeof(status))
        return status & 0xffff;
    DWORD dwExitCode;
    BOOL bSuccess;
    bSuccess = GetExitCodeProcess(ctx->hChild, &dwExitCode);

    reprl_terminate_child(ctx);
    if (bSuccess)
        return status & 0xffff;
    return reprl_error(ctx, "child in weird state after execution");
#else
    if (write(ctx->ctrl_out, "exec", 4) != 4 ||
        write(ctx->ctrl_out, &script_length, 8) != 8) {
        // These can fail if the child unexpectedly terminated between executions.
        // Check for that here to be able to provide a better error message.
        int status;
        if (waitpid(ctx->pid, &status, WNOHANG) == ctx->pid) {
            reprl_child_terminated(ctx);
            if (WIFEXITED(status)) {
                return reprl_error(ctx, "Child unexpectedly exited with status %i between executions", WEXITSTATUS(status));
            } else {
                return reprl_error(ctx, "Child unexpectedly terminated with signal %i between executions", WTERMSIG(status));
            }
        }
        return reprl_error(ctx, "Failed to send command to child process: %s", strerror(errno));
    }

    // Wait for child to finish execution (or crash).
    int timeout_ms = timeout / 1000;
    uint64_t start_time = current_usecs();
    struct pollfd fds = {.fd = ctx->ctrl_in, .events = POLLIN, .revents = 0};
    int res = poll(&fds, 1, timeout_ms);
    *execution_time = current_usecs() - start_time;
    if (res == 0) {
        // Execution timed out. Kill child and return a timeout status.
        reprl_terminate_child(ctx);
        return 1 << 16;
    } else if (res != 1) {
        // An error occurred.
        // We expect all signal handlers to be installed with SA_RESTART, so receiving EINTR here is unexpected and thus also an error.
        return reprl_error(ctx, "Failed to poll: %s", strerror(errno));
    }
    
    // Poll succeeded, so there must be something to read now (either the status or EOF).
    int status;
    ssize_t rv = read(ctx->ctrl_in, &status, 4);
    if (rv < 0) {
        return reprl_error(ctx, "Failed to read from control pipe: %s", strerror(errno));
    } else if (rv != 4) {
        // Most likely, the child process crashed and closed the write end of the control pipe.
        // Unfortunately, there probably is nothing that guarantees that waitpid() will immediately succeed now,
        // and we also don't want to block here. So just retry waitpid() a few times...
        int success = 0;
        do {
            success = waitpid(ctx->pid, &status, WNOHANG) == ctx->pid;
            if (!success) usleep(10);
        } while (!success && current_usecs() - start_time < timeout);
        
        if (!success) {
            // Wait failed, so something weird must have happened. Maybe somehow the control pipe was closed without the child exiting?
            // Probably the best we can do is kill the child and return an error.
            reprl_terminate_child(ctx);
            return reprl_error(ctx, "Child in weird state after execution");
        }

        // Cleanup any state related to this child process.
        reprl_child_terminated(ctx);

        if (WIFEXITED(status)) {
            status = WEXITSTATUS(status) << 8;
        } else if (WIFSIGNALED(status)) {
            status = WTERMSIG(status);
        } else {
            // This shouldn't happen, since we don't specify WUNTRACED for waitpid...
            return reprl_error(ctx, "Waitpid returned unexpected child state %i", status);
        }
    }
    
    // The status must be a positive number, see the status encoding format below.
    // We also don't allow the child process to indicate a timeout. If we wanted,
    // we could treat it as an error if the upper bits are set.
    status &= 0xffff;

    return status;
#endif
}

/// The 32bit REPRL exit status as returned by reprl_execute has the following format:
///     [ 00000000 | did_timeout | exit_code | terminating_signal ]
/// Only one of did_timeout, exit_code, or terminating_signal may be set at one time.
int RIFSIGNALED(int status)
{
    return (status & 0xff) != 0;
}

int RIFEXITED(int status)
{
    return !RIFSIGNALED(status) && !RIFTIMEDOUT(status);
}

int RIFTIMEDOUT(int status)
{
    return (status & 0xff0000) != 0;
}

int RTERMSIG(int status)
{
    return status & 0xff;
}

int REXITSTATUS(int status)
{
    return (status >> 8) & 0xff;
}

static const char* fetch_data_channel_content(struct data_channel* channel)
{
    if (!channel) return "";
#if defined(_WIN32)
    DWORD pos = SetFilePointer(channel->hFile, 0, 0, FILE_CURRENT);
#else
    size_t pos = lseek(channel->fd, 0, SEEK_CUR);
#endif
    pos = MIN(pos, REPRL_MAX_DATA_SIZE - 1);
    channel->mapping[pos] = 0;
    return channel->mapping;
}

const char* reprl_fetch_fuzzout(struct reprl_context* ctx)
{
    return fetch_data_channel_content(ctx->data_in);
}

const char* reprl_fetch_stdout(struct reprl_context* ctx)
{
    return fetch_data_channel_content(ctx->child_stdout);
}

const char* reprl_fetch_stderr(struct reprl_context* ctx)
{
    return fetch_data_channel_content(ctx->child_stderr);
}

const char* reprl_get_last_error(struct reprl_context* ctx)
{
    return ctx->last_error;
}

