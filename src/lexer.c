#include "stdio.h"
#include "stdlib.h"
#include "string.h"
#include <prairie/lexer.h>
#include <prairie/utils.h>

void add_token(prairie_lexer_ctx_t *ctx, prairie_token_type_t type,
               char *lexeme) {
  prairie_token_t *token = malloc(sizeof(prairie_token_t));
  token->type = type;
  token->lexeme = lexeme;

  if (ctx->token_end != NULL) {
    ctx->token_end->next = token;
    ctx->token_end = token;
  } else {
    ctx->token_end = token;
    ctx->token_start = token;
  }
}

void default_acc(prairie_lexer_ctx_t *ctx) {
  ctx->acc = malloc(1);
  ctx->acc[0] = '\0';
}

void pop_acc(prairie_lexer_ctx_t *ctx, prairie_token_type_t type) {
  if (strcmp(ctx->acc, "") == 0)
    return;

  add_token(ctx, type, ctx->acc);

  default_acc(ctx);
}

char *token_to_string_map[] = {"identifier", "colon", "body"};

char *prairie_token_to_string(prairie_token_t *token) {
  return token_to_string_map[token->type];
}
char *prairie_token_type_to_string(prairie_token_type_t type) {
  return token_to_string_map[type];
}

void prairie_print_token(prairie_token_t *token) {
  int map_length = 3;
  int max_value_length = 0;

  for (int i = 0; i < map_length; i++) {
    int value_length = strlen(token_to_string_map[i]);
    if (value_length > max_value_length)
      max_value_length = value_length;
  }

  printf("%s %s\n",
         prairie_pad_right(token_to_string_map[token->type],
                           max_value_length + 1, ' '),
         token->lexeme);
}

void prairie_print_tokens(prairie_token_t *token) {
  prairie_token_t *tmp_token = token;
  while (tmp_token != NULL) {
    prairie_print_token(tmp_token);
    tmp_token = tmp_token->next;
  }
}

prairie_token_t *prairie_lex(char *raw_file, int raw_file_length) {
  prairie_lexer_ctx_t *ctx = malloc(sizeof(prairie_lexer_ctx_t));
  ctx->token_start = NULL;
  ctx->token_end = NULL;
  ctx->acc = NULL;
  ctx->state = PRAIRIE_LS_METHOD;
  default_acc(ctx);

  for (int i = 0; i < raw_file_length; i++) {
    switch (raw_file[i]) {
    case '\n':
      if (ctx->state != PRAIRIE_LS_BODY) {
        if (ctx->state == PRAIRIE_LS_FIELD_NAME) {
          ctx->state = PRAIRIE_LS_BODY;
          break;
        }

        pop_acc(ctx, PRAIRIE_TOKEN_IDENTIFIER);
        ctx->state = PRAIRIE_LS_FIELD_NAME;
        break;
      }
      __attribute__((fallthrough));
    case ' ':
      if (ctx->state == PRAIRIE_LS_METHOD) {
        pop_acc(ctx, PRAIRIE_TOKEN_IDENTIFIER);
        ctx->state = PRAIRIE_LS_ROUTE;
        break;
      }
      if (ctx->state == PRAIRIE_LS_ROUTE) {
        pop_acc(ctx, PRAIRIE_TOKEN_IDENTIFIER);
        ctx->state = PRAIRIE_LS_PROTOCOL;
        break;
      }
      __attribute__((fallthrough));
    case ':':
      if (ctx->state == PRAIRIE_LS_FIELD_NAME) {
        i++;
        pop_acc(ctx, PRAIRIE_TOKEN_IDENTIFIER);
        add_token(ctx, PRAIRIE_TOKEN_COLON, ":");
        ctx->state = PRAIRIE_LS_FIELD_VALUE;
        break;
      }
      __attribute__((fallthrough));
    default: {
      int acc_length = strlen(ctx->acc);
      char *tmp = realloc(ctx->acc, acc_length + 2);
      if (!tmp) {
        printf("failed to allocate accumulator in lexer");
        return 0;
      }

      ctx->acc = tmp;
      ctx->acc[acc_length] = raw_file[i];
      ctx->acc[acc_length + 1] = '\0';

    } break;
    }
  }

  if (ctx->state == PRAIRIE_LS_BODY)
    pop_acc(ctx, PRAIRIE_TOKEN_BODY);

  prairie_token_t *start = ctx->token_start;
  free(ctx);
  return start;
}

void prairie_token_destroy(prairie_token_t *token_start) {
  prairie_token_t *token = token_start;

  while (token != NULL) {
    prairie_token_t *next = token->next;
    free(token);

    token = next;
  }
}