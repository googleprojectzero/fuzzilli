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

int socket_listen(const char* address, uint16_t port);
int socket_accept(int socket);
int socket_connect(const char* address, uint16_t port);

long socket_send(int socket, const uint8_t* data, long length);
long socket_recv(int socket, uint8_t* buffer, long length);

int socket_close(int socket);

#endif
