%option noyywrap
%option never-interactive
%option nodefault
%option nounistd
%option noinput
%option nounput

%x STRING
%x RAW_STRING
%x BLOCK_COMMENT

%{
#include "Lexer.h"

#define YY_DECL int yylex(LexerContext& lexer)
%}

/* Регулярные выражения ASCII-идентификаторов */
ID_START        [a-zA-Z_]
ID_CONT         [a-zA-Z0-9_]
IDENTIFIER      {ID_START}{ID_CONT}*
SUFFIX          ([a-zA-Z]{ID_CONT}*|_{ID_CONT}+)

/* Регулярные выражения числовых литералов */
/* Суффикс отделяется не здесь, он разрешён у любого literal token, а его смысл проверяется на следующих этапах. */
DEC_NUMBER      [0-9][0-9_]*
BIN_NUMBER      0b_*[01][01_]*
OCT_NUMBER      0o_*[0-7][0-7_]*
HEX_NUMBER      0x_*[0-9a-fA-F][0-9a-fA-F_]*
EXPONENT        [eE][+-]?_*[0-9][0-9_]*

/* Общие элементы строк и символьных литералов */
CHAR_UNIT       ([^\'\\\r\n]|\\x[0-9a-fA-F]{2}|\\[^\r\n])
PATTERN_WS      [ \t\v\f\r\n]

%%

 /* ЗОНА 1 Пробельные символы */

{PATTERN_WS}+   { /* Пробелы только разделяют токены. */ }


 /* ЗОНА 2 Ключевые слова */

"_"         { return lexer.emitToken(TokenKind::UNDERSCORE, yytext, yyleng); }
"as"        { return lexer.emitToken(TokenKind::AS, yytext, yyleng); }
"async"     { return lexer.emitToken(TokenKind::ASYNC, yytext, yyleng); }
"await"     { return lexer.emitToken(TokenKind::AWAIT, yytext, yyleng); }
"break"     { return lexer.emitToken(TokenKind::BREAK, yytext, yyleng); }
"const"     { return lexer.emitToken(TokenKind::CONST, yytext, yyleng); }
"continue"  { return lexer.emitToken(TokenKind::CONTINUE, yytext, yyleng); }
"crate"     { return lexer.emitToken(TokenKind::CRATE, yytext, yyleng); }
"dyn"       { return lexer.emitToken(TokenKind::DYN, yytext, yyleng); }
"else"      { return lexer.emitToken(TokenKind::ELSE, yytext, yyleng); }
"enum"      { return lexer.emitToken(TokenKind::ENUM, yytext, yyleng); }
"extern"    { return lexer.emitToken(TokenKind::EXTERN, yytext, yyleng); }
"false"     { return lexer.emitToken(TokenKind::FALSE, yytext, yyleng); }
"fn"        { return lexer.emitToken(TokenKind::FN, yytext, yyleng); }
"for"       { return lexer.emitToken(TokenKind::FOR, yytext, yyleng); }
"if"        { return lexer.emitToken(TokenKind::IF, yytext, yyleng); }
"impl"      { return lexer.emitToken(TokenKind::IMPL, yytext, yyleng); }
"in"        { return lexer.emitToken(TokenKind::IN, yytext, yyleng); }
"let"       { return lexer.emitToken(TokenKind::LET, yytext, yyleng); }
"loop"      { return lexer.emitToken(TokenKind::LOOP, yytext, yyleng); }
"match"     { return lexer.emitToken(TokenKind::MATCH, yytext, yyleng); }
"mod"       { return lexer.emitToken(TokenKind::MOD, yytext, yyleng); }
"move"      { return lexer.emitToken(TokenKind::MOVE, yytext, yyleng); }
"mut"       { return lexer.emitToken(TokenKind::MUT, yytext, yyleng); }
"pub"       { return lexer.emitToken(TokenKind::PUB, yytext, yyleng); }
"ref"       { return lexer.emitToken(TokenKind::REF, yytext, yyleng); }
"return"    { return lexer.emitToken(TokenKind::RETURN, yytext, yyleng); }
"self"      { return lexer.emitToken(TokenKind::SELF_VALUE, yytext, yyleng); }
"Self"      { return lexer.emitToken(TokenKind::SELF_TYPE, yytext, yyleng); }
"static"    { return lexer.emitToken(TokenKind::STATIC, yytext, yyleng); }
"struct"    { return lexer.emitToken(TokenKind::STRUCT, yytext, yyleng); }
"super"     { return lexer.emitToken(TokenKind::SUPER, yytext, yyleng); }
"trait"     { return lexer.emitToken(TokenKind::TRAIT, yytext, yyleng); }
"true"      { return lexer.emitToken(TokenKind::TRUE, yytext, yyleng); }
"type"      { return lexer.emitToken(TokenKind::TYPE, yytext, yyleng); }
"unsafe"    { return lexer.emitToken(TokenKind::UNSAFE, yytext, yyleng); }
"use"       { return lexer.emitToken(TokenKind::USE, yytext, yyleng); }
"where"     { return lexer.emitToken(TokenKind::WHERE, yytext, yyleng); }
"while"     { return lexer.emitToken(TokenKind::WHILE, yytext, yyleng); }

"abstract"  { return lexer.emitToken(TokenKind::ABSTRACT, yytext, yyleng); }
"become"    { return lexer.emitToken(TokenKind::BECOME, yytext, yyleng); }
"box"       { return lexer.emitToken(TokenKind::BOX, yytext, yyleng); }
"do"        { return lexer.emitToken(TokenKind::DO, yytext, yyleng); }
"final"     { return lexer.emitToken(TokenKind::FINAL, yytext, yyleng); }
"macro"     { return lexer.emitToken(TokenKind::MACRO, yytext, yyleng); }
"override"  { return lexer.emitToken(TokenKind::OVERRIDE, yytext, yyleng); }
"priv"      { return lexer.emitToken(TokenKind::PRIV, yytext, yyleng); }
"try"       { return lexer.emitToken(TokenKind::TRY, yytext, yyleng); }
"typeof"    { return lexer.emitToken(TokenKind::TYPEOF, yytext, yyleng); }
"unsized"   { return lexer.emitToken(TokenKind::UNSIZED, yytext, yyleng); }
"virtual"   { return lexer.emitToken(TokenKind::VIRTUAL, yytext, yyleng); }
"yield"     { return lexer.emitToken(TokenKind::YIELD, yytext, yyleng); }


 /* ЗОНА 3 Однострочные комментарии */

"//"[^\r\n]*                { /* Комментарий пропускается. */ }


 /* ЗОНА 4 Вложенные блочные комментарии */

"/*"                            {
                                      lexer.beginBlockComment();
                                      BEGIN(BLOCK_COMMENT);
                                  }
<BLOCK_COMMENT>"/*"              { lexer.enterNestedBlockComment(); }
<BLOCK_COMMENT>"*/"              {
                                      if (lexer.leaveBlockComment()) {
                                          BEGIN(INITIAL);
                                      }
                                  }
<BLOCK_COMMENT>[^*/]+             { /* Содержимое комментария пропускается. */ }
<BLOCK_COMMENT>[*/]               { /* Одиночные / и * пропускаются. */ }
<BLOCK_COMMENT><<EOF>>            {
                                      lexer.reportUnclosedBlockComment();
                                      return 0;
                                  }


 /* ЗОНА 5 Открывающая часть raw-строки */

r[#]*\"                          {
                                      lexer.beginRawString(yytext, yyleng);
                                      BEGIN(RAW_STRING);
                                  }


 /* ЗОНА 6 Обычная строка */

\"                                {
                                      lexer.beginString(yytext, yyleng);
                                      BEGIN(STRING);
                                  }


 /* ЗОНА 7 Содержимое обычных строк и escape-последовательности */

<STRING>[^\"\\\r]+             {
                                      lexer.appendStringText(yytext, yyleng);
                                  }
<STRING>\\[nrt0\\\'\"]        {
                                      lexer.appendStringEscape(yytext, yyleng);
                                  }
<STRING>\\x[0-9a-fA-F]{2}       {
                                      lexer.appendStringEscape(yytext, yyleng, true);
                                  }
<STRING>\\\r?\n{PATTERN_WS}*       { lexer.appendStringContinuation(yytext, yyleng); }
<STRING>\\.                       {
                                      lexer.appendStringError(yytext, yyleng, "unknown string escape");
                                  }
<STRING>\\                        {
                                      lexer.appendStringError(yytext, yyleng, "unfinished string escape");
                                  }
<STRING>\r\n                       {
                                      lexer.appendStringCrLf(yytext, yyleng);
                                  }
<STRING>\r                         {
                                      lexer.appendStringError(yytext, yyleng,
                                          "carriage return is not allowed in a string literal");
                                  }
<STRING>\"{SUFFIX}?               {
                                      const int token = lexer.finishString(yytext, yyleng);
                                      BEGIN(INITIAL);
                                      if (token != 0) return token;
                                  }
