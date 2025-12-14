#include "lexer.h"

#ifndef PRAIRIE_PARSER_H
#define PRAIRIE_PARSER_H

typedef enum { GET, POST } prairie_method_t;

typedef enum { HTTP_1_0, HTTP_1_1, HTTP_2 } prairie_protocol_t;

typedef struct prairie_header_t {
  char *key;
  char *value;
  struct prairie_header_t *next;
} prairie_header_t;

typedef struct {
  prairie_method_t method;
  char *route;
  prairie_protocol_t protocol;
  char *body;
  prairie_header_t *header_start;
  prairie_header_t *header_end;
} prairie_response_t;

typedef struct {
  prairie_token_t *current_token;
  prairie_response_t *response;
} ParserContext;

prairie_response_t *prairie_parse(prairie_token_t *token_start);
void prairie_print_response(prairie_response_t *response);

#endif