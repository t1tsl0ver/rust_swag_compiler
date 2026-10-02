#include "LexerContext.h"

#include <cctype>
#include <cerrno>
#include <cstdlib>

LexerContext::LexerContext(const char* name) : sourceName(name) {}

bool LexerContext::hasErrors() const
{
    return hadErrors;
}

void LexerContext::printUsage(const char* executable)
{
    std::printf("Usage: %s <source.rs>\n", executable);
    std::printf("Prints one recognized lexical token per line.\n");
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

void LexerContext::printToken(const char* kind, std::string_view text)
{
    std::printf("%-32s ", kind);
    printEscaped(stdout, text);
    std::fputc('\n', stdout);
}

void LexerContext::printUnsignedValue(const char* kind, unsigned long long value)
{
    std::printf("%-32s %llu\n", kind, value);
}

void LexerContext::printFloatValue(const char* kind, double value)
{
    std::printf("%-32s %.17g\n", kind, value);
}

void LexerContext::printCurrentToken(const char* kind, const char* text, int length) const
{
    printToken(kind, std::string_view(text, static_cast<std::size_t>(length)));
}

void LexerContext::reportError(std::string_view message, std::string_view text)
{
    hadErrors = true;
    std::fprintf(stderr, "%s: lexer error: %.*s: ", sourceName,
                 static_cast<int>(message.size()), message.data());
    printEscaped(stderr, text);
    std::fputc('\n', stderr);
}

void LexerContext::reportCurrentError(std::string_view message,
                                      const char* text, int length)
{
    const std::string_view source(text, static_cast<std::size_t>(length));
    printToken("ERROR", source);
    reportError(message, source);
}

void LexerContext::printEndOfFile() const
{
    printToken("EOF", "");
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

void LexerContext::beginAccumulated(const char* kind, const char* text, int length,
                                    bool hasSemanticValue)
{
    accumulatedKind = kind;
    accumulatedText.assign(text, static_cast<std::size_t>(length));
    accumulatedValue.clear();
    accumulatedError.clear();
    accumulatedHasSemanticValue = hasSemanticValue;
}

void LexerContext::appendAccumulated(const char* text, int length)
{
    accumulatedText.append(text, static_cast<std::size_t>(length));
}

void LexerContext::markAccumulatedError(std::string_view message)
{
    if (accumulatedError.empty()) {
        accumulatedError.assign(message);
    }
}

void LexerContext::validateStringContent(std::string_view text)
{
    if (containsNonAscii(text)) {
        markAccumulatedError("a string literal may contain only ASCII characters");
    }
}

void LexerContext::finishAccumulated()
{
    if (!accumulatedError.empty()) {
        printToken("ERROR", accumulatedText);
        reportError(accumulatedError, accumulatedText);
    } else {
        printToken(accumulatedKind,
                   accumulatedHasSemanticValue ? std::string_view(accumulatedValue)
                                               : std::string_view(accumulatedText));
    }

    accumulatedText.clear();
    accumulatedValue.clear();
    accumulatedError.clear();
    accumulatedKind = nullptr;
    accumulatedHasSemanticValue = false;
}

void LexerContext::reportUnclosedAccumulated(std::string_view message)
{
    printToken("ERROR", accumulatedText);
    reportError(message, accumulatedText);
}

void LexerContext::beginBlockComment(const char* text, int length)
{
    beginAccumulated("BLOCK_COMMENT", text, length);
    blockCommentDepth = 1;
}

void LexerContext::openNestedBlockComment(const char* text, int length)
{
    appendAccumulated(text, length);
    ++blockCommentDepth;
}

void LexerContext::appendBlockComment(const char* text, int length)
{
    appendAccumulated(text, length);
}

bool LexerContext::closeBlockComment(const char* text, int length)
{
    appendAccumulated(text, length);
    --blockCommentDepth;
    if (blockCommentDepth != 0) {
        return false;
    }

    const std::string_view comment(accumulatedText);
    if (comment.rfind("/*!", 0) == 0) {
        accumulatedKind = "INNER_BLOCK_DOC_COMMENT";
    } else if (comment.rfind("/**", 0) == 0 &&
               comment.size() > 3 && comment[3] != '*' && comment[3] != '/') {
        accumulatedKind = "OUTER_BLOCK_DOC_COMMENT";
    }
    finishAccumulated();
    return true;
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

void LexerContext::handleIntegerLiteral(const char* kind, int base, int prefixLength,
                                        const char* text, int length)
{
    const std::string_view source(text, static_cast<std::size_t>(length));
    const std::string normalized = withoutUnderscores(source);
    const char* digits = normalized.c_str() + prefixLength;
    char* end = nullptr;
    errno = 0;
    const unsigned long long value = std::strtoull(digits, &end, base);

    if (end == digits || errno == ERANGE) {
        printToken("ERROR", source);
        reportError("integer literal is outside the supported range", source);
        return;
    }
    printUnsignedValue(kind, value);
}

void LexerContext::handleFloatingLiteral(const char* text, int length)
{
    const std::string_view source(text, static_cast<std::size_t>(length));
    const std::string normalized = withoutUnderscores(source);
    char* end = nullptr;
    errno = 0;
    const double value = std::strtod(normalized.c_str(), &end);

    if (end == normalized.c_str() || errno == ERANGE) {
        printToken("ERROR", source);
        reportError("floating-point literal is outside the supported range", source);
        return;
    }
    printFloatValue("FLOAT_LITERAL", value);
}

void LexerContext::validateHexEscape(std::string_view escape)
{
    if (parseHex(escape.substr(2)) > 0x7FU) {
        markAccumulatedError("a string \\x escape must be in the ASCII range");
    }
}

void LexerContext::beginString(const char* text, int length)
{
    beginAccumulated("STRING_LITERAL", text, length, true);
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
    markAccumulatedError(message);
}

void LexerContext::appendStringCrLf(const char* text, int length)
{
    appendAccumulated(text, length);
    accumulatedValue.push_back('\n');
}

void LexerContext::finishString(const char* text, int length)
{
    appendAccumulated(text, length);
    finishAccumulated();
}

void LexerContext::beginRawString(const char* text, int length)
{
    beginAccumulated("RAW_STRING_LITERAL", text, length, true);
    rawHashCount = countOpeningHashes(accumulatedText);
    if (rawHashCount > 255) {
        markAccumulatedError("raw strings may use at most 255 # characters");
    }
}

void LexerContext::appendRawText(const char* text, int length)
{
    appendAccumulated(text, length);
    accumulatedValue.append(text, static_cast<std::size_t>(length));
    if (containsNonAscii(std::string_view(text, static_cast<std::size_t>(length)))) {
        markAccumulatedError("a string literal may contain only ASCII characters");
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
    markAccumulatedError("carriage return is not allowed in a raw string literal");
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

void LexerContext::finishRawString(const char* text, int length)
{
    appendAccumulated(text, length);
    finishAccumulated();
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

void LexerContext::handleCharacterLiteral(const char* text, int length)
{
    const std::string_view source(text, static_cast<std::size_t>(length));
    const std::string error = validateCharacterLiteral(source);
    if (error.empty()) {
        printToken("CHAR_LITERAL", characterLiteralValue(source));
    } else {
        printToken("ERROR", source);
        reportError(error, source);
    }
}
