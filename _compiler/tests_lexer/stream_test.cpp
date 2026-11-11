#include "Lexer.h"

#include <cstdio>
#include <iostream>
#include <string>
#include <variant>
#include <vector>

using Kind = TokenKind;

static bool expectKinds(const std::vector<Token>& tokens,
                        const std::vector<Kind>& expected)
{
    if (tokens.size() != expected.size()) {
        std::cerr << "expected " << expected.size() << " tokens, got "
                  << tokens.size() << '\n';
        return false;
    }
    for (std::size_t i = 0; i < expected.size(); ++i) {
        if (tokens[i].kind != expected[i]) {
            std::cerr << "wrong token at index " << i << '\n';
            return false;
        }
    }
    return true;
}

static bool expectString(const Token& token, const std::string& expected)
{
    const auto* value = std::get_if<std::string>(&token.value);
    return value != nullptr && *value == expected;
}

static bool expectInteger(const Token& token, const std::string& spelling,
                          unsigned long long expected)
{
    const auto* value = std::get_if<unsigned long long>(&token.value);
    return token.spelling == spelling && value != nullptr && *value == expected;
}

static bool checkValid(const std::vector<Token>& tokens, const LexerContext& context)
{
    const std::vector<Kind> expected = {
        Kind::FN, Kind::ID, Kind::LEFT_PAREN, Kind::ID, Kind::COLON,
        Kind::ID, Kind::RIGHT_PAREN, Kind::LEFT_BRACE,
        Kind::LET, Kind::ID, Kind::ASSIGN, Kind::RAW_STRING_LITERAL,
        Kind::SEMICOLON,
        Kind::LET, Kind::ID, Kind::ASSIGN, Kind::INTEGER_LITERAL,
        Kind::SEMICOLON,
        Kind::LET, Kind::ID, Kind::ASSIGN, Kind::CHAR_LITERAL,
        Kind::SEMICOLON,
        Kind::ID, Kind::LEFT_PAREN, Kind::ID, Kind::RIGHT_PAREN,
        Kind::SEMICOLON,
        Kind::LET, Kind::ID, Kind::ASSIGN, Kind::INTEGER_LITERAL,
        Kind::SEMICOLON,
        Kind::LET, Kind::ID, Kind::ASSIGN, Kind::INTEGER_LITERAL,
        Kind::SEMICOLON,
        Kind::LET, Kind::ID, Kind::ASSIGN, Kind::INTEGER_LITERAL,
        Kind::SEMICOLON, Kind::RIGHT_BRACE
    };
    if (context.hasErrors() || !expectKinds(tokens, expected)) return false;
    if (!expectString(tokens[1], "demo") ||
        !expectString(tokens[11], "a\\n") ||
        tokens[11].spelling != "r##\"a\\n\"##" ||
        !expectInteger(tokens[16], "0x2Au8", 42ULL) ||
        !expectString(tokens[21], "\n") ||
        !expectInteger(tokens[31], "0b101010u8", 42ULL) ||
        !expectInteger(tokens[36], "0o52u8", 42ULL) ||
        !expectInteger(tokens[41], "42u8", 42ULL)) {
        std::cerr << "a token has an incorrect value or spelling\n";
        return false;
    }
    return true;
}

static bool checkErrors(const std::vector<Token>& tokens, const LexerContext& context)
{
    const std::vector<Kind> expected = {
        Kind::LET, Kind::ID, Kind::ASSIGN, Kind::SEMICOLON,
        Kind::LET, Kind::ID, Kind::ASSIGN, Kind::INTEGER_LITERAL,
        Kind::SEMICOLON,
        Kind::LET, Kind::ID, Kind::ASSIGN, Kind::STRING_LITERAL,
        Kind::SEMICOLON
    };
    return context.errors() == 2 && context.hasErrors() &&
           expectKinds(tokens, expected) &&
           expectString(tokens[12], "ok");
}

static bool checkUnclosed(const std::vector<Token>& tokens,
                          const LexerContext& context)
{
    const std::vector<Kind> expected = {
        Kind::FN, Kind::ID, Kind::LEFT_PAREN, Kind::RIGHT_PAREN,
        Kind::LEFT_BRACE, Kind::RIGHT_BRACE
    };
    return context.errors() == 1 && expectKinds(tokens, expected);
}

int main(int argc, char** argv)
{
    if (argc != 3) return 2;
    FILE* input = std::fopen(argv[2], "rb");
    if (input == nullptr) {
        std::cerr << "cannot open test input\n";
        return 2;
    }

    LexerContext context(argv[2]);
    yyrestart(input);
    std::vector<Token> tokens;
    int kind = 0;
    while ((kind = yylex(context)) != 0) {
        if (kind != static_cast<int>(context.token().kind)) {
            std::cerr << "returned kind and token data disagree\n";
            std::fclose(input);
            return 1;
        }
        tokens.push_back(context.token());
    }
    std::fclose(input);

    const std::string mode(argv[1]);
    const bool passed = mode == "valid" ? checkValid(tokens, context) :
                        mode == "errors" ? checkErrors(tokens, context) :
                        mode == "unclosed" ? checkUnclosed(tokens, context) : false;
    return passed ? 0 : 1;
}
