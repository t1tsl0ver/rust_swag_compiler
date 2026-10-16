#pragma once

#include "Token.h"

#include <cstdio>
#include <string>
#include <string_view>

class LexerContext {
public:
    explicit LexerContext(std::string sourceName);

    const Token& token() const { return currentToken; }
    bool hasErrors() const { return errorCount != 0; }
    unsigned int errors() const { return errorCount; }

    int emitToken(TokenKind kind, const char* text, int length,
                  TokenValue value = {});
    void reportCurrentError(std::string_view message, const char* text, int length);

    void beginBlockComment();
    void enterNestedBlockComment();
    bool leaveBlockComment();
    void reportUnclosedBlockComment();

    void beginString(const char* text, int length);
    void appendStringText(const char* text, int length);
    void appendStringEscape(const char* text, int length, bool hexEscape = false);
    void appendStringContinuation(const char* text, int length);
    void appendStringError(const char* text, int length, std::string_view message);
    void appendStringCrLf(const char* text, int length);
    int finishString(const char* text, int length);

    void beginRawString(const char* text, int length);
    void appendRawText(const char* text, int length);
    void appendRawCrLf(const char* text, int length);
    void appendRawCarriageReturn(const char* text, int length);
    int rawClosingPrefixLength(const char* text, int length) const;
    int finishRawString(const char* text, int length);

    void reportUnclosedAccumulated(std::string_view message);
    int handleCharacterLiteral(const char* text, int length);
    int handleIntegerLiteral(TokenKind kind, int base, int prefixLength,
                             const char* text, int length);
    int handleFloatingLiteral(const char* text, int length);

private:
    void reportError(std::string_view message, std::string_view text);
    void beginAccumulated(TokenKind kind, const char* text, int length);
    void appendAccumulated(const char* text, int length);
    void rejectAccumulated(std::string_view message, std::string_view text);
    void validateStringContent(std::string_view text);
    int finishAccumulated();
    void validateHexEscape(std::string_view escape);

    static void printEscaped(FILE* stream, std::string_view text);
    static bool containsNonAscii(std::string_view text);
    static int countOpeningHashes(std::string_view text);
    static bool isHexDigit(char character);
    static unsigned int parseHex(std::string_view text);
    static bool decodeEscape(std::string_view escape, std::string& output);
    static std::string withoutUnderscores(std::string_view text);
    static std::string validateCharacterLiteral(std::string_view literal);
    static std::string characterLiteralValue(std::string_view literal);

    std::string sourceName;
    Token currentToken;
    unsigned int errorCount = 0;
    std::string accumulatedText;
    std::string accumulatedValue;
    TokenKind accumulatedKind = TokenKind::End;
    bool accumulatedValid = true;
    int blockCommentDepth = 0;
    int rawHashCount = 0;
};
