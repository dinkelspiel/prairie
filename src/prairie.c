#include "stdlib.h"
#include <prairie/lexer.h>
#include <prairie/parser.h>

prairie_request_t *prairie_request_create(char *raw, int length) {
  prairie_token_t *token = prairie_lex(raw, length);
  //   print_tokens(token);

  prairie_request_t *request = prairie_parse_request(token);
  //   print_response(response);
  return request;
}

void prairie_request_destroy(prairie_request_t *request) {
  prairie_header_t *header = request->header_start;

  while (header != NULL) {
    prairie_header_t *next = header->next;
    free(header);

    header = next;
  }
  free(request);
}