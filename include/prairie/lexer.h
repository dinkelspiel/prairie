#include "stdbool.h"

#ifndef PRAIRIE_LEXER_H
#define PRAIRIE_LEXER_H

typedef enum {
  PRAIRIE_TOKEN_IDENTIFIER = 0,
  PRAIRIE_TOKEN_COLON = 1,
  PRAIRIE_TOKEN_BODY = 2
} prairie_token_type_t;

typedef struct prairie_token_t {
  prairie_token_type_t type;
  char *lexeme;
  struct prairie_token_t *next;
} prairie_token_t;

typedef enum {
  PRAIRIE_LS_METHOD,
  PRAIRIE_LS_ROUTE,
  PRAIRIE_LS_PROTOCOL,
  PRAIRIE_LS_FIELD_NAME,
  PRAIRIE_LS_FIELD_VALUE,
  PRAIRIE_LS_BODY
} prairie_lexer_state_t;

typedef struct {
  prairie_token_t *token_start;
  prairie_token_t *token_end;
  char *acc;
  prairie_lexer_state_t state;
} prairie_lexer_ctx_t;

prairie_token_t *prairie_lex(char *raw_file, int raw_file_length);
void prairie_print_token(prairie_token_t *token);
void prairie_print_tokens(prairie_token_t *token);
char *prairie_token_to_string(prairie_token_t *token);
char *prairie_token_type_to_string(prairie_token_type_t type);

#endif
