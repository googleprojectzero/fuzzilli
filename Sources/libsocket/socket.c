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
#include <arpa/inet.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <unistd.h>
#include <netinet/in.h>
#include <netdb.h>

int socket_listen(const char* address, uint16_t port) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) {
        return -1;
    }
    
    int arg = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &arg, sizeof(arg));
    
    struct sockaddr_in serv_addr;
    memset(&serv_addr, 0, sizeof(serv_addr));
    serv_addr.sin_family = AF_INET;
    serv_addr.sin_addr.s_addr = inet_addr(address);
    serv_addr.sin_port = htons(port);
    
    if (bind(fd, (struct sockaddr*)&serv_addr, sizeof(serv_addr)) < 0) {
        return -2;
    }
    
    listen(fd, 256);
    return fd;
}

int socket_accept(int fd) {
    int client_fd = accept(fd, NULL, 0);
    
#ifdef  __APPLE__
    int arg = 1;
    setsockopt(client_fd, SOL_SOCKET, SO_NOSIGPIPE, &arg, sizeof(arg));
#endif
    
    int flags = fcntl(client_fd, F_GETFL, 0);
    if (fcntl(client_fd, F_SETFL, flags | O_NONBLOCK) == -1) {
        close(client_fd);
        return -3;
    }
    
    return client_fd;
}

int socket_connect(const char* address, uint16_t port) {
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

    int fd;
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

    return fd;
}

long socket_send(int fd, uint8_t* data, long length) {
    long remaining = length;
    while (remaining > 0) {
#ifdef  __APPLE__
        long rv = send(fd, data, remaining, 0);
#else
        long rv = send(fd, data, remaining, MSG_NOSIGNAL);
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

long socket_recv(int fd, uint8_t* data, long length) {
    return read(fd, data, length);
}

int socket_close(int fd) {
    return close(fd);
}
