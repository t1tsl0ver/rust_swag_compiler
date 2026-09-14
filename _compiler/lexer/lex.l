%option noyywrap
%option never-interactive
%option yylineno
%option nodefault

%x STR
%x RAW_STR
%x ML_COMMENT

%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Вспомогательная функция для подсчёта # в начале raw-строки. */
int countHashes(const char* text)
{
    int count = 0;
    for (int i = 0; text[i] != 0; ++i) {
        if (text[i] == '#') {
            ++count;
        }
    }
    return count;
}
%}

DIGIT           [0-9]
DEC_NUMBER      [0-9][0-9_]*
BIN_NUMBER      0b[_01]*[01][_01]*
OCT_NUMBER      0o[_0-7]*[0-7][_0-7]*
HEX_NUMBER      0x[_0-9a-fA-F]*[0-9a-fA-F][_0-9a-fA-F]*

INT_TYPE        (i8|i16|i32|i64|i128|isize|u8|u16|u32|u64|u128|usize)
FLOAT_TYPE      (f32|f64)
NUMBER_SUFFIX   (_?({INT_TYPE}|{FLOAT_TYPE}))?
EXPONENT        [eE][+-]?[_0-9]*[0-9][_0-9]*

ID              [a-zA-Z_][a-zA-Z0-9_]*
LIFETIME        '[a-zA-Z_][a-zA-Z0-9_]*
RAW_ID          r#[a-zA-Z_][a-zA-Z0-9_]*
RAW_LIFETIME    'r#[a-zA-Z_][a-zA-Z0-9_]*

CHAR_ESCAPE     \\(n|r|t|0|\\|'|\"|x[0-7][0-9a-fA-F]|u\{([0-9a-fA-F]_*){1,6}\})
CHAR_LITERAL    '([^'\\\n\r\t]|{CHAR_ESCAPE})'
BYTE_ESCAPE     \\(n|r|t|0|\\|'|\"|x[0-9a-fA-F]{2})
BYTE_LITERAL    b'([^'\\\n\r\t\x80-\xFF]|{BYTE_ESCAPE})'

%%

%{
    char str[10000];
    int stringType = 0;       /* 0 - String, 1 - Byte string, 2 - C string */
    int rawStringType = 0;    /* 0 - Raw string, 1 - Raw byte, 2 - Raw C */
    int rawHashCount = 0;
    int commentDepth = 0;
    int commentStartLine = 1;
%}

\xEF\xBB\xBF                       { /* UTF-8 BOM пропускается. */ }

^"#!["                              {
                                        yyless(1);
                                        printf("Punctuation: %s\n", yytext);
                                    }
^"#!"[^\n\r]*                     { printf("Shebang: %s\n", yytext); }

[ \t\v\f\r]+                      { /* Пробельные символы пропускаются. */ }
\n                                  { /* yylineno обновляется самим Flex. */ }

"//!"[^\n\r]*                     { printf("Inner line doc comment: %s\n", yytext); }
"///"([^/\n\r][^\n\r]*)?         { printf("Outer line doc comment: %s\n", yytext); }
"//"[^\n\r]*                      { printf("Line comment: %s\n", yytext); }

"/*"                                {
                                        commentDepth = 1;
                                        commentStartLine = yylineno;
                                        BEGIN(ML_COMMENT);
                                    }
<ML_COMMENT>"/*"                    { ++commentDepth; }
<ML_COMMENT>"*/"                    {
                                        --commentDepth;
                                        if (commentDepth == 0) {
                                            printf("Block comment at line %d\n", commentStartLine);
                                            BEGIN(INITIAL);
                                        }
                                    }
<ML_COMMENT>\n                      { /* Перевод строки внутри комментария. */ }
<ML_COMMENT>.                       { /* Содержимое комментария пропускается. */ }
<ML_COMMENT><<EOF>>                 {
                                        printf("Lexer error at line %d: block comment is not closed\n",
                                               commentStartLine);
                                        BEGIN(INITIAL);
                                        return 0;
                                    }

b\"                                  {
                                        BEGIN(STR);
                                        str[0] = 0;
                                        stringType = 1;
                                    }
c\"                                  {
                                        BEGIN(STR);
                                        str[0] = 0;
                                        stringType = 2;
                                    }
\"                                   {
                                        BEGIN(STR);
                                        str[0] = 0;
                                        stringType = 0;
                                    }

