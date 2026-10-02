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
#include "LexerContext.h"
#include <cstdio>
#include <cstring>

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

"_"         { lexer.printCurrentToken("UNDERSCORE", yytext, yyleng); }
"as"        { lexer.printCurrentToken("AS", yytext, yyleng); }
"async"     { lexer.printCurrentToken("ASYNC", yytext, yyleng); }
"await"     { lexer.printCurrentToken("AWAIT", yytext, yyleng); }
"break"     { lexer.printCurrentToken("BREAK", yytext, yyleng); }
"const"     { lexer.printCurrentToken("CONST", yytext, yyleng); }
"continue"  { lexer.printCurrentToken("CONTINUE", yytext, yyleng); }
"crate"     { lexer.printCurrentToken("CRATE", yytext, yyleng); }
"dyn"       { lexer.printCurrentToken("DYN", yytext, yyleng); }
"else"      { lexer.printCurrentToken("ELSE", yytext, yyleng); }
"enum"      { lexer.printCurrentToken("ENUM", yytext, yyleng); }
"extern"    { lexer.printCurrentToken("EXTERN", yytext, yyleng); }
"false"     { lexer.printCurrentToken("FALSE", yytext, yyleng); }
"fn"        { lexer.printCurrentToken("FN", yytext, yyleng); }
"for"       { lexer.printCurrentToken("FOR", yytext, yyleng); }
"if"        { lexer.printCurrentToken("IF", yytext, yyleng); }
"impl"      { lexer.printCurrentToken("IMPL", yytext, yyleng); }
"in"        { lexer.printCurrentToken("IN", yytext, yyleng); }
"let"       { lexer.printCurrentToken("LET", yytext, yyleng); }
"loop"      { lexer.printCurrentToken("LOOP", yytext, yyleng); }
"match"     { lexer.printCurrentToken("MATCH", yytext, yyleng); }
"mod"       { lexer.printCurrentToken("MOD", yytext, yyleng); }
"move"      { lexer.printCurrentToken("MOVE", yytext, yyleng); }
"mut"       { lexer.printCurrentToken("MUT", yytext, yyleng); }
"pub"       { lexer.printCurrentToken("PUB", yytext, yyleng); }
"ref"       { lexer.printCurrentToken("REF", yytext, yyleng); }
"return"    { lexer.printCurrentToken("RETURN", yytext, yyleng); }
"self"      { lexer.printCurrentToken("SELF_VALUE", yytext, yyleng); }
"Self"      { lexer.printCurrentToken("SELF_TYPE", yytext, yyleng); }
"static"    { lexer.printCurrentToken("STATIC", yytext, yyleng); }
"struct"    { lexer.printCurrentToken("STRUCT", yytext, yyleng); }
"super"     { lexer.printCurrentToken("SUPER", yytext, yyleng); }
"trait"     { lexer.printCurrentToken("TRAIT", yytext, yyleng); }
"true"      { lexer.printCurrentToken("TRUE", yytext, yyleng); }
"type"      { lexer.printCurrentToken("TYPE", yytext, yyleng); }
"unsafe"    { lexer.printCurrentToken("UNSAFE", yytext, yyleng); }
"use"       { lexer.printCurrentToken("USE", yytext, yyleng); }
"where"     { lexer.printCurrentToken("WHERE", yytext, yyleng); }
"while"     { lexer.printCurrentToken("WHILE", yytext, yyleng); }

"abstract"  { lexer.printCurrentToken("ABSTRACT", yytext, yyleng); }
"become"    { lexer.printCurrentToken("BECOME", yytext, yyleng); }
"box"       { lexer.printCurrentToken("BOX", yytext, yyleng); }
"do"        { lexer.printCurrentToken("DO", yytext, yyleng); }
"final"     { lexer.printCurrentToken("FINAL", yytext, yyleng); }
"macro"     { lexer.printCurrentToken("MACRO", yytext, yyleng); }
"override"  { lexer.printCurrentToken("OVERRIDE", yytext, yyleng); }
"priv"      { lexer.printCurrentToken("PRIV", yytext, yyleng); }
"try"       { lexer.printCurrentToken("TRY", yytext, yyleng); }
"typeof"    { lexer.printCurrentToken("TYPEOF", yytext, yyleng); }
"unsized"   { lexer.printCurrentToken("UNSIZED", yytext, yyleng); }
"virtual"   { lexer.printCurrentToken("VIRTUAL", yytext, yyleng); }
"yield"     { lexer.printCurrentToken("YIELD", yytext, yyleng); }


 /* ЗОНА 3 Однострочные комментарии и line doc comments */

