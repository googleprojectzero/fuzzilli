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

#ifndef __LIBSOCKET_H__
#define __LIBSOCKET_H__

#include <stdint.h>
#include <sys/types.h>

typedef int socket_t;

socket_t socket_listen(const char* address, uint16_t port);
socket_t socket_accept(socket_t socket);
socket_t socket_connect(const char* address, uint16_t port);

ssize_t socket_send(socket_t socket, const uint8_t* data, size_t length);
ssize_t socket_recv(socket_t socket, uint8_t* buffer, size_t length);

int socket_shutdown(socket_t socket);
int socket_close(socket_t socket);

#endif