<STR>[^"\n\r\\]+                  { strcat(str, yytext); }
<STR>\\n                           { strcat(str, "\n"); }
<STR>\\r                           { strcat(str, "\r"); }
<STR>\\t                           { strcat(str, "\t"); }
<STR>\\0                           { strcat(str, "\\0"); }
<STR>\\\\                         { strcat(str, "\\"); }
<STR>\\\"                         { strcat(str, "\""); }
<STR>\\'                           { strcat(str, "'"); }
<STR>\\x[0-9a-fA-F]{2}            { strcat(str, yytext); }
<STR>\\u\{([0-9a-fA-F]_*){1,6}\} { strcat(str, yytext); }
<STR>\\\n[ \t\r\n]*                { /* Продолжение строки: пробелы пропускаются. */ }
<STR>\n                             { strcat(str, "\n"); }
<STR>\r                             { printf("Lexer error at line %d: CR inside string\n", yylineno); }
<STR>\\.                           { printf("Lexer error at line %d: unknown string escape %s\n", yylineno, yytext); }
<STR>\\                            { printf("Lexer error at line %d: unfinished string escape\n", yylineno); }
<STR>\"                             {
                                        if (stringType == 0) {
                                            printf("String literal: %s\n", str);
                                        } else if (stringType == 1) {
                                            printf("Byte string literal: %s\n", str);
                                        } else {
                                            printf("C string literal: %s\n", str);
                                        }
                                        BEGIN(INITIAL);
                                    }
<STR><<EOF>>                        {
                                        printf("Lexer error at line %d: string is not closed\n", yylineno);
                                        BEGIN(INITIAL);
                                        return 0;
                                    }

br[#]*\"                             {
                                        BEGIN(RAW_STR);
                                        str[0] = 0;
                                        rawStringType = 1;
                                        rawHashCount = countHashes(yytext);
                                    }
cr[#]*\"                             {
                                        BEGIN(RAW_STR);
                                        str[0] = 0;
                                        rawStringType = 2;
                                        rawHashCount = countHashes(yytext);
                                    }
r[#]*\"                              {
                                        BEGIN(RAW_STR);
                                        str[0] = 0;
                                        rawStringType = 0;
                                        rawHashCount = countHashes(yytext);
                                    }

<RAW_STR>[^"\n\r]+                 { strcat(str, yytext); }
<RAW_STR>\n                         { strcat(str, "\n"); }
<RAW_STR>\r                         { printf("Lexer error at line %d: CR inside raw string\n", yylineno); }
<RAW_STR>\"[#]*                     {
                                        int closingHashes = countHashes(yytext);
                                        if (closingHashes == rawHashCount) {
                                            if (rawStringType == 0) {
                                                printf("Raw string literal: %s\n", str);
                                            } else if (rawStringType == 1) {
                                                printf("Raw byte string literal: %s\n", str);
                                            } else {
                                                printf("Raw C string literal: %s\n", str);
                                            }
                                            BEGIN(INITIAL);
                                        } else {
                                            strcat(str, yytext);
                                        }
                                    }
<RAW_STR><<EOF>>                    {
                                        printf("Lexer error at line %d: raw string is not closed\n", yylineno);
                                        BEGIN(INITIAL);
                                        return 0;
                                    }

{BYTE_LITERAL}                       { printf("Byte literal: %s\n", yytext); }
{CHAR_LITERAL}                       { printf("Character literal: %s\n", yytext); }

{RAW_LIFETIME}                       { printf("Raw lifetime: %s\n", yytext); }
{LIFETIME}                           { printf("Lifetime or label: %s\n", yytext); }
{RAW_ID}                             { printf("Raw identifier: %s\n", yytext); }

"_"                                  { printf("Strict keyword: %s\n", yytext); }
"as"                                 { printf("Strict keyword: %s\n", yytext); }
"async"                              { printf("Strict keyword: %s\n", yytext); }
"await"                              { printf("Strict keyword: %s\n", yytext); }
"break"                              { printf("Strict keyword: %s\n", yytext); }
"const"                              { printf("Strict keyword: %s\n", yytext); }
"continue"                           { printf("Strict keyword: %s\n", yytext); }
"crate"                              { printf("Strict keyword: %s\n", yytext); }
"dyn"                                { printf("Strict keyword: %s\n", yytext); }
"else"                               { printf("Strict keyword: %s\n", yytext); }
"enum"                               { printf("Strict keyword: %s\n", yytext); }
"extern"                             { printf("Strict keyword: %s\n", yytext); }
"false"                              { printf("Boolean literal: %s\n", yytext); }
"fn"                                 { printf("Strict keyword: %s\n", yytext); }
"for"                                { printf("Strict keyword: %s\n", yytext); }
"if"                                 { printf("Strict keyword: %s\n", yytext); }
"impl"                               { printf("Strict keyword: %s\n", yytext); }
"in"                                 { printf("Strict keyword: %s\n", yytext); }
"let"                                { printf("Strict keyword: %s\n", yytext); }
"loop"                               { printf("Strict keyword: %s\n", yytext); }
"match"                              { printf("Strict keyword: %s\n", yytext); }
"mod"                                { printf("Strict keyword: %s\n", yytext); }
"move"                               { printf("Strict keyword: %s\n", yytext); }
"mut"                                { printf("Strict keyword: %s\n", yytext); }
"pub"                                { printf("Strict keyword: %s\n", yytext); }
"ref"                                { printf("Strict keyword: %s\n", yytext); }
"return"                             { printf("Strict keyword: %s\n", yytext); }
"self"                               { printf("Strict keyword: %s\n", yytext); }
"Self"                               { printf("Strict keyword: %s\n", yytext); }
"static"                             { printf("Strict keyword: %s\n", yytext); }
"struct"                             { printf("Strict keyword: %s\n", yytext); }
"super"                              { printf("Strict keyword: %s\n", yytext); }
"trait"                              { printf("Strict keyword: %s\n", yytext); }
"true"                               { printf("Boolean literal: %s\n", yytext); }
"type"                               { printf("Strict keyword: %s\n", yytext); }
"unsafe"                             { printf("Strict keyword: %s\n", yytext); }
"use"                                { printf("Strict keyword: %s\n", yytext); }
"where"                              { printf("Strict keyword: %s\n", yytext); }
"while"                              { printf("Strict keyword: %s\n", yytext); }