"//!"[^\r\n]*               { lexer.printCurrentToken("INNER_LINE_DOC_COMMENT", yytext, yyleng); }
"///"([^/\r\n][^\r\n]*)?    { lexer.printCurrentToken("OUTER_LINE_DOC_COMMENT", yytext, yyleng); }
"//"[^\r\n]*                { lexer.printCurrentToken("LINE_COMMENT", yytext, yyleng); }


 /* ЗОНА 4 Вложенные блочные и block doc comments */

"/*"                            {
                                      lexer.beginBlockComment(yytext, yyleng);
                                      BEGIN(BLOCK_COMMENT);
                                  }
<BLOCK_COMMENT>"/*"              {
                                      lexer.openNestedBlockComment(yytext, yyleng);
                                  }
<BLOCK_COMMENT>"*/"              {
                                      if (lexer.closeBlockComment(yytext, yyleng)) {
                                          BEGIN(INITIAL);
                                      }
                                  }
<BLOCK_COMMENT>[^*/\r\n]+        { lexer.appendBlockComment(yytext, yyleng); }
<BLOCK_COMMENT>[*/]               { lexer.appendBlockComment(yytext, yyleng); }
<BLOCK_COMMENT>[\r\n]            { lexer.appendBlockComment(yytext, yyleng); }
<BLOCK_COMMENT><<EOF>>            {
                                      lexer.reportUnclosedAccumulated("block comment is not closed");
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
                                      lexer.finishString(yytext, yyleng);
                                      BEGIN(INITIAL);
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
                                          lexer.finishRawString(yytext, usedLength);
                                          BEGIN(INITIAL);
                                      }
                                  }
<RAW_STRING><<EOF>>               {
                                      lexer.reportUnclosedAccumulated("raw string literal is not closed");
                                      return 0;
                                  }


 /* ЗОНА 9 Символьные литералы */

\'{CHAR_UNIT}\'{SUFFIX}?         {
                                      lexer.handleCharacterLiteral(yytext, yyleng);
                                  }


 /* ЗОНА 10. Raw identifiers */

r#(crate|self|Self|super|_)       { lexer.reportCurrentError("this raw identifier name is reserved", yytext, yyleng); }
r#{IDENTIFIER}                    { lexer.printCurrentToken("RAW_IDENTIFIER", yytext, yyleng); }


 /* ЗОНА 11 Целочисленные литералы: binary / octal / hexadecimal */

 /* 0b101e10 - было бы 0b101 и отдельно e10*/
 
{BIN_NUMBER}[eE]{ID_CONT}*        { lexer.reportCurrentError("binary integer literal may not be followed by e or E", yytext, yyleng); }
{OCT_NUMBER}[eE]{ID_CONT}*        { lexer.reportCurrentError("octal integer literal may not be followed by e or E", yytext, yyleng); }
({BIN_NUMBER}|{OCT_NUMBER}|{HEX_NUMBER})/\.[0-9] {
                                      lexer.reportCurrentError("non-decimal integer literal may not be followed by a period", yytext, yyleng);
                                  }

{BIN_NUMBER}{SUFFIX}?             { lexer.handleIntegerLiteral("INTEGER_LITERAL_BIN", 2, 2, yytext, yyleng); }
{OCT_NUMBER}{SUFFIX}?             { lexer.handleIntegerLiteral("INTEGER_LITERAL_OCT", 8, 2, yytext, yyleng); }
{HEX_NUMBER}{SUFFIX}?             { lexer.handleIntegerLiteral("INTEGER_LITERAL_HEX", 16, 2, yytext, yyleng); }

0b{ID_CONT}*                      { lexer.reportCurrentError("invalid binary integer literal", yytext, yyleng); }
0o{ID_CONT}*                      { lexer.reportCurrentError("invalid octal integer literal", yytext, yyleng); }
0x{ID_CONT}*                      { lexer.reportCurrentError("invalid hexadecimal integer literal", yytext, yyleng); }


 /* ЗОНА 12 Decimal integer и floating-point literals */