<STRING><<EOF>>                    {
                                      lexer.reportUnclosedAccumulated("string literal is not closed");
                                      return 0;
                                  }


 /* ЗОНА 8 Содержимое raw-строк */

<RAW_STRING>[^\"\r]+             {
                                      lexer.appendRawText(yytext, yyleng);
                                  }
<RAW_STRING>\r\n                   {
                                      lexer.appendRawCrLf(yytext, yyleng);
                                  }
<RAW_STRING>\r                     {
                                      lexer.appendRawCarriageReturn(yytext, yyleng);
                                  }
<RAW_STRING>\"[#]*{SUFFIX}?     {
                                      const int usedLength =
                                          lexer.rawClosingPrefixLength(yytext, yyleng);
                                      if (usedLength < 0) {
                                          lexer.appendRawText(yytext, yyleng);
                                      } else {
                                          if (usedLength < yyleng) {
                                              yyless(usedLength);
                                          }
                                          const int token = lexer.finishRawString(yytext, usedLength);
                                          BEGIN(INITIAL);
                                          if (token != 0) return token;
                                      }
                                  }
<RAW_STRING><<EOF>>               {
                                      lexer.reportUnclosedAccumulated("raw string literal is not closed");
                                      return 0;
                                  }


 /* ЗОНА 9 Символьные литералы */

