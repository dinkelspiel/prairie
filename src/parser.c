#include "stdarg.h"
#include "stdbool.h"
#include "stdio.h"
#include "stdlib.h"
#include "string.h"
#include <prairie/lexer.h>
#include <prairie/parser.h>
#include <prairie/utils.h>

void advance(prairie_parser_ctx_t *ctx) {
  ctx->current_token = ctx->current_token->next;
}

/**
 * Returns true if the assertion passes
 */
bool assert(prairie_parser_ctx_t *ctx, prairie_token_type_t type) {
  if (ctx->current_token->type != type) {
    printf("unexpected token, expected %s, found %s\n",
           prairie_token_type_to_string(type),
           prairie_token_to_string(ctx->current_token));
    return false;
  }
  return true;
}

bool assert_advance(prairie_parser_ctx_t *ctx, prairie_token_type_t type) {
  if (assert(ctx, type)) {
    advance(ctx);
    return true;
  }
  return false;
}

prairie_method_t string_to_method(char *value) {
  if (strcmp(value, "GET") == 0)
    return GET;
  if (strcmp(value, "POST") == 0)
    return POST;

  // Might want to do some error handling here but default > crash
  return GET;
}

prairie_protocol_t string_to_protocol(char *value) {
  if (strcmp(value, "HTTP/1.0") == 0)
    return HTTP_1_0;
  if (strcmp(value, "HTTP/1.1") == 0)
    return HTTP_1_1;
  if (strcmp(value, "HTTP/2") == 0)
    return HTTP_2;

  // Might want to do some error handling here but default > crash
  return HTTP_1_1;
}

#define free_and_return                                                        \
  {                                                                            \
    printf("Error occured\n");                                                 \
    free(ctx);                                                                 \
    free(request);                                                             \
    return NULL;                                                               \
  }

void prairie_print_request(prairie_request_t *request) {
  printf("%d %s %d\n", request->method, request->route, request->protocol);
  prairie_header_t *header = request->header_start;
  while (header != NULL) {
    printf("%s: %s\n", header->key, header->value);
    header = header->next;
  }
  printf("%s\n", request->body);
}

prairie_request_t *prairie_parse_request(prairie_token_t *token_start) {
  prairie_request_t *request = malloc(sizeof(prairie_request_t));
  prairie_parser_ctx_t *ctx = malloc(sizeof(prairie_parser_ctx_t));
  ctx->current_token = token_start;
  ctx->request = request;

  if (!assert(ctx, PRAIRIE_TOKEN_IDENTIFIER))
    free_and_return;

  // printf("method: %s\n", ctx->current_token->lexeme);
  ctx->request->method = string_to_method(ctx->current_token->lexeme);
  advance(ctx);

  if (!assert(ctx, PRAIRIE_TOKEN_IDENTIFIER))
    free_and_return;

  // printf("route: %s\n", ctx->current_token->lexeme);
  ctx->request->route = ctx->current_token->lexeme;
  advance(ctx);

  if (!assert(ctx, PRAIRIE_TOKEN_IDENTIFIER))
    free_and_return;

  // printf("protocol: %s\n", ctx->current_token->lexeme);
  ctx->request->protocol = string_to_protocol(ctx->current_token->lexeme);
  advance(ctx);

  while (ctx->current_token != NULL) {
    if (ctx->current_token->type == PRAIRIE_TOKEN_IDENTIFIER) {
      prairie_header_t *header = malloc(sizeof(prairie_header_t));
      header->key = ctx->current_token->lexeme;
      header->next = NULL;
      advance(ctx);

      if (!assert_advance(ctx, PRAIRIE_TOKEN_COLON))
        free_and_return;

      header->value = ctx->current_token->lexeme;

      if (ctx->request->header_start == NULL) {
        ctx->request->header_start = header;
        ctx->request->header_end = header;
      } else {
        ctx->request->header_end->next = header;
        ctx->request->header_end = header;
      }
      advance(ctx);
    } else if (ctx->current_token->type == PRAIRIE_TOKEN_BODY) {
      ctx->request->body = ctx->current_token->lexeme;
      free(ctx);

      return request;
    } else {
      printf("unexpected token. expected identifier or body, found %s\n",
             prairie_token_to_string(ctx->current_token));
      free_and_return;
    }
  }

  free(ctx);
  return request;
}