{DEC_NUMBER}(\.{DEC_NUMBER})?{EXPONENT}{SUFFIX}? {
                                      lexer.handleFloatingLiteral(yytext, yyleng);
                                  }
{DEC_NUMBER}(\.{DEC_NUMBER})?[eE][+-]?{ID_CONT}* {
                                      lexer.reportCurrentError("floating-point exponent has no digits", yytext, yyleng);
                                  }
{DEC_NUMBER}\.{DEC_NUMBER}{SUFFIX}? { lexer.handleFloatingLiteral(yytext, yyleng); }
{DEC_NUMBER}/\.\.               { lexer.handleIntegerLiteral("INTEGER_LITERAL_DEC", 10, 0, yytext, yyleng); }
{DEC_NUMBER}/\.{ID_START}        { lexer.handleIntegerLiteral("INTEGER_LITERAL_DEC", 10, 0, yytext, yyleng); }
{DEC_NUMBER}\.                   { lexer.handleFloatingLiteral(yytext, yyleng); }
{DEC_NUMBER}(f32|f64)             { lexer.handleFloatingLiteral(yytext, yyleng); }
{DEC_NUMBER}{SUFFIX}?             { lexer.handleIntegerLiteral("INTEGER_LITERAL_DEC", 10, 0, yytext, yyleng); }

 /* ЗОНА 13 Reserved prefixes и обычные идентификаторы */

{IDENTIFIER}/\"                 { lexer.reportCurrentError("reserved identifier prefix before a string", yytext, yyleng); }
{IDENTIFIER}/\'                  { lexer.reportCurrentError("reserved identifier prefix before a character quote", yytext, yyleng); }
{IDENTIFIER}/#                   {
                                      const std::string_view text(yytext,
                                          static_cast<std::size_t>(yyleng));
                                      if (text == "r") {
                                          lexer.printCurrentToken("ID", yytext, yyleng);
                                      } else {
                                          lexer.reportCurrentError("reserved identifier prefix before #", yytext, yyleng);
                                      }
                                  }

{IDENTIFIER}                      { lexer.printCurrentToken("ID", yytext, yyleng); }


 /* ЗОНА 14 Составная пунктуация и операторы (проверяется первой) */

"..="                             { lexer.printCurrentToken("RANGE_INCLUSIVE", yytext, yyleng); }
"<<="                             { lexer.printCurrentToken("SHIFT_LEFT_ASSIGN", yytext, yyleng); }
">>="                             { lexer.printCurrentToken("SHIFT_RIGHT_ASSIGN", yytext, yyleng); }
"!="                              { lexer.printCurrentToken("NOT_EQUAL", yytext, yyleng); }
"%="                              { lexer.printCurrentToken("REMAINDER_ASSIGN", yytext, yyleng); }
"&&"                              { lexer.printCurrentToken("LOGICAL_AND", yytext, yyleng); }
"&="                              { lexer.printCurrentToken("BIT_AND_ASSIGN", yytext, yyleng); }
"*="                              { lexer.printCurrentToken("MULTIPLY_ASSIGN", yytext, yyleng); }
"+="                              { lexer.printCurrentToken("PLUS_ASSIGN", yytext, yyleng); }
"-="                              { lexer.printCurrentToken("MINUS_ASSIGN", yytext, yyleng); }
"->"                              { lexer.printCurrentToken("RIGHT_ARROW", yytext, yyleng); }
".."                              { lexer.printCurrentToken("RANGE", yytext, yyleng); }
"/="                              { lexer.printCurrentToken("DIVIDE_ASSIGN", yytext, yyleng); }
"::"                              { lexer.printCurrentToken("PATH_SEPARATOR", yytext, yyleng); }
"<<"                              { lexer.printCurrentToken("SHIFT_LEFT", yytext, yyleng); }
"<="                              { lexer.printCurrentToken("LESS_EQUAL", yytext, yyleng); }
"=="                              { lexer.printCurrentToken("EQUAL_EQUAL", yytext, yyleng); }
"=>"                              { lexer.printCurrentToken("FAT_ARROW", yytext, yyleng); }
">="                              { lexer.printCurrentToken("GREATER_EQUAL", yytext, yyleng); }
">>"                              { lexer.printCurrentToken("SHIFT_RIGHT", yytext, yyleng); }
"^="                              { lexer.printCurrentToken("BIT_XOR_ASSIGN", yytext, yyleng); }
"|="                              { lexer.printCurrentToken("BIT_OR_ASSIGN", yytext, yyleng); }
"||"                              { lexer.printCurrentToken("LOGICAL_OR", yytext, yyleng); }


 /* ЗОНА 15 Односимвольная пунктуация, операторы и delimiters */

