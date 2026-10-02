#pragma once

#include <cstdio>
#include <string>
#include <string_view>

// Методы для работы с состоянием, объявленным внутри yylex в lex.l.
class LexerContext {
public:
    LexerContext(const char*& sourceName, bool& hadErrors,
                 std::string& accumulatedText, std::string& accumulatedValue,
                 std::string& accumulatedError, const char*& accumulatedKind,
                 bool& accumulatedHasSemanticValue, int& blockCommentDepth,
                 int& rawHashCount);

    bool hasErrors() const;
    static void printUsage(const char* executable);

    void printCurrentToken(const char* kind, const char* text, int length) const;
    void reportCurrentError(std::string_view message, const char* text, int length);
    void printEndOfFile() const;

    void beginBlockComment(const char* text, int length);
    void openNestedBlockComment(const char* text, int length);
    void appendBlockComment(const char* text, int length);
    bool closeBlockComment(const char* text, int length);

    void beginString(const char* text, int length);
    void appendStringText(const char* text, int length);
    void appendStringEscape(const char* text, int length, bool hexEscape = false);
    void appendStringContinuation(const char* text, int length);
    void appendStringError(const char* text, int length, std::string_view message);
    void appendStringCrLf(const char* text, int length);
    void finishString(const char* text, int length);

    void beginRawString(const char* text, int length);
    void appendRawText(const char* text, int length);
    void appendRawCrLf(const char* text, int length);
    void appendRawCarriageReturn(const char* text, int length);
    int rawClosingPrefixLength(const char* text, int length) const;
    void finishRawString(const char* text, int length);

    void reportUnclosedAccumulated(std::string_view message);
    void handleCharacterLiteral(const char* text, int length);
    void handleIntegerLiteral(const char* kind, int base, int prefixLength,
                              const char* text, int length);
    void handleFloatingLiteral(const char* text, int length);

private:
    void reportError(std::string_view message, std::string_view text);
    void beginAccumulated(const char* kind, const char* text, int length,
                          bool hasSemanticValue = false);
    void appendAccumulated(const char* text, int length);
    void markAccumulatedError(std::string_view message);
    void validateStringContent(std::string_view text);
    void finishAccumulated();
    void validateHexEscape(std::string_view escape);

    static void printEscaped(FILE* stream, std::string_view text);
    static void printToken(const char* kind, std::string_view text);
    static void printUnsignedValue(const char* kind, unsigned long long value);
    static void printFloatValue(const char* kind, double value);
    static bool containsNonAscii(std::string_view text);
    static int countOpeningHashes(std::string_view text);
    static bool isHexDigit(char character);
    static unsigned int parseHex(std::string_view text);
    static bool decodeEscape(std::string_view escape, std::string& output);
    static std::string withoutUnderscores(std::string_view text);
    static std::string validateCharacterLiteral(std::string_view literal);
    static std::string characterLiteralValue(std::string_view literal);

    const char*& sourceName;
    bool& hadErrors;

    std::string& accumulatedText;
    std::string& accumulatedValue;
    std::string& accumulatedError;
    const char*& accumulatedKind;
    bool& accumulatedHasSemanticValue;

    int& blockCommentDepth;
    int& rawHashCount;
};
