#include "parser.h"

#ifndef PRAIRIE_H

prairie_request_t *prairie_request_create(char *raw, int length);
void prairie_request_destroy(prairie_request_t *request);

#endif
#define PRAIRIE_H