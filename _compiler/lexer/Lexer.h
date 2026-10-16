#pragma once

#include "LexerContext.h"

#include <cstdio>

// Returns one token kind per call, or 0 at end of input. Valid token data is
// available in context.token(); lexical errors are recorded in the context.
int yylex(LexerContext& context);

// Flex input controls. The caller owns the FILE*.
extern FILE* yyin;
void yyrestart(FILE* input);
