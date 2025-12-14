#include "stdbool.h"
#include "stdlib.h"
#include "string.h"

char *prairie_pad_right(char *value, int length, char padding) {
  int value_length = strlen(value);

  // Don't do any processing if the desired length is below the values length
  if (length <= value_length)
    return value;

  char *padded_value = (char *)malloc(length + 1);
  for (int i = 0; i < length; i++) {
    if (i < value_length) {
      padded_value[i] = value[i];
    } else {
      padded_value[i] = padding;
    }
  }
  padded_value[length] = '\0';

  return padded_value;
}

char *prairie_pad_left(char *value, int length, char padding) {
  int value_length = strlen(value);

  // Don't do any processing if the desired length is below the values length
  if (length <= value_length)
    return value;

  char *padded_value = (char *)malloc(length + 1);
  for (int i = 0; i < length; i++) {
    if (i < length - value_length) {
      padded_value[i] = padding;
    } else {
      padded_value[i] = value[i - (length - value_length)];
    }
  }
  padded_value[length] = '\0';
  return padded_value;
}