"abstract"                           { printf("Reserved keyword: %s\n", yytext); }
"become"                             { printf("Reserved keyword: %s\n", yytext); }
"box"                                { printf("Reserved keyword: %s\n", yytext); }
"do"                                 { printf("Reserved keyword: %s\n", yytext); }
"final"                              { printf("Reserved keyword: %s\n", yytext); }
"gen"                                { printf("Reserved keyword: %s\n", yytext); }
"macro"                              { printf("Reserved keyword: %s\n", yytext); }
"override"                           { printf("Reserved keyword: %s\n", yytext); }
"priv"                               { printf("Reserved keyword: %s\n", yytext); }
"try"                                { printf("Reserved keyword: %s\n", yytext); }
"typeof"                             { printf("Reserved keyword: %s\n", yytext); }
"unsized"                            { printf("Reserved keyword: %s\n", yytext); }
"virtual"                            { printf("Reserved keyword: %s\n", yytext); }
"yield"                              { printf("Reserved keyword: %s\n", yytext); }

"macro_rules"                        { printf("Weak keyword: %s\n", yytext); }
"raw"                                { printf("Weak keyword: %s\n", yytext); }
"safe"                               { printf("Weak keyword: %s\n", yytext); }
"union"                              { printf("Weak keyword: %s\n", yytext); }

"bool"                               { printf("Boolean type: %s\n", yytext); }
"char"                               { printf("Character type: %s\n", yytext); }
"str"                                { printf("String slice type: %s\n", yytext); }
"String"                             { printf("String type: %s\n", yytext); }
"i8"                                 { printf("Signed integer type: %s\n", yytext); }
"i16"                                { printf("Signed integer type: %s\n", yytext); }
"i32"                                { printf("Signed integer type: %s\n", yytext); }
"i64"                                { printf("Signed integer type: %s\n", yytext); }
"i128"                               { printf("Signed integer type: %s\n", yytext); }
"isize"                              { printf("Signed integer type: %s\n", yytext); }
"u8"                                 { printf("Unsigned integer type: %s\n", yytext); }
"u16"                                { printf("Unsigned integer type: %s\n", yytext); }
"u32"                                { printf("Unsigned integer type: %s\n", yytext); }
"u64"                                { printf("Unsigned integer type: %s\n", yytext); }
"u128"                               { printf("Unsigned integer type: %s\n", yytext); }
"usize"                              { printf("Unsigned integer type: %s\n", yytext); }
"f32"                                { printf("Floating-point type: %s\n", yytext); }
"f64"                                { printf("Floating-point type: %s\n", yytext); }

{DEC_NUMBER}(\.{DEC_NUMBER})?{EXPONENT}{NUMBER_SUFFIX} {
                                        printf("Floating-point literal: %s\n", yytext);
                                    }
{DEC_NUMBER}\.{DEC_NUMBER}{NUMBER_SUFFIX} {
                                        printf("Floating-point literal: %s\n", yytext);
                                    }
{DEC_NUMBER}\.\.                    {
                                        yyless(yyleng - 2);
                                        printf("Decimal integer literal: %s\n", yytext);
                                    }
{DEC_NUMBER}\.[a-zA-Z_]              {
                                        yyless(yyleng - 2);
                                        printf("Decimal integer literal: %s\n", yytext);
                                    }
{DEC_NUMBER}\.                       { printf("Floating-point literal: %s\n", yytext); }
{BIN_NUMBER}{NUMBER_SUFFIX}           { printf("Binary integer literal: %s\n", yytext); }
{OCT_NUMBER}{NUMBER_SUFFIX}           { printf("Octal integer literal: %s\n", yytext); }
{HEX_NUMBER}{NUMBER_SUFFIX}           { printf("Hexadecimal integer literal: %s\n", yytext); }
{DEC_NUMBER}{NUMBER_SUFFIX}           { printf("Decimal integer literal: %s\n", yytext); }

