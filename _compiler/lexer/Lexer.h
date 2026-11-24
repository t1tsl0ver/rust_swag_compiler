#pragma once

#include "LexerContext.h"

#include <cstdio>

// Возвращает код очередной лексемы или 0 в конце файла. Данные лексемы доступны
// через context.token(). Лексические ошибки сохраняются в контексте.
int yylex(LexerContext& context);

// Начинает чтение нового файла и сбрасывает состояние Flex. Файл закрывает вызывающий код.
void lexerRestart(FILE* input);