\'{CHAR_UNIT}\'{SUFFIX}?         {
                                      const int token = lexer.handleCharacterLiteral(yytext, yyleng);
                                      if (token != 0) return token;
                                  }


 /* ЗОНА 10. Raw identifiers */

r#(crate|self|Self|super|_)       { lexer.reportCurrentError("this raw identifier name is reserved", yytext, yyleng); }
r#{IDENTIFIER}                    { return lexer.emitToken(TokenKind::RAW_IDENTIFIER, yytext, yyleng); }


 /* ЗОНА 11 Целочисленные литералы: binary / octal / hexadecimal */

 /* 0b101e10 - было бы 0b101 и отдельно e10*/
 
{BIN_NUMBER}[eE]{ID_CONT}*        { lexer.reportCurrentError("binary integer literal may not be followed by e or E", yytext, yyleng); }
{OCT_NUMBER}[eE]{ID_CONT}*        { lexer.reportCurrentError("octal integer literal may not be followed by e or E", yytext, yyleng); }
({BIN_NUMBER}|{OCT_NUMBER}|{HEX_NUMBER})/\.[0-9] {
                                      lexer.reportCurrentError("non-decimal integer literal may not be followed by a period", yytext, yyleng);
                                  }

{BIN_NUMBER}{SUFFIX}?             { const int token = lexer.handleIntegerLiteral(TokenKind::INTEGER_LITERAL_BIN, 2, 2, yytext, yyleng); if (token != 0) return token; }
{OCT_NUMBER}{SUFFIX}?             { const int token = lexer.handleIntegerLiteral(TokenKind::INTEGER_LITERAL_OCT, 8, 2, yytext, yyleng); if (token != 0) return token; }
{HEX_NUMBER}{SUFFIX}?             { const int token = lexer.handleIntegerLiteral(TokenKind::INTEGER_LITERAL_HEX, 16, 2, yytext, yyleng); if (token != 0) return token; }

0b{ID_CONT}*                      { lexer.reportCurrentError("invalid binary integer literal", yytext, yyleng); }
0o{ID_CONT}*                      { lexer.reportCurrentError("invalid octal integer literal", yytext, yyleng); }
0x{ID_CONT}*                      { lexer.reportCurrentError("invalid hexadecimal integer literal", yytext, yyleng); }


 /* ЗОНА 12 Decimal integer и floating-point literals */