"..."                                { printf("Punctuation: %s\n", yytext); }
"..="                                { printf("Range inclusive operator: %s\n", yytext); }
"<<="                                { printf("Left shift assignment operator: %s\n", yytext); }
">>="                                { printf("Right shift assignment operator: %s\n", yytext); }
"!="                                 { printf("Not equal operator: %s\n", yytext); }
"%="                                 { printf("Remainder assignment operator: %s\n", yytext); }
"&&"                                 { printf("Logical AND operator: %s\n", yytext); }
"&="                                 { printf("Bitwise AND assignment operator: %s\n", yytext); }
"*="                                 { printf("Multiplication assignment operator: %s\n", yytext); }
"+="                                 { printf("Addition assignment operator: %s\n", yytext); }
"-="                                 { printf("Subtraction assignment operator: %s\n", yytext); }
"->"                                 { printf("Right arrow: %s\n", yytext); }
".."                                 { printf("Range operator: %s\n", yytext); }
"/="                                 { printf("Division assignment operator: %s\n", yytext); }
"::"                                 { printf("Path separator: %s\n", yytext); }
"<-"                                 { printf("Left arrow: %s\n", yytext); }
"<<"                                 { printf("Left shift operator: %s\n", yytext); }
"<="                                 { printf("Less or equal operator: %s\n", yytext); }
"=="                                 { printf("Equal operator: %s\n", yytext); }
"=>"                                 { printf("Fat arrow: %s\n", yytext); }
">="                                 { printf("Greater or equal operator: %s\n", yytext); }
">>"                                 { printf("Right shift operator: %s\n", yytext); }
"^="                                 { printf("Bitwise XOR assignment operator: %s\n", yytext); }
"|="                                 { printf("Bitwise OR assignment operator: %s\n", yytext); }
"||"                                 { printf("Logical OR operator: %s\n", yytext); }

"!"                                  { printf("Punctuation: %s\n", yytext); }
"#"                                  { printf("Punctuation: %s\n", yytext); }
"$"                                  { printf("Punctuation: %s\n", yytext); }
"%"                                  { printf("Remainder operator: %s\n", yytext); }
"&"                                  { printf("Reference or bitwise AND: %s\n", yytext); }
"("                                  { printf("Left parenthesis: %s\n", yytext); }
")"                                  { printf("Right parenthesis: %s\n", yytext); }
"*"                                  { printf("Multiplication or dereference: %s\n", yytext); }
"+"                                  { printf("Addition operator: %s\n", yytext); }
","                                  { printf("Comma: %s\n", yytext); }
"-"                                  { printf("Subtraction operator: %s\n", yytext); }
"."                                  { printf("Dot: %s\n", yytext); }
"/"                                  { printf("Division operator: %s\n", yytext); }
":"                                  { printf("Colon: %s\n", yytext); }
";"                                  { printf("Semicolon: %s\n", yytext); }
"<"                                  { printf("Less-than operator: %s\n", yytext); }
"="                                  { printf("Assignment operator: %s\n", yytext); }
">"                                  { printf("Greater-than operator: %s\n", yytext); }
"?"                                  { printf("Question mark: %s\n", yytext); }
"@"                                  { printf("At sign: %s\n", yytext); }
"["                                  { printf("Left square bracket: %s\n", yytext); }
"]"                                  { printf("Right square bracket: %s\n", yytext); }
"^"                                  { printf("Bitwise XOR operator: %s\n", yytext); }
"{"                                  { printf("Left brace: %s\n", yytext); }
"|"                                  { printf("Bitwise OR or closure separator: %s\n", yytext); }
"}"                                  { printf("Right brace: %s\n", yytext); }
"~"                                  { printf("Tilde: %s\n", yytext); }

{ID}                                 { printf("Identifier: %s\n", yytext); }

.                                    {
                                        printf("Lexer error at line %d: unknown character %s\n",
                                               yylineno, yytext);
                                    }

%%

int main(int argc, char** argv)
{
    if (argc != 2) {
        printf("Usage: %s <source.rs>\n", argv[0]);
        return 1;
    }

    yyin = fopen(argv[1], "rb");
    if (yyin == NULL) {
        printf("Cannot open file: %s\n", argv[1]);
        return 1;
    }

    yylex();
    fclose(yyin);
    return 0;
}
