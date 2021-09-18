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

#include "libsocket.h"

#include <stdio.h>
#include <string.h>

#if defined(_WIN32)
#include <assert.h>
#include <WS2tcpip.h>

// WinSock must be initialized prior to any WinSock related call.  Although it
// is possible to control this in the application level, doing this by the
// constructor means that the initialization is guaranteed to be complete by the
// time that `main` is entered.  Because this library is homed inside of
// fuzzilli, which is Swift based and builds via the Swift Package Manager, this
// is guaranteed to build with clang which is able to map the
// `__attribute__((__constructor__))` and `__attribute__((__destructor__))` to
// the appropriate `.XCRT$*` section.  We could make this code more prtable by
// using `#pragma section` which is supported by both clang and MSVC, but it is
// unlikely to be beneficial currently.
static void __attribute__((__constructor__, __used__)) libsocket_init(void) {
    WSADATA wsa;
    if (WSAStartup(MAKEWORD(2, 2), &wsa)) {
        fprintf(stderr, "unable to initialize WinSock2: %d\n", WSAGetLastError());
        _exit(EXIT_FAILURE);
    }
}

static void __attribute__((__destructor__, __used__)) libsocket_fini(void) {
    (void)WSACleanup();
}

socket_t socket_listen(const char *address, uint16_t port) {
    socket_t sock = socket(AF_INET, SOCK_STREAM, 0);
    if (sock == INVALID_SOCKET)
        return INVALID_SOCKET;

    BOOL bOpt = TRUE;
    (void)setsockopt(sock, SOL_SOCKET, SO_REUSEADDR, (char *)&bOpt, sizeof(bOpt));

    struct sockaddr_in addr;
    ZeroMemory(&addr, sizeof(addr));
    addr.sin_family = AF_INET;
    (void)inet_pton(AF_INET, address, &addr.sin_addr);
    addr.sin_port = htons(port);

    if (bind(sock, (struct sockaddr *)&addr, sizeof(addr)) == SOCKET_ERROR) {
        closesocket(sock);
        return INVALID_SOCKET;
    }

    // TODO(compnerd) use a constant for the backlog
    (void)listen(sock, 256);
    return sock;
}

socket_t socket_accept(socket_t sock) {
    socket_t client = accept(sock, NULL, NULL);
    if (client == INVALID_SOCKET)
        return INVALID_SOCKET;

    BOOL bOpt = TRUE;
    if (ioctlsocket(client, FIONBIO, (u_long *)&bOpt) == SOCKET_ERROR) {
        closesocket(client);
        return INVALID_SOCKET;
    }

    return client;
}

socket_t socket_connect(const char *address, uint16_t port) {
    struct addrinfo ai;
    (void)memset(&ai, 0, sizeof(ai));
    ai.ai_family = AF_UNSPEC;
    ai.ai_socktype = SOCK_STREAM;
    ai.ai_protocol = IPPROTO_TCP;

    char port_str[6];
    snprintf(port_str, sizeof(port_str), "%u", port);

    struct addrinfo *ai_list = NULL;
    if (getaddrinfo(address, port_str, &ai, &ai_list))
        return INVALID_SOCKET;

    socket_t sock;
    struct addrinfo *ai_cur;
    for (ai_cur = ai_list; ai_cur; ai_cur = ai_cur->ai_next) {
        sock = socket(ai_cur->ai_family, ai_cur->ai_socktype, ai_cur->ai_protocol);
        if (sock == INVALID_SOCKET)
            continue;

        if (connect(sock, ai_cur->ai_addr, ai_cur->ai_addrlen)) {
            closesocket(sock);
            continue;
        }

        break;
    }

    freeaddrinfo(ai_list);
    if (ai_cur == NULL)
        return INVALID_SOCKET;

    BOOL bOpt = TRUE;
    if (ioctlsocket(sock, FIONBIO, (u_long *)&bOpt) == SOCKET_ERROR) {
        closesocket(sock);
        return INVALID_SOCKET;
    }

    return sock;
}

ssize_t socket_send(socket_t sock, const uint8_t *data, size_t length) {
    assert(length <= INT_MAX && "unable to send > INT_MAX bytes");
    ssize_t remaining = length;
    while (remaining) {
        int rv = send(sock, (const char *)data, remaining, 0);
        if (rv == SOCKET_ERROR)
            return GetLastError() == WSAEWOULDBLOCK ? length - remaining : rv;
        remaining -= rv;
        data += rv;
    }
    return length;
}

