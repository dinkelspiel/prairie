#include <prairie/lexer.h>
#include <prairie/parser.h>

prairie_response_t *prairie_make_response(char *raw, int length) {
  prairie_token_t *token = prairie_lex(raw, length);
  //   print_tokens(token);

  prairie_response_t *response = prairie_parse(token);
  //   print_response(response);
  return response;
}