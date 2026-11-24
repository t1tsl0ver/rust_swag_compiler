#include "Parser.h"

#include "Lexer.h"
#include "rust_parser.hpp"

#include <cstdio>
#include <mutex>

namespace {

int parserToken(TokenKind kind)
{
#define MAP(name) case TokenKind::name: return name
    switch (kind) {
    MAP(AS); MAP(BREAK); MAP(CONST); MAP(CONTINUE); MAP(CRATE);
    MAP(ELSE); MAP(ENUM); MAP(FN); MAP(FOR); MAP(IF); MAP(IMPL);
    MAP(IN); MAP(LET); MAP(LOOP); MAP(MOD); MAP(MUT); MAP(PUB);
    MAP(RETURN); MAP(SELF_TYPE); MAP(SELF_VALUE); MAP(STRUCT);
    MAP(SUPER); MAP(TRAIT); MAP(WHILE); MAP(ID);
    MAP(INTEGER_LITERAL); MAP(FLOAT_LITERAL); MAP(STRING_LITERAL);
    MAP(RAW_STRING_LITERAL); MAP(CHAR_LITERAL);
    MAP(LEFT_PAREN); MAP(RIGHT_PAREN); MAP(LEFT_BRACE); MAP(RIGHT_BRACE);
    MAP(LEFT_BRACKET); MAP(RIGHT_BRACKET); MAP(SEMICOLON); MAP(COMMA);
    MAP(COLON); MAP(PATH_SEPARATOR); MAP(DOT); MAP(QUESTION);
    MAP(ASSIGN); MAP(PLUS); MAP(MINUS); MAP(STAR); MAP(SLASH);
    MAP(REMAINDER); MAP(BANG); MAP(AMPERSAND); MAP(LESS);
    MAP(GREATER); MAP(EQUAL_EQUAL); MAP(NOT_EQUAL); MAP(LESS_EQUAL);
    MAP(GREATER_EQUAL); MAP(LOGICAL_AND); MAP(LOGICAL_OR);
    MAP(RIGHT_ARROW); MAP(RANGE);
    case TokenKind::TRUE:
    case TokenKind::FALSE:
        return BOOLEAN_LITERAL;
    case TokenKind::RAW_IDENTIFIER:
        return ID;
    default:
        return YYUNDEF;
    }
#undef MAP
}

}

int yylex(YYSTYPE* value, LexerContext& lexer)
{
    if (yylex(lexer) == 0) {
        return YYEOF;
    }
    const Token& token = lexer.token();
    const int kind = parserToken(token.kind);
    switch (kind) {
    case ID:
        value->name = new ast::Name{
            std::get<std::string>(token.value), token.kind == TokenKind::RAW_IDENTIFIER};
        break;
    case INTEGER_LITERAL:
    case FLOAT_LITERAL:
    case BOOLEAN_LITERAL:
    case STRING_LITERAL:
    case RAW_STRING_LITERAL:
    case CHAR_LITERAL:
        value->literal = new Token(token);
        break;
    }
    return kind;
}

void yyerror(LexerContext&, syntax::ParseResult& result, const char* message)
{
    if (result.error.empty()) {
        result.error = message;
    }
}

namespace syntax {

ParseResult parseFile(const std::string& filename)
{
    ParseResult result;
    const std::unique_ptr<FILE, decltype(&std::fclose)> input(
        std::fopen(filename.c_str(), "rb"), std::fclose);
    if (!input) {
        result.error = "cannot open input file: " + filename;
        return result;
    }

    LexerContext lexer(filename);
    static std::mutex parserMutex;
    const std::lock_guard<std::mutex> lock(parserMutex);
    lexerRestart(input.get());
    const int parseStatus = yyparse(lexer, result);
    result.lexerErrors = lexer.errors();
    if (parseStatus != 0 || result.lexerErrors != 0) {
        result.tree.reset();
        if (result.error.empty()) {
            result.error = "lexical analysis failed";
        }
    }
    return result;
}

}