ssize_t socket_recv(socket_t sock, uint8_t *buffer, size_t length) {
    assert(length <= INT_MAX && "unable to receive >INT_MAX bytes");
    return recv(sock, (char *)buffer, length, 0);
}

int socket_shutdown(socket_t socket) {
    return shutdown(socket, SD_BOTH);
}

int socket_close(socket_t socket) {
    return closesocket(socket);
}
#else
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <unistd.h>

socket_t socket_listen(const char* address, uint16_t port) {
    socket_t fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        return -1;
    }
    
    int arg = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &arg, sizeof(arg));
    
    int flags = fcntl(fd, F_GETFL, 0);
    if (fcntl(fd, F_SETFD, FD_CLOEXEC) == -1) {
        close(fd);
        return -2;
    }
    
    struct sockaddr_in serv_addr;
    memset(&serv_addr, 0, sizeof(serv_addr));
    serv_addr.sin_family = AF_INET;
    serv_addr.sin_addr.s_addr = inet_addr(address);
    serv_addr.sin_port = htons(port);
    
    if (bind(fd, (struct sockaddr*)&serv_addr, sizeof(serv_addr)) < 0) {
        close(fd);
        return -3;
    }
    
    listen(fd, 256);
    return fd;
}

socket_t socket_accept(socket_t fd) {
    socket_t client_fd = accept(fd, NULL, 0);
    if (client_fd < 0) {
        return -1;
    }
    
#ifdef  __APPLE__
    int arg = 1;
    setsockopt(client_fd, SOL_SOCKET, SO_NOSIGPIPE, &arg, sizeof(arg));
#endif
    
    int flags = fcntl(client_fd, F_GETFL, 0);
    if (fcntl(client_fd, F_SETFL, flags | O_NONBLOCK) == -1) {
        close(client_fd);
        return -2;
    }
    if (fcntl(fd, F_SETFD, FD_CLOEXEC) == -1) {
        close(fd);
        return -3;
    }
    
    return client_fd;
}

socket_t socket_connect(const char* address, uint16_t port) {
    struct addrinfo hint;
    memset(&hint, 0, sizeof(hint));
    hint.ai_family = AF_UNSPEC;
    hint.ai_socktype = SOCK_STREAM;
    hint.ai_protocol = IPPROTO_TCP;
    
    char portbuf[6];
    snprintf(portbuf, sizeof(portbuf), "%d", port);
    
    struct addrinfo* result;
    if (getaddrinfo (address, portbuf, &hint, &result) != 0) {
        return -1;
    }

    socket_t fd;
    struct addrinfo* addr;
    for (addr = result; addr != NULL; addr = addr->ai_next) {
        fd = socket(addr->ai_family, addr->ai_socktype, addr->ai_protocol);
        if (fd < 0) {
            continue;
        }
        
        if (connect(fd, addr->ai_addr, addr->ai_addrlen) != 0) {
            close(fd);
            continue;
        }
        
        break;
    }

    freeaddrinfo(result);

    if (addr == NULL) {
       return -2;
    }
    
#ifdef  __APPLE__
    int arg = 1;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &arg, sizeof(arg));
#endif
    
    int flags = fcntl(fd, F_GETFL, 0);
    if (fcntl(fd, F_SETFL, flags | O_NONBLOCK) == -1) {
        close(fd);
        return -3;
    }
    if (fcntl(fd, F_SETFD, FD_CLOEXEC) == -1) {
        close(fd);
        return -4;
    }

    return fd;
}

ssize_t socket_send(socket_t fd, const uint8_t* data, size_t length) {
    ssize_t remaining = length;
    while (remaining > 0) {
#ifdef __APPLE__
        ssize_t rv = send(fd, data, remaining, 0);
#else
        ssize_t rv = send(fd, data, remaining, MSG_NOSIGNAL);
#endif
        if (rv <= 0) {
            if (errno != EAGAIN && errno != EWOULDBLOCK) {
                return rv;
            } else {
                return length - remaining;
            }
        }
        remaining -= rv;
        data += rv;
    }
    return length;
}

ssize_t socket_recv(socket_t fd, uint8_t* data, size_t length) {
    return read(fd, data, length);
}

int socket_shutdown(socket_t socket) {
    return shutdown(socket, SHUT_RDWR);
}

int socket_close(socket_t fd) {
    return close(fd);
}
#endif
