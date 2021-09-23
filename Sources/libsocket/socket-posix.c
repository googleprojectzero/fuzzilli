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

#if !defined(_WIN32)

#include "libsocket.h"

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

socket_t socket_listen(const char* address, uint16_t port) {
    socket_t fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        return INVALID_SOCKET;
    }
    
    int arg = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &arg, sizeof(arg));
    
    int flags = fcntl(fd, F_GETFL, 0);
    if (fcntl(fd, F_SETFD, FD_CLOEXEC) == -1) {
        close(fd);
        return INVALID_SOCKET;
    }
    
    struct sockaddr_in serv_addr;
    memset(&serv_addr, 0, sizeof(serv_addr));
    serv_addr.sin_family = AF_INET;
    serv_addr.sin_addr.s_addr = inet_addr(address);
    serv_addr.sin_port = htons(port);
    
    if (bind(fd, (struct sockaddr*)&serv_addr, sizeof(serv_addr)) < 0) {
        close(fd);
        return INVALID_SOCKET;
    }
    
    listen(fd, 256);
    return fd;
}

socket_t socket_accept(socket_t fd) {
    socket_t client_fd = accept(fd, NULL, 0);
    if (client_fd < 0) {
        return INVALID_SOCKET;
    }
    
#ifdef  __APPLE__
    int arg = 1;
    setsockopt(client_fd, SOL_SOCKET, SO_NOSIGPIPE, &arg, sizeof(arg));
#endif
    
    int flags = fcntl(client_fd, F_GETFL, 0);
    if (fcntl(client_fd, F_SETFL, flags | O_NONBLOCK) == -1) {
        close(client_fd);
        return INVALID_SOCKET;
    }
    if (fcntl(fd, F_SETFD, FD_CLOEXEC) == -1) {
        close(fd);
        return INVALID_SOCKET;
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
        return INVALID_SOCKET;
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
       return INVALID_SOCKET;
    }
    
#ifdef  __APPLE__
    int arg = 1;
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &arg, sizeof(arg));
#endif
    
    int flags = fcntl(fd, F_GETFL, 0);
    if (fcntl(fd, F_SETFL, flags | O_NONBLOCK) == -1) {
        close(fd);
        return INVALID_SOCKET;
    }
    if (fcntl(fd, F_SETFD, FD_CLOEXEC) == -1) {
        close(fd);
        return INVALID_SOCKET;
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
