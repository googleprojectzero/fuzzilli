// Copyright 2021 Google LLC
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

#if defined(_WIN32)

#include "libreprl.h"

#include <assert.h>
#include <stdbool.h>
#include <stdio.h>

#define NOMINMAX
#include <Windows.h>

#define MIN(x, y) ((x) < (y) ? (x) : (y))

static uint64_t current_usecs()
{
    ULONGLONG ullUnbiasedTime;
    QueryUnbiasedInterruptTime(&ullUnbiasedTime);
    return ullUnbiasedTime / 10;
}

static char** copy_string_array(const char** orig)
{
    size_t num_entries = 0;
    for (const char** current = orig; *current; current++) {
        num_entries += 1;
    }
    char** copy = calloc(num_entries + 1, sizeof(char*));
    for (size_t i = 0; i < num_entries; i++) {
        copy[i] = _strdup(orig[i]);
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

// A unidirectional communication channel for larger amounts of data, up to a
// maximum size (REPRL_MAX_DATA_SIZE).
//
// Implemented as a (RAM-backed) file for which the file descriptor is shared
// with the child process and which is mapped into our address space.
struct data_channel {
    // HANDLE of the underlying mapping. Directly shared with the child process.
    HANDLE hFile;
    // Memory mapping of the file, always of size REPRL_MAX_DATA_SIZE.
    char* mapping;
};

struct reprl_context {
    // Whether reprl_initialize has been successfully performed on this context.
    bool initialized;

    HANDLE hControlRead;
    HANDLE hControlWrite;

    // Data channel REPRL -> Child
    struct data_channel* data_in;
    // Data channel Child -> REPRL
    struct data_channel* data_out;

    // Optional data channel for the child's stdout and stderr.
    struct data_channel* child_stdout;
    struct data_channel* child_stderr;

    // PID of the child process. Will be zero if no child process is currently running.
    HANDLE hChild;

    // Arguments and environment for the child process.
    char** argv;
    char** envp;

    // A malloc'd string containing a description of the last error that occurred.
    char* last_error;
};

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
}

static void reprl_destroy_data_channel(struct data_channel* channel)
{
    if (!channel)
        return;
    UnmapViewOfFile(channel->mapping);
    CloseHandle(channel->hFile);
    free(channel);
}

static void reprl_child_terminated(struct reprl_context* ctx)
{
    if (ctx->hChild == INVALID_HANDLE_VALUE)
        return;
    ctx->hChild = INVALID_HANDLE_VALUE;
    CloseHandle(ctx->hControlRead);
    CloseHandle(ctx->hControlWrite);
}

static void reprl_terminate_child(struct reprl_context* ctx)
{
    if (ctx->hChild == INVALID_HANDLE_VALUE)
        return;
    (void)TerminateProcess(ctx->hChild, -9);
    (void)WaitForSingleObject(ctx->hChild, INFINITE);
    CloseHandle(ctx->hChild);
    reprl_child_terminated(ctx);
}

static int reprl_spawn_child(struct reprl_context* ctx)
{
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
}

struct reprl_context* reprl_create_context()
{
    return calloc(1, sizeof(struct reprl_context));
}

int reprl_initialize_context(struct reprl_context* ctx, const char** argv, const char** envp, int capture_stdout, int capture_stderr)
{
    if (ctx->initialized)
        return reprl_error(ctx, "Context is already initialized");

    ctx->argv = copy_string_array(argv);
    ctx->envp = copy_string_array(envp);

    ctx->data_in = reprl_create_data_channel(ctx);
    ctx->data_out = reprl_create_data_channel(ctx);
    if (capture_stdout)
        ctx->child_stdout = reprl_create_data_channel(ctx);
    if (capture_stderr)
        ctx->child_stderr = reprl_create_data_channel(ctx);

    // Proper error message will have been set by reprl_create_data_channel
    if (!ctx->data_in || !ctx->data_out || (capture_stdout && !ctx->child_stdout) || (capture_stderr && !ctx->child_stderr))
        return -1;

    ctx->initialized = true;
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

int reprl_execute(struct reprl_context* ctx, const char* script, uint64_t script_size, uint64_t timeout, uint64_t* execution_time, int fresh_instance)
{
    if (!ctx->initialized)
        return reprl_error(ctx, "REPRL context is not initialized");

    if (script_size > REPRL_MAX_DATA_SIZE)
        return reprl_error(ctx, "Script too large");

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

    // Copy the script to the data channel.
    memcpy(ctx->data_out->mapping, script, script_size);

    // Tell child to execute the script.
    DWORD dwBytesWritten;
    if (!WriteFile(ctx->hControlWrite, "exec", 4, &dwBytesWritten, NULL) || dwBytesWritten != 4) {
        DWORD dwExitCode;
        if (GetExitCodeProcess(ctx->hChild, &dwExitCode) != STILL_ACTIVE) {
            reprl_child_terminated(ctx);
            return reprl_error(ctx, "Child unexpected terminated with status %u between executions", dwExitCode);
        }
        return reprl_error(ctx, "Failed to send command to child process: %d", GetLastError());
    }
    if (!WriteFile(ctx->hControlWrite, &script_size, sizeof(script_size), &dwBytesWritten, NULL) || dwBytesWritten != sizeof(script_size)) {
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
}

static const char* fetch_data_channel_content(struct data_channel* channel)
{
    if (!channel)
        return "";
    DWORD pos = SetFilePointer(channel->hFile, 0, 0, FILE_CURRENT);
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

#endif
