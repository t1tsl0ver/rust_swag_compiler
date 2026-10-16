#include "LexerContext.h"

#include <cctype>
#include <cerrno>
#include <cstdlib>
#include <utility>

LexerContext::LexerContext(std::string sourceName)
    : sourceName(std::move(sourceName))
{
}

void LexerContext::printEscaped(FILE* stream, std::string_view text)
{
    std::fputc('"', stream);
    for (const unsigned char character : text) {
        switch (character) {
        case '\\': std::fputs("\\\\", stream); break;
        case '"':  std::fputs("\\\"", stream); break;
        case '\n': std::fputs("\\n", stream); break;
        case '\r': std::fputs("\\r", stream); break;
        case '\t': std::fputs("\\t", stream); break;
        default:
            if (character < 0x20U || character == 0x7FU) {
                std::fprintf(stream, "\\x%02X", static_cast<unsigned int>(character));
            } else {
                std::fputc(character, stream);
            }
        }
    }
    std::fputc('"', stream);
}

int LexerContext::emitToken(TokenKind kind, const char* text, int length,
                            TokenValue value)
{
    currentToken.kind = kind;
    currentToken.spelling.assign(text, static_cast<std::size_t>(length));
    if (kind == TokenKind::ID) {
        value = currentToken.spelling;
    } else if (kind == TokenKind::RAW_IDENTIFIER) {
        value = currentToken.spelling.substr(2);
    }
    currentToken.value = std::move(value);
    return static_cast<int>(kind);
}

void LexerContext::beginBlockComment()
{
    blockCommentDepth = 1;
}

void LexerContext::enterNestedBlockComment()
{
    ++blockCommentDepth;
}

bool LexerContext::leaveBlockComment()
{
    return --blockCommentDepth == 0;
}

void LexerContext::reportError(std::string_view message, std::string_view text)
{
    ++errorCount;
    std::fprintf(stderr, "%s: lexer error: %.*s: ", sourceName.c_str(),
                 static_cast<int>(message.size()), message.data());
    printEscaped(stderr, text);
    std::fputc('\n', stderr);
}

void LexerContext::reportCurrentError(std::string_view message,
                                      const char* text, int length)
{
    const std::string_view source(text, static_cast<std::size_t>(length));
    reportError(message, source);
}

bool LexerContext::containsNonAscii(std::string_view text)
{
    for (const unsigned char character : text) {
        if (character >= 0x80U) {
            return true;
        }
    }
    return false;
}

int LexerContext::countOpeningHashes(std::string_view text)
{
    int count = 0;
    for (const char character : text) {
        if (character == '#') {
            ++count;
        }
    }
    return count;
}

void LexerContext::beginAccumulated(TokenKind kind, const char* text, int length)
{
    accumulatedKind = kind;
    accumulatedText.assign(text, static_cast<std::size_t>(length));
    accumulatedValue.clear();
    accumulatedValid = true;
}

void LexerContext::appendAccumulated(const char* text, int length)
{
    accumulatedText.append(text, static_cast<std::size_t>(length));
}

void LexerContext::rejectAccumulated(std::string_view message, std::string_view text)
{
    reportError(message, text);
    accumulatedValid = false;
}

void LexerContext::validateStringContent(std::string_view text)
{
    if (containsNonAscii(text)) {
        rejectAccumulated("a string literal may contain only ASCII characters", text);
    }
}

int LexerContext::finishAccumulated()
{
    int result = 0;
    if (accumulatedValid) {
        result = emitToken(accumulatedKind, accumulatedText.data(),
                           static_cast<int>(accumulatedText.size()), accumulatedValue);
    }

    accumulatedText.clear();
    accumulatedValue.clear();
    accumulatedKind = TokenKind::End;
    accumulatedValid = true;
    return result;
}

void LexerContext::reportUnclosedAccumulated(std::string_view message)
{
    reportError(message, accumulatedText);
}

void LexerContext::reportUnclosedBlockComment()
{
    ++errorCount;
    std::fprintf(stderr, "%s: lexer error: block comment is not closed\n",
                 sourceName.c_str());
}

bool LexerContext::isHexDigit(char character)
{
    return std::isxdigit(static_cast<unsigned char>(character)) != 0;
}