{DEC_NUMBER}(\.{DEC_NUMBER})?{EXPONENT}{SUFFIX}? {
                                      const int token = lexer.handleFloatingLiteral(yytext, yyleng); if (token != 0) return token;
                                  }
{DEC_NUMBER}(\.{DEC_NUMBER})?[eE][+-]?{ID_CONT}* {
                                      lexer.reportCurrentError("floating-point exponent has no digits", yytext, yyleng);
                                  }
{DEC_NUMBER}\.{DEC_NUMBER}{SUFFIX}? { const int token = lexer.handleFloatingLiteral(yytext, yyleng); if (token != 0) return token; }
{DEC_NUMBER}/\.\.               { const int token = lexer.handleIntegerLiteral(TokenKind::INTEGER_LITERAL_DEC, 10, 0, yytext, yyleng); if (token != 0) return token; }
{DEC_NUMBER}/\.{ID_START}        { const int token = lexer.handleIntegerLiteral(TokenKind::INTEGER_LITERAL_DEC, 10, 0, yytext, yyleng); if (token != 0) return token; }
{DEC_NUMBER}\.                   { const int token = lexer.handleFloatingLiteral(yytext, yyleng); if (token != 0) return token; }
{DEC_NUMBER}(f32|f64)             { const int token = lexer.handleFloatingLiteral(yytext, yyleng); if (token != 0) return token; }
{DEC_NUMBER}{SUFFIX}?             { const int token = lexer.handleIntegerLiteral(TokenKind::INTEGER_LITERAL_DEC, 10, 0, yytext, yyleng); if (token != 0) return token; }

 /* ЗОНА 13 Reserved prefixes и обычные идентификаторы */

{IDENTIFIER}/\"                 { lexer.reportCurrentError("reserved identifier prefix before a string", yytext, yyleng); }
{IDENTIFIER}/\'                  { lexer.reportCurrentError("reserved identifier prefix before a character quote", yytext, yyleng); }
{IDENTIFIER}/#                   {
                                      const std::string_view text(yytext,
                                          static_cast<std::size_t>(yyleng));
                                      if (text == "r") {
                                          return lexer.emitToken(TokenKind::ID, yytext, yyleng);
                                      } else {
                                          lexer.reportCurrentError("reserved identifier prefix before #", yytext, yyleng);
                                      }
                                  }

{IDENTIFIER}                      { return lexer.emitToken(TokenKind::ID, yytext, yyleng); }


 /* ЗОНА 14 Составная пунктуация и операторы (проверяется первой) */

"..="                             { return lexer.emitToken(TokenKind::RANGE_INCLUSIVE, yytext, yyleng); }
"<<="                             { return lexer.emitToken(TokenKind::SHIFT_LEFT_ASSIGN, yytext, yyleng); }
">>="                             { return lexer.emitToken(TokenKind::SHIFT_RIGHT_ASSIGN, yytext, yyleng); }
"!="                              { return lexer.emitToken(TokenKind::NOT_EQUAL, yytext, yyleng); }
"%="                              { return lexer.emitToken(TokenKind::REMAINDER_ASSIGN, yytext, yyleng); }
"&&"                              { return lexer.emitToken(TokenKind::LOGICAL_AND, yytext, yyleng); }
"&="                              { return lexer.emitToken(TokenKind::BIT_AND_ASSIGN, yytext, yyleng); }
"*="                              { return lexer.emitToken(TokenKind::MULTIPLY_ASSIGN, yytext, yyleng); }
"+="                              { return lexer.emitToken(TokenKind::PLUS_ASSIGN, yytext, yyleng); }
"-="                              { return lexer.emitToken(TokenKind::MINUS_ASSIGN, yytext, yyleng); }
"->"                              { return lexer.emitToken(TokenKind::RIGHT_ARROW, yytext, yyleng); }
".."                              { return lexer.emitToken(TokenKind::RANGE, yytext, yyleng); }
"/="                              { return lexer.emitToken(TokenKind::DIVIDE_ASSIGN, yytext, yyleng); }
"::"                              { return lexer.emitToken(TokenKind::PATH_SEPARATOR, yytext, yyleng); }
"<<"                              { return lexer.emitToken(TokenKind::SHIFT_LEFT, yytext, yyleng); }
"<="                              { return lexer.emitToken(TokenKind::LESS_EQUAL, yytext, yyleng); }
"=="                              { return lexer.emitToken(TokenKind::EQUAL_EQUAL, yytext, yyleng); }
"=>"                              { return lexer.emitToken(TokenKind::FAT_ARROW, yytext, yyleng); }
">="                              { return lexer.emitToken(TokenKind::GREATER_EQUAL, yytext, yyleng); }
">>"                              { return lexer.emitToken(TokenKind::SHIFT_RIGHT, yytext, yyleng); }
"^="                              { return lexer.emitToken(TokenKind::BIT_XOR_ASSIGN, yytext, yyleng); }
"|="                              { return lexer.emitToken(TokenKind::BIT_OR_ASSIGN, yytext, yyleng); }
"||"                              { return lexer.emitToken(TokenKind::LOGICAL_OR, yytext, yyleng); }


 /* ЗОНА 15 Односимвольная пунктуация, операторы и delimiters */