"!"                               { lexer.printCurrentToken("BANG", yytext, yyleng); }
"#"                               { lexer.printCurrentToken("POUND", yytext, yyleng); }
"$"                               { lexer.printCurrentToken("DOLLAR", yytext, yyleng); }
"%"                               { lexer.printCurrentToken("REMAINDER", yytext, yyleng); }
"&"                               { lexer.printCurrentToken("AMPERSAND", yytext, yyleng); }
"("                               { lexer.printCurrentToken("LEFT_PAREN", yytext, yyleng); }
")"                               { lexer.printCurrentToken("RIGHT_PAREN", yytext, yyleng); }
"*"                               { lexer.printCurrentToken("STAR", yytext, yyleng); }
"+"                               { lexer.printCurrentToken("PLUS", yytext, yyleng); }
","                               { lexer.printCurrentToken("COMMA", yytext, yyleng); }
"-"                               { lexer.printCurrentToken("MINUS", yytext, yyleng); }
"."                               { lexer.printCurrentToken("DOT", yytext, yyleng); }
"/"                               { lexer.printCurrentToken("SLASH", yytext, yyleng); }
":"                               { lexer.printCurrentToken("COLON", yytext, yyleng); }
";"                               { lexer.printCurrentToken("SEMICOLON", yytext, yyleng); }
"<"                               { lexer.printCurrentToken("LESS", yytext, yyleng); }
"="                               { lexer.printCurrentToken("ASSIGN", yytext, yyleng); }
">"                               { lexer.printCurrentToken("GREATER", yytext, yyleng); }
"?"                               { lexer.printCurrentToken("QUESTION", yytext, yyleng); }
"@"                               { lexer.printCurrentToken("AT", yytext, yyleng); }
"["                               { lexer.printCurrentToken("LEFT_BRACKET", yytext, yyleng); }
"]"                               { lexer.printCurrentToken("RIGHT_BRACKET", yytext, yyleng); }
"^"                               { lexer.printCurrentToken("BIT_XOR", yytext, yyleng); }
"{"                               { lexer.printCurrentToken("LEFT_BRACE", yytext, yyleng); }
"|"                               { lexer.printCurrentToken("PIPE", yytext, yyleng); }
"}"                               { lexer.printCurrentToken("RIGHT_BRACE", yytext, yyleng); }
"~"                               { lexer.printCurrentToken("TILDE", yytext, yyleng); }


 /* ЗОНА 16 Неизвестные символы и конец файла */

\'                                { lexer.reportCurrentError("unexpected single quote", yytext, yyleng); }
.                                 { lexer.reportCurrentError("unknown character", yytext, yyleng); }

 /* EOF печатается как отдельный маркер, чтобы тестировать конец ввода. */
<<EOF>>                           {
                                      lexer.printEndOfFile();
                                      return 0;
                                  }

%%

/*
 * CLI-точка входа: открывает один .rs-файл, запускает Flex и преобразует накопленный флаг ошибок в документированные коды возврата 0/1/2.
 */
int main(int argc, char** argv)
{
    if (argc == 2 && (std::strcmp(argv[1], "--help") == 0 ||
                      std::strcmp(argv[1], "-h") == 0)) {
        LexerContext::printUsage(argv[0]);
        return 0;
    }

    if (argc != 2) {
        LexerContext::printUsage(argv[0]);
        return 1;
    }

    yyin = std::fopen(argv[1], "rb");
    if (yyin == nullptr) {
        std::fprintf(stderr, "Cannot open source file: %s\n", argv[1]);
        return 1;
    }

    LexerContext lexer(argv[1]);
    yylex(lexer);
    std::fclose(yyin);
    return lexer.hasErrors() ? 2 : 0;
}