unsigned int LexerContext::parseHex(std::string_view text)
{
    unsigned int value = 0;
    for (const char character : text) {
        value *= 16U;
        if (character >= '0' && character <= '9') {
            value += static_cast<unsigned int>(character - '0');
        } else if (character >= 'a' && character <= 'f') {
            value += 10U + static_cast<unsigned int>(character - 'a');
        } else {
            value += 10U + static_cast<unsigned int>(character - 'A');
        }
    }
    return value;
}

bool LexerContext::decodeEscape(std::string_view escape, std::string& output)
{
    if (escape.size() == 2) {
        switch (escape[1]) {
        case 'n': output.push_back('\n'); return true;
        case 'r': output.push_back('\r'); return true;
        case 't': output.push_back('\t'); return true;
        case '0': output.push_back('\0'); return true;
        case '\\': output.push_back('\\'); return true;
        case '\'': output.push_back('\''); return true;
        case '"': output.push_back('"'); return true;
        default: return false;
        }
    }
    if (escape.size() == 4 && escape[1] == 'x') {
        output.push_back(static_cast<char>(parseHex(escape.substr(2))));
        return true;
    }
    return false;
}

std::string LexerContext::withoutUnderscores(std::string_view text)
{
    std::string result;
    result.reserve(text.size());
    for (const char character : text) {
        if (character != '_') {
            result.push_back(character);
        }
    }
    return result;
}

int LexerContext::handleIntegerLiteral(TokenKind kind, int base, int prefixLength,
                                       const char* text, int length)
{
    const std::string_view source(text, static_cast<std::size_t>(length));
    const std::string normalized = withoutUnderscores(source);
    const char* digits = normalized.c_str() + prefixLength;
    char* end = nullptr;
    errno = 0;
    const unsigned long long value = std::strtoull(digits, &end, base);

    if (end == digits || errno == ERANGE) {
        reportError("integer literal is outside the supported range", source);
        return 0;
    }
    return emitToken(kind, text, length, value);
}

int LexerContext::handleFloatingLiteral(const char* text, int length)
{
    const std::string_view source(text, static_cast<std::size_t>(length));
    const std::string normalized = withoutUnderscores(source);
    char* end = nullptr;
    errno = 0;
    const double value = std::strtod(normalized.c_str(), &end);

    if (end == normalized.c_str() || errno == ERANGE) {
        reportError("floating-point literal is outside the supported range", source);
        return 0;
    }
    return emitToken(TokenKind::FLOAT_LITERAL, text, length, value);
}

void LexerContext::validateHexEscape(std::string_view escape)
{
    if (parseHex(escape.substr(2)) > 0x7FU) {
        rejectAccumulated("a string \\x escape must be in the ASCII range", escape);
    }
}

void LexerContext::beginString(const char* text, int length)
{
    beginAccumulated(TokenKind::STRING_LITERAL, text, length);
}

void LexerContext::appendStringText(const char* text, int length)
{
    appendAccumulated(text, length);
    accumulatedValue.append(text, static_cast<std::size_t>(length));
    validateStringContent(std::string_view(text, static_cast<std::size_t>(length)));
}

void LexerContext::appendStringEscape(const char* text, int length, bool hexEscape)
{
    appendAccumulated(text, length);
    const std::string_view escape(text, static_cast<std::size_t>(length));
    decodeEscape(escape, accumulatedValue);
    if (hexEscape) {
        validateHexEscape(escape);
    }
}

void LexerContext::appendStringContinuation(const char* text, int length)
{
    appendAccumulated(text, length);
}

void LexerContext::appendStringError(const char* text, int length,
                                     std::string_view message)
{
    appendAccumulated(text, length);
    rejectAccumulated(message, std::string_view(text, static_cast<std::size_t>(length)));
}

void LexerContext::appendStringCrLf(const char* text, int length)
{
    appendAccumulated(text, length);
    accumulatedValue.push_back('\n');
}

int LexerContext::finishString(const char* text, int length)
{
    appendAccumulated(text, length);
    return finishAccumulated();
}