"!"                               { return lexer.emitToken(TokenKind::BANG, yytext, yyleng); }
"#"                               { return lexer.emitToken(TokenKind::POUND, yytext, yyleng); }
"$"                               { return lexer.emitToken(TokenKind::DOLLAR, yytext, yyleng); }
"%"                               { return lexer.emitToken(TokenKind::REMAINDER, yytext, yyleng); }
"&"                               { return lexer.emitToken(TokenKind::AMPERSAND, yytext, yyleng); }
"("                               { return lexer.emitToken(TokenKind::LEFT_PAREN, yytext, yyleng); }
")"                               { return lexer.emitToken(TokenKind::RIGHT_PAREN, yytext, yyleng); }
"*"                               { return lexer.emitToken(TokenKind::STAR, yytext, yyleng); }
"+"                               { return lexer.emitToken(TokenKind::PLUS, yytext, yyleng); }
","                               { return lexer.emitToken(TokenKind::COMMA, yytext, yyleng); }
"-"                               { return lexer.emitToken(TokenKind::MINUS, yytext, yyleng); }
"."                               { return lexer.emitToken(TokenKind::DOT, yytext, yyleng); }
"/"                               { return lexer.emitToken(TokenKind::SLASH, yytext, yyleng); }
":"                               { return lexer.emitToken(TokenKind::COLON, yytext, yyleng); }
";"                               { return lexer.emitToken(TokenKind::SEMICOLON, yytext, yyleng); }
"<"                               { return lexer.emitToken(TokenKind::LESS, yytext, yyleng); }
"="                               { return lexer.emitToken(TokenKind::ASSIGN, yytext, yyleng); }
">"                               { return lexer.emitToken(TokenKind::GREATER, yytext, yyleng); }
"?"                               { return lexer.emitToken(TokenKind::QUESTION, yytext, yyleng); }
"@"                               { return lexer.emitToken(TokenKind::AT, yytext, yyleng); }
"["                               { return lexer.emitToken(TokenKind::LEFT_BRACKET, yytext, yyleng); }
"]"                               { return lexer.emitToken(TokenKind::RIGHT_BRACKET, yytext, yyleng); }
"^"                               { return lexer.emitToken(TokenKind::BIT_XOR, yytext, yyleng); }
"{"                               { return lexer.emitToken(TokenKind::LEFT_BRACE, yytext, yyleng); }
"|"                               { return lexer.emitToken(TokenKind::PIPE, yytext, yyleng); }
"}"                               { return lexer.emitToken(TokenKind::RIGHT_BRACE, yytext, yyleng); }
"~"                               { return lexer.emitToken(TokenKind::TILDE, yytext, yyleng); }


 /* ЗОНА 16 Неизвестные символы и конец файла */

\'                                { lexer.reportCurrentError("unexpected single quote", yytext, yyleng); }
.                                 { lexer.reportCurrentError("unknown character", yytext, yyleng); }

%%
