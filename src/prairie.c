#include <prairie/lexer.h>
#include <prairie/parser.h>

prairie_request_t *prairie_make_request(char *raw, int length) {
  prairie_token_t *token = prairie_lex(raw, length);
  //   print_tokens(token);

  prairie_request_t *request = prairie_parse_request(token);
  //   print_response(response);
  return request;
}