void LexerContext::beginRawString(const char* text, int length)
{
    beginAccumulated(TokenKind::RAW_STRING_LITERAL, text, length);
    rawHashCount = countOpeningHashes(accumulatedText);
    if (rawHashCount > 255) {
        rejectAccumulated("raw strings may use at most 255 # characters", accumulatedText);
    }
}

void LexerContext::appendRawText(const char* text, int length)
{
    appendAccumulated(text, length);
    accumulatedValue.append(text, static_cast<std::size_t>(length));
    if (containsNonAscii(std::string_view(text, static_cast<std::size_t>(length)))) {
        rejectAccumulated("a string literal may contain only ASCII characters",
                          std::string_view(text, static_cast<std::size_t>(length)));
    }
}

void LexerContext::appendRawCrLf(const char* text, int length)
{
    appendAccumulated(text, length);
    accumulatedValue.push_back('\n');
}

void LexerContext::appendRawCarriageReturn(const char* text, int length)
{
    appendAccumulated(text, length);
    accumulatedValue.append(text, static_cast<std::size_t>(length));
    rejectAccumulated("carriage return is not allowed in a raw string literal",
                      std::string_view(text, static_cast<std::size_t>(length)));
}

int LexerContext::rawClosingPrefixLength(const char* text, int length) const
{
    int closingHashes = 0;
    while (1 + closingHashes < length && text[1 + closingHashes] == '#') {
        ++closingHashes;
    }
    if (closingHashes < rawHashCount) {
        return -1;
    }
    return closingHashes > rawHashCount ? 1 + rawHashCount : length;
}

int LexerContext::finishRawString(const char* text, int length)
{
    appendAccumulated(text, length);
    return finishAccumulated();
}

std::string LexerContext::validateCharacterLiteral(std::string_view literal)
{
    const std::size_t contentStart = 1U;
    std::size_t closingQuote = contentStart;
    bool escaped = false;
    for (; closingQuote < literal.size(); ++closingQuote) {
        const char character = literal[closingQuote];
        if (!escaped && character == '\'') {
            break;
        }
        if (!escaped && character == '\\') {
            escaped = true;
        } else {
            escaped = false;
        }
    }
    if (closingQuote == literal.size()) {
        return "character literal is not closed";
    }

    const std::string_view content = literal.substr(contentStart, closingQuote - contentStart);
    if (content.empty()) {
        return "character literal is empty";
    }
    if (content.front() == '\\') {
        if (content.size() == 2 &&
            std::string_view("nrt0\\'\"").find(content[1]) != std::string_view::npos) {
            return {};
        }
        if (content.size() == 4 && content[1] == 'x' &&
            isHexDigit(content[2]) && isHexDigit(content[3])) {
            if (parseHex(content.substr(2)) > 0x7FU) {
                return "a character \\x escape must be in the ASCII range";
            }
            return {};
        }
        return "unknown character escape";
    }
    if (containsNonAscii(content)) {
        return "a character literal may contain only an ASCII character";
    }
    if (content.size() != 1) {
        return "a character literal must contain exactly one ASCII character";
    }
    if (content.front() == '\t') {
        return "a tab must be escaped in a character literal";
    }
    return {};
}

std::string LexerContext::characterLiteralValue(std::string_view literal)
{
    const std::size_t contentStart = 1U;
    std::size_t closingQuote = contentStart;
    bool escaped = false;
    for (; closingQuote < literal.size(); ++closingQuote) {
        if (!escaped && literal[closingQuote] == '\'') {
            break;
        }
        if (!escaped && literal[closingQuote] == '\\') {
            escaped = true;
        } else {
            escaped = false;
        }
    }

    const std::string_view content = literal.substr(contentStart, closingQuote - contentStart);
    std::string value;
    if (content.front() == '\\') {
        decodeEscape(content, value);
    } else {
        value.assign(content);
    }
    return value;
}

int LexerContext::handleCharacterLiteral(const char* text, int length)
{
    const std::string_view source(text, static_cast<std::size_t>(length));
    const std::string error = validateCharacterLiteral(source);
    if (error.empty()) {
        return emitToken(TokenKind::CHAR_LITERAL, text, length,
                         characterLiteralValue(source));
    } else {
        reportError(error, source);
        return 0;
    }
}
