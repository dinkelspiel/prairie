#include "stdbool.h"
#include "stdlib.h"
#include "string.h"

#ifndef PRAIRIE_UTILS_H
#define PRAIRIE_UTILS_H

char *prairie_pad_right(char *value, int length, char padding);
char *prairie_pad_left(char *value, int length, char padding);

#endif