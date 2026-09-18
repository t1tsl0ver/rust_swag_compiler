%option noyywrap
%option never-interactive
%option nodefault
%option nounistd
%option noinput
%option nounput

%x STRING
%x RAW_STRING
%x BLOCK_COMMENT
%x BYTE_CHAR

%{
#include <cctype>
#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <string_view>

/*
 * ЛЕКСЕР RUST-ПОДОБНОГО ЯЗЫКА: КАРТА ФАЙЛА
 * =========================================
 *
 * Что уже реализовано:
 *   1. BOM, shebang и все виды пробельных символов из Rust Reference.
 *   2. Обычные, документационные и вложенные блочные комментарии.
 *   3. Обычные, byte-, C- и raw-строки с вычислением их значений.
 *   4. Символьные и byte-литералы.
 *   5. Идентификаторы, raw-идентификаторы, lifetime и raw-lifetime.
 *   6. Strict/reserved keywords отдельными правилами; контекстные слова — ID.
 *   7. Целые числа 2/8/10/16 систем, числа с плавающей точкой и суффиксы.
 *   8. Полный набор знаков пунктуации из лексической грамматики Rust.
 *   9. Координаты начала токена и ненулевой код возврата при ошибках.
 *
 * Что намеренно оставлено на следующие этапы:
 *   - точные Unicode 17 XID_Start/XID_Continue и NFC-нормализация;
 *   - проверка допустимости суффикса в конкретном выражении (задача парсера);
 *   - превращение doc-комментариев в атрибуты;
 *   - передача токенов и уже вычисленных semantic values в будущий парсер.
 *
 * Сейчас это самостоятельный диагностический сканер: emitToken() печатает
 * найденные токены. При подключении Bison именно вызовы emitToken() будут
 * заменены/дополнены возвратом TOKEN и заполнением semantic value.
 */

/* ---------------- Состояние позиции и текущей составной лексемы --------- */

static int currentLine = 1;
static int currentColumn = 1;
static int matchLine = 1;
static int matchColumn = 1;
static bool hadErrors = false;
static const char* sourceName = "<input>";

static std::string accumulatedText;
static std::string accumulatedValue;
static std::string accumulatedError;
static const char* accumulatedKind = nullptr;
static bool accumulatedHasSemanticValue = false;
static int accumulatedLine = 1;
static int accumulatedColumn = 1;

static int blockCommentDepth = 0;
static int rawHashCount = 0;

/* Вид накапливаемой строки определяет допустимые символы и escape-правила. */
enum class StringFlavor {
    Normal,
    Byte,
    C,
    Raw,
    RawByte,
    RawC,
};

static StringFlavor stringFlavor = StringFlavor::Normal;

/*
 * Простая система координат: перевод строки увеличивает номер строки,
 * остальные байты увеличивают колонку. Для лабораторного лексера этого
 * достаточно, а точные Unicode-координаты сможет добавить диагностика позже.
 */
static void advancePosition(const char* text, int length)
{
    for (int i = 0; i < length; ++i) {
        if (text[i] == '\n') {
            ++currentLine;
            currentColumn = 1;
        } else {
            ++currentColumn;
        }
    }
}

/* Запоминает начало совпадения Flex и заранее вычисляет позицию после него. */
static void beginMatch(const char* text, int length)
{
    matchLine = currentLine;
    matchColumn = currentColumn;
    advancePosition(text, length);
}

/* YY_USER_ACTION runs before every Flex action. */
#define YY_USER_ACTION do { beginMatch(yytext, yyleng); } while (0);

/*
 * Исправляет позицию после yyless(), когда Flex возвращает хвост совпадения
 * обратно во входной поток (используется для shebang и raw-строк).
 */
static void keepMatchedPrefix(const char* text, int length)
{
    currentLine = matchLine;
    currentColumn = matchColumn;
    advancePosition(text, length);
}

/* Печатает текст токена в одну строку, экранируя служебные символы. */
static void printEscaped(FILE* stream, std::string_view text)
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

/* Единая точка диагностического вывода корректно распознанного токена. */
static void emitToken(const char* kind, std::string_view text, int line, int column)
{
    std::printf("%d:%d  %-32s ", line, column, kind);
    printEscaped(stdout, text);
    std::fputc('\n', stdout);
}

/* Числовые semantic values печатаются числами, без строковых кавычек. */
static void emitUnsignedValue(const char* kind, unsigned long long value,
                              int line, int column)
{
    std::printf("%d:%d  %-32s %llu\n", line, column, kind, value);
}

static void emitFloatValue(const char* kind, double value,
                           int line, int column)
{
    std::printf("%d:%d  %-32s %.17g\n", line, column, kind, value);
}

/* Печатает текущее совпадение yytext с координатами, сохранёнными Flex. */
static void emitCurrentToken(const char* kind)
{
    emitToken(kind, std::string_view(yytext, static_cast<std::size_t>(yyleng)),
              matchLine, matchColumn);
}

/* Регистрирует ошибку, чтобы main вернул код 2, и выводит её в stderr. */
static void reportError(std::string_view message, std::string_view text,
                        int line, int column)
{
    hadErrors = true;
    std::fprintf(stderr, "%s:%d:%d: lexer error: %.*s: ", sourceName, line,
                 column, static_cast<int>(message.size()), message.data());
    printEscaped(stderr, text);
    std::fputc('\n', stderr);
}

/* Выводит текущее совпадение как ERROR и создаёт связанную диагностику. */
static void emitCurrentError(std::string_view message)
{
    const std::string_view text(yytext, static_cast<std::size_t>(yyleng));
    emitToken("ERROR", text, matchLine, matchColumn);
    reportError(message, text, matchLine, matchColumn);
}

/* Проверяет, присутствуют ли во фрагменте байты вне ASCII (0x00..0x7F). */
static bool containsNonAscii(std::string_view text)
{
    for (const unsigned char character : text) {
        if (character >= 0x80U) {
            return true;
        }
    }
    return false;
}

/* Ищет нулевой байт, запрещённый внутри C-строк. */
static bool containsNul(std::string_view text)
{
    return text.find('\0') != std::string_view::npos;
}

/* Считает # в открывающей части raw-строки: r###", br###" или cr###". */
static int countOpeningHashes(std::string_view text)
{
    int count = 0;
    for (const char character : text) {
        if (character == '#') {
            ++count;
        }
    }
    return count;
}

/*
 * Начинает накапливать лексему, которую нельзя получить одним regex-правилом:
 * строку, raw-строку, блочный комментарий или незавершённый byte-символ.
 */
static void beginAccumulated(const char* kind, StringFlavor flavor,
                             const char* text, int length,
                             bool hasSemanticValue = false)
{
    accumulatedKind = kind;
    stringFlavor = flavor;
    accumulatedText.assign(text, static_cast<std::size_t>(length));
    accumulatedValue.clear();
    accumulatedError.clear();
    accumulatedHasSemanticValue = hasSemanticValue;
    accumulatedLine = matchLine;
    accumulatedColumn = matchColumn;
}

/* Добавляет очередное совпадение Flex к составной лексеме. */
static void appendAccumulated(const char* text, int length)
{
    accumulatedText.append(text, static_cast<std::size_t>(length));
}

/* Сохраняет первую ошибку внутри составной лексемы, не теряя её полный текст. */
static void markAccumulatedError(std::string_view message)
{
    if (accumulatedError.empty()) {
        accumulatedError.assign(message);
    }
}

/* Проверяет ограничения тела byte- и C-строк. */
static void validateStringContent(std::string_view text)
{
    if ((stringFlavor == StringFlavor::Byte ||
         stringFlavor == StringFlavor::RawByte) && containsNonAscii(text)) {
        markAccumulatedError("a byte string may contain only ASCII characters");
    }

    if ((stringFlavor == StringFlavor::C ||
         stringFlavor == StringFlavor::RawC) && containsNul(text)) {
        markAccumulatedError("a C string may not contain a null byte");
    }
}

/*
 * Завершает составную лексему: печатает исходный текст комментария либо
 * вычисленное значение строкового литерала.
 */
static void finishAccumulated()
{
    if (!accumulatedError.empty()) {
        emitToken("ERROR", accumulatedText, accumulatedLine, accumulatedColumn);
        reportError(accumulatedError, accumulatedText,
                    accumulatedLine, accumulatedColumn);
    } else {
        emitToken(accumulatedKind,
                  accumulatedHasSemanticValue ? std::string_view(accumulatedValue)
                                              : std::string_view(accumulatedText),
                  accumulatedLine, accumulatedColumn);
    }

    accumulatedText.clear();
    accumulatedValue.clear();
    accumulatedError.clear();
    accumulatedKind = nullptr;
    accumulatedHasSemanticValue = false;
}

/* ASCII-проверка одной шестнадцатеричной цифры. */
static bool isHexDigit(char character)
{
    return std::isxdigit(static_cast<unsigned char>(character)) != 0;
}

/* Переводит hex-последовательность в число, пропуская разделители `_`. */
static unsigned int parseHexIgnoringUnderscores(std::string_view text)
{
    unsigned int value = 0;
    for (const char character : text) {
        if (character == '_') {
            continue;
        }
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

/* Кодирует Unicode scalar value в UTF-8 для semantic value литерала. */
static void appendUtf8(std::string& output, unsigned int value)
{
    if (value <= 0x7FU) {
        output.push_back(static_cast<char>(value));
    } else if (value <= 0x7FFU) {
        output.push_back(static_cast<char>(0xC0U | (value >> 6U)));
        output.push_back(static_cast<char>(0x80U | (value & 0x3FU)));
    } else if (value <= 0xFFFFU) {
        output.push_back(static_cast<char>(0xE0U | (value >> 12U)));
        output.push_back(static_cast<char>(0x80U | ((value >> 6U) & 0x3FU)));
        output.push_back(static_cast<char>(0x80U | (value & 0x3FU)));
    } else {
        output.push_back(static_cast<char>(0xF0U | (value >> 18U)));
        output.push_back(static_cast<char>(0x80U | ((value >> 12U) & 0x3FU)));
        output.push_back(static_cast<char>(0x80U | ((value >> 6U) & 0x3FU)));
        output.push_back(static_cast<char>(0x80U | (value & 0x3FU)));
    }
}

/* Преобразует одну проверенную служебную последовательность в её значение. */
static bool decodeEscape(std::string_view escape, std::string& output)
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
        output.push_back(static_cast<char>(parseHexIgnoringUnderscores(escape.substr(2))));
        return true;
    }

    if (escape.size() >= 5 && escape.substr(0, 3) == "\\u{" &&
        escape.back() == '}') {
        const unsigned int value = parseHexIgnoringUnderscores(
            escape.substr(3, escape.size() - 4));
        if (value > 0x10FFFFU || (value >= 0xD800U && value <= 0xDFFFU)) {
            return false;
        }
        appendUtf8(output, value);
        return true;
    }

    return false;
}

static std::string withoutUnderscores(std::string_view text)
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

/* Вычисляет semantic value целого литерала с учётом системы счисления. */
static void emitIntegerLiteral(const char* kind, int base, int prefixLength)
{
    const std::string_view source(yytext, static_cast<std::size_t>(yyleng));
    const std::string normalized = withoutUnderscores(source);
    const char* digits = normalized.c_str() + prefixLength;
    char* end = nullptr;
    errno = 0;
    const unsigned long long value = std::strtoull(digits, &end, base);

    if (end == digits || errno == ERANGE) {
        emitToken("ERROR", source, matchLine, matchColumn);
        reportError("integer literal is outside the supported range",
                    source, matchLine, matchColumn);
        return;
    }

    emitUnsignedValue(kind, value, matchLine, matchColumn);
}

/* Вычисляет semantic value вещественного литерала. */
static void emitFloatingLiteral()
{
    const std::string_view source(yytext, static_cast<std::size_t>(yyleng));
    const std::string normalized = withoutUnderscores(source);
    char* end = nullptr;
    errno = 0;
    const double value = std::strtod(normalized.c_str(), &end);

    if (end == normalized.c_str() || errno == ERANGE) {
        emitToken("ERROR", source, matchLine, matchColumn);
        reportError("floating-point literal is outside the supported range",
                    source, matchLine, matchColumn);
        return;
    }

    emitFloatValue("FLOAT_LITERAL", value, matchLine, matchColumn);
}

/* Проверяет ограничения escape вида \xNN для выбранного вида строки. */
static void validateHexEscape(std::string_view escape)
{
    const unsigned int value = parseHexIgnoringUnderscores(escape.substr(2));

    if (stringFlavor == StringFlavor::Normal && value > 0x7FU) {
        markAccumulatedError("a string \\x escape must be in the ASCII range");
    } else if (stringFlavor == StringFlavor::C && value == 0U) {
        markAccumulatedError("a C string may not contain a null byte");
    }
}

/* Проверяет escape вида \u{...}: число цифр проверяет regex, здесь — значение. */
static void validateUnicodeEscape(std::string_view escape)
{
    if (stringFlavor == StringFlavor::Byte) {
        markAccumulatedError("Unicode escapes are not allowed in byte strings");
        return;
    }

    const std::size_t openBrace = escape.find('{');
    const std::size_t closeBrace = escape.rfind('}');
    const unsigned int value = parseHexIgnoringUnderscores(
        escape.substr(openBrace + 1, closeBrace - openBrace - 1));

    if (value > 0x10FFFFU || (value >= 0xD800U && value <= 0xDFFFU)) {
        markAccumulatedError("Unicode escape is not a valid scalar value");
    } else if (stringFlavor == StringFlavor::C && value == 0U) {
        markAccumulatedError("a C string may not contain a null byte");
    }
}

/* Возвращает длину одного UTF-8 code point по его первому байту. */
static std::size_t utf8CharacterLength(unsigned char firstByte)
{
    if (firstByte < 0x80U) return 1;
    if ((firstByte & 0xE0U) == 0xC0U) return 2;
    if ((firstByte & 0xF0U) == 0xE0U) return 3;
    if ((firstByte & 0xF8U) == 0xF0U) return 4;
    return 0;
}

/*
 * Проверяет содержимое символьного/byte-литерала: ровно один символ или один
 * допустимый escape. Суффикс после закрывающей кавычки здесь не анализируется.
 */
static std::string validateCharacterLiteral(std::string_view literal, bool isByte)
{
    const std::size_t contentStart = isByte ? 2U : 1U;
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

    const std::string_view content =
        literal.substr(contentStart, closingQuote - contentStart);
    if (content.empty()) {
        return "character literal is empty";
    }

    if (content.front() == '\\') {
        if (content.size() == 2 &&
            std::string_view("nrt0\\\'\"").find(content[1]) != std::string_view::npos) {
            return {};
        }

        if (content.size() == 4 && content[1] == 'x' &&
            isHexDigit(content[2]) && isHexDigit(content[3])) {
            const unsigned int value = parseHexIgnoringUnderscores(content.substr(2));
            if (!isByte && value > 0x7FU) {
                return "a character \\x escape must be in the ASCII range";
            }
            return {};
        }

        if (!isByte && content.size() >= 5 && content.substr(0, 3) == "\\u{" &&
            content.back() == '}') {
            const std::string_view digits = content.substr(3, content.size() - 4);
            int digitCount = 0;
            for (const char character : digits) {
                if (character != '_') {
                    if (!isHexDigit(character)) {
                        return "invalid Unicode escape in character literal";
                    }
                    ++digitCount;
                }
            }
            if (digitCount < 1 || digitCount > 6) {
                return "Unicode escape must contain from one to six hex digits";
            }
            const unsigned int value = parseHexIgnoringUnderscores(digits);
            if (value > 0x10FFFFU || (value >= 0xD800U && value <= 0xDFFFU)) {
                return "Unicode escape is not a valid scalar value";
            }
            return {};
        }

        return "unknown character escape";
    }

    const std::size_t characterLength =
        utf8CharacterLength(static_cast<unsigned char>(content.front()));
    if (characterLength == 0 || characterLength != content.size()) {
        return "a character literal must contain exactly one character";
    }
    if (isByte && containsNonAscii(content)) {
        return "a byte literal may contain only an ASCII character";
    }
    if (content.front() == '\t') {
        return "a tab must be escaped in a character literal";
    }
    return {};
}

static std::string characterLiteralValue(std::string_view literal, bool isByte)
{
    const std::size_t contentStart = isByte ? 2U : 1U;
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

    const std::string_view content =
        literal.substr(contentStart, closingQuote - contentStart);
    std::string value;
    if (content.front() == '\\') {
        decodeEscape(content, value);
    } else {
        value.assign(content);
    }
    return value;
}

/* Выводит проверенный CHAR_LITERAL/BYTE_LITERAL либо ERROR. */
static void emitCharacterLiteral(const char* kind, bool isByte)
{
    const std::string_view text(yytext, static_cast<std::size_t>(yyleng));
    const std::string error = validateCharacterLiteral(text, isByte);
    if (error.empty()) {
        const std::string value = characterLiteralValue(text, isByte);
        if (isByte) {
            emitUnsignedValue(kind, static_cast<unsigned char>(value.front()),
                              matchLine, matchColumn);
        } else {
            emitToken(kind, value, matchLine, matchColumn);
        }
    } else {
        emitToken("ERROR", text, matchLine, matchColumn);
        reportError(error, text, matchLine, matchColumn);
    }
}

/* Все неключевые слова, включая имена типов, остаются идентификаторами. */
static void emitIdentifier()
{
    emitCurrentToken("ID");
}

/*
 * `r`, `br` и `cr` перед # могут начинать корректный raw-токен; остальные
 * идентификаторы образуют запрещённый reserved prefix Rust 2021+.
 */
static bool isAllowedBeforePound(std::string_view identifier)
{
    return identifier == "r" || identifier == "br" || identifier == "cr";
}
%}

    /* ===== Регулярные выражения идентификаторов и UTF-8 ================ */
    /*
     * Пока любой корректно закодированный не-ASCII code point допускается
     * внутри имени. Точная фильтрация XID и NFC перечислена в TODO наверху.
     */
ASCII_ID_START  [a-zA-Z_]
ASCII_ID_CONT   [a-zA-Z0-9_]
UTF8_2          [\xC2-\xDF][\x80-\xBF]
UTF8_3          (\xE0[\xA0-\xBF][\x80-\xBF]|[\xE1-\xEC\xEE-\xEF][\x80-\xBF]{2}|\xED[\x80-\x9F][\x80-\xBF])
UTF8_4          (\xF0[\x90-\xBF][\x80-\xBF]{2}|[\xF1-\xF3][\x80-\xBF]{3}|\xF4[\x80-\x8F][\x80-\xBF]{2})
UTF8_CHAR       ({UTF8_2}|{UTF8_3}|{UTF8_4})
ID_START        ({ASCII_ID_START}|{UTF8_CHAR})
ID_CONT         ({ASCII_ID_CONT}|{UTF8_CHAR})
IDENTIFIER      {ID_START}{ID_CONT}*
SUFFIX          (([a-zA-Z]|{UTF8_CHAR}){ID_CONT}*|_{ID_CONT}+)

    /* ===== Регулярные выражения числовых литералов ===================== */
    /* Суффикс отделяется не здесь: по Rust Reference он разрешён у любого
     * literal token, а его смысл проверяется на следующих этапах. */
DEC_NUMBER      [0-9][0-9_]*
BIN_NUMBER      0b_*[01][01_]*
OCT_NUMBER      0o_*[0-7][0-7_]*
HEX_NUMBER      0x_*[0-9a-fA-F][0-9a-fA-F_]*
EXPONENT        [eE][+-]?_*[0-9][0-9_]*

    /* ===== Общие элементы строк и символьных литералов ================= */
UNICODE_ESCAPE  \\u\{([0-9a-fA-F]_*){1,6}\}
CHAR_UNIT       ([^\'\\\r\n]|\\x[0-9a-fA-F]{2}|{UNICODE_ESCAPE}|\\[^\r\n])
PATTERN_WS      ([ \t\v\f\r\n]|\xC2\x85|\xE2\x80[\x8E\x8F\xA8\xA9])

%%

    /* ================================================================== */
    /* ЗОНА A. Начало файла, BOM, shebang и пробельные символы             */
    /* ================================================================== */

\xEF\xBB\xBF                    {
                                      if (matchLine == 1 && matchColumn == 1) {
                                          /* A leading BOM does not occupy a source column. */
                                          currentColumn = 1;
                                      } else {
                                          emitCurrentError("UTF-8 BOM is allowed only at the start of a file");
                                      }
                                  }

^"#!"[^\r\n]*                  {
                                      const bool isInitialShebang =
                                          matchLine == 1 && matchColumn == 1 &&
                                          (yyleng == 2 || yytext[2] != '[');
                                      if (isInitialShebang) {
                                          emitCurrentToken("SHEBANG");
                                      } else {
                                          yyless(1);
                                          keepMatchedPrefix(yytext, 1);
                                          emitToken("POUND", "#", matchLine, matchColumn);
                                      }
                                  }

{PATTERN_WS}+                    { /* Пробелы только разделяют токены. */ }

    /* ================================================================== */
    /* ЗОНА B. Ключевые слова                                             */
    /* Каждое слово — отдельное Flex-правило, как требует лабораторная.   */
    /* Имена типов и weak keywords намеренно сюда не входят: это ID.      */
    /* ================================================================== */

"_"                               { emitCurrentToken("UNDERSCORE"); }
"as"                              { emitCurrentToken("AS"); }
"async"                           { emitCurrentToken("ASYNC"); }
"await"                           { emitCurrentToken("AWAIT"); }
"break"                           { emitCurrentToken("BREAK"); }
"const"                           { emitCurrentToken("CONST"); }
"continue"                        { emitCurrentToken("CONTINUE"); }
"crate"                           { emitCurrentToken("CRATE"); }
"dyn"                             { emitCurrentToken("DYN"); }
"else"                            { emitCurrentToken("ELSE"); }
"enum"                            { emitCurrentToken("ENUM"); }
"extern"                          { emitCurrentToken("EXTERN"); }
"false"                           { emitCurrentToken("FALSE"); }
"fn"                              { emitCurrentToken("FN"); }
"for"                             { emitCurrentToken("FOR"); }
"if"                              { emitCurrentToken("IF"); }
"impl"                            { emitCurrentToken("IMPL"); }
"in"                              { emitCurrentToken("IN"); }
"let"                             { emitCurrentToken("LET"); }
"loop"                            { emitCurrentToken("LOOP"); }
"match"                           { emitCurrentToken("MATCH"); }
"mod"                             { emitCurrentToken("MOD"); }
"move"                            { emitCurrentToken("MOVE"); }
"mut"                             { emitCurrentToken("MUT"); }
"pub"                             { emitCurrentToken("PUB"); }
"ref"                             { emitCurrentToken("REF"); }
"return"                          { emitCurrentToken("RETURN"); }
"self"                            { emitCurrentToken("SELF_VALUE"); }
"Self"                            { emitCurrentToken("SELF_TYPE"); }
"static"                          { emitCurrentToken("STATIC"); }
"struct"                          { emitCurrentToken("STRUCT"); }
"super"                           { emitCurrentToken("SUPER"); }
"trait"                           { emitCurrentToken("TRAIT"); }
"true"                            { emitCurrentToken("TRUE"); }
"type"                            { emitCurrentToken("TYPE"); }
"unsafe"                          { emitCurrentToken("UNSAFE"); }
"use"                             { emitCurrentToken("USE"); }
"where"                           { emitCurrentToken("WHERE"); }
"while"                           { emitCurrentToken("WHILE"); }

"abstract"                        { emitCurrentToken("ABSTRACT"); }
"become"                          { emitCurrentToken("BECOME"); }
"box"                             { emitCurrentToken("BOX"); }
"do"                              { emitCurrentToken("DO"); }
"final"                           { emitCurrentToken("FINAL"); }
"macro"                           { emitCurrentToken("MACRO"); }
"override"                        { emitCurrentToken("OVERRIDE"); }
"priv"                            { emitCurrentToken("PRIV"); }
"try"                             { emitCurrentToken("TRY"); }
"typeof"                          { emitCurrentToken("TYPEOF"); }
"unsized"                         { emitCurrentToken("UNSIZED"); }
"virtual"                         { emitCurrentToken("VIRTUAL"); }
"yield"                           { emitCurrentToken("YIELD"); }

    /* ================================================================== */
    /* ЗОНА C. Однострочные комментарии и line doc comments               */
    /* ================================================================== */

"//!"[^\r\n]*                 { emitCurrentToken("INNER_LINE_DOC_COMMENT"); }
"///"([^/\r\n][^\r\n]*)?    { emitCurrentToken("OUTER_LINE_DOC_COMMENT"); }
"//"[^\r\n]*                  { emitCurrentToken("LINE_COMMENT"); }

    /* ================================================================== */
    /* ЗОНА D. Вложенные блочные и block doc comments                     */
    /* BLOCK_COMMENT — exclusive state до выравнивания вложенности.       */
    /* ================================================================== */

"/*"                            {
                                      beginAccumulated("BLOCK_COMMENT", StringFlavor::Normal,
                                                       yytext, yyleng);
                                      blockCommentDepth = 1;
                                      BEGIN(BLOCK_COMMENT);
                                  }
<BLOCK_COMMENT>"/*"              {
                                      appendAccumulated(yytext, yyleng);
                                      ++blockCommentDepth;
                                  }
<BLOCK_COMMENT>"*/"              {
                                      appendAccumulated(yytext, yyleng);
                                      --blockCommentDepth;
                                      if (blockCommentDepth == 0) {
                                          const std::string_view comment(accumulatedText);
                                          if (comment.rfind("/*!", 0) == 0) {
                                              accumulatedKind = "INNER_BLOCK_DOC_COMMENT";
                                          } else if (comment.rfind("/**", 0) == 0 &&
                                                     comment.size() > 3 &&
                                                     comment[3] != '*' && comment[3] != '/') {
                                              accumulatedKind = "OUTER_BLOCK_DOC_COMMENT";
                                          }
                                          finishAccumulated();
                                          BEGIN(INITIAL);
                                      }
                                  }
<BLOCK_COMMENT>[^*/\r\n]+        { appendAccumulated(yytext, yyleng); }
<BLOCK_COMMENT>[*/]               { appendAccumulated(yytext, yyleng); }
<BLOCK_COMMENT>[\r\n]            { appendAccumulated(yytext, yyleng); }
<BLOCK_COMMENT><<EOF>>            {
                                      emitToken("ERROR", accumulatedText,
                                                accumulatedLine, accumulatedColumn);
                                      reportError("block comment is not closed", accumulatedText,
                                                  accumulatedLine, accumulatedColumn);
                                      return 0;
                                  }

    /* ================================================================== */
    /* ЗОНА E. Открывающие части raw-, raw byte- и raw C-строк            */
    /* Число # сохраняется и сравнивается с закрывающим разделителем.     */
    /* ================================================================== */

br[#]*\"                         {
                                      beginAccumulated("RAW_BYTE_STRING_LITERAL",
                                                       StringFlavor::RawByte, yytext, yyleng, true);
                                      rawHashCount = countOpeningHashes(accumulatedText);
                                      if (rawHashCount > 255) {
                                          markAccumulatedError("raw strings may use at most 255 # characters");
                                      }
                                      BEGIN(RAW_STRING);
                                  }
cr[#]*\"                         {
                                      beginAccumulated("RAW_C_STRING_LITERAL",
                                                       StringFlavor::RawC, yytext, yyleng, true);
                                      rawHashCount = countOpeningHashes(accumulatedText);
                                      if (rawHashCount > 255) {
                                          markAccumulatedError("raw strings may use at most 255 # characters");
                                      }
                                      BEGIN(RAW_STRING);
                                  }
r[#]*\"                          {
                                      beginAccumulated("RAW_STRING_LITERAL",
                                                       StringFlavor::Raw, yytext, yyleng, true);
                                      rawHashCount = countOpeningHashes(accumulatedText);
                                      if (rawHashCount > 255) {
                                          markAccumulatedError("raw strings may use at most 255 # characters");
                                      }
                                      BEGIN(RAW_STRING);
                                  }

    /* ================================================================== */
    /* ЗОНА F. Обычные String / Byte string / C string                    */
    /* ================================================================== */

b\"                               {
                                      beginAccumulated("BYTE_STRING_LITERAL",
                                                       StringFlavor::Byte, yytext, yyleng, true);
                                      BEGIN(STRING);
                                  }
c\"                               {
                                      beginAccumulated("C_STRING_LITERAL",
                                                       StringFlavor::C, yytext, yyleng, true);
                                      BEGIN(STRING);
                                  }
\"                                {
                                      beginAccumulated("STRING_LITERAL",
                                                       StringFlavor::Normal, yytext, yyleng, true);
                                      BEGIN(STRING);
                                  }

    /* ================================================================== */
    /* ЗОНА G. Содержимое обычных строк и escape-последовательности        */
    /* STRING завершается только кавычкой; ошибка сохраняется до конца.   */
    /* ================================================================== */

<STRING>[^\"\\\r]+             {
                                      appendAccumulated(yytext, yyleng);
                                      accumulatedValue.append(yytext,
                                          static_cast<std::size_t>(yyleng));
                                      validateStringContent(
                                          std::string_view(yytext, static_cast<std::size_t>(yyleng)));
                                  }
<STRING>\\[nrt0\\\'\"]        {
                                      appendAccumulated(yytext, yyleng);
                                      decodeEscape(
                                          std::string_view(yytext, static_cast<std::size_t>(yyleng)),
                                          accumulatedValue);
                                      if (stringFlavor == StringFlavor::C && yytext[1] == '0') {
                                          markAccumulatedError("a C string may not contain a null byte");
                                      }
                                  }
<STRING>\\x[0-9a-fA-F]{2}       {
                                      appendAccumulated(yytext, yyleng);
                                      decodeEscape(
                                          std::string_view(yytext, static_cast<std::size_t>(yyleng)),
                                          accumulatedValue);
                                      validateHexEscape(
                                          std::string_view(yytext, static_cast<std::size_t>(yyleng)));
                                  }
<STRING>{UNICODE_ESCAPE}           {
                                      appendAccumulated(yytext, yyleng);
                                      decodeEscape(
                                          std::string_view(yytext, static_cast<std::size_t>(yyleng)),
                                          accumulatedValue);
                                      validateUnicodeEscape(
                                          std::string_view(yytext, static_cast<std::size_t>(yyleng)));
                                  }
<STRING>\\\n{PATTERN_WS}*         { appendAccumulated(yytext, yyleng); }
<STRING>\\.                       {
                                      appendAccumulated(yytext, yyleng);
                                      markAccumulatedError("unknown string escape");
                                  }
<STRING>\\                        {
                                      appendAccumulated(yytext, yyleng);
                                      markAccumulatedError("unfinished string escape");
                                  }
<STRING>\r                         {
                                      appendAccumulated(yytext, yyleng);
                                      markAccumulatedError("carriage return is not allowed in a string literal");
                                  }
<STRING>\"{SUFFIX}?               {
                                      appendAccumulated(yytext, yyleng);
                                      finishAccumulated();
                                      BEGIN(INITIAL);
                                  }
<STRING><<EOF>>                    {
                                      emitToken("ERROR", accumulatedText,
                                                accumulatedLine, accumulatedColumn);
                                      reportError("string literal is not closed", accumulatedText,
                                                  accumulatedLine, accumulatedColumn);
                                      return 0;
                                  }

    /* ================================================================== */
    /* ЗОНА H. Содержимое raw-строк                                       */
    /* В raw-строках backslash ничего не экранирует.                      */
    /* ================================================================== */

<RAW_STRING>[^\"\r]+             {
                                      appendAccumulated(yytext, yyleng);
                                      accumulatedValue.append(yytext,
                                          static_cast<std::size_t>(yyleng));
                                      validateStringContent(
                                          std::string_view(yytext, static_cast<std::size_t>(yyleng)));
                                  }
<RAW_STRING>\r                     {
                                      appendAccumulated(yytext, yyleng);
                                      accumulatedValue.append(yytext,
                                          static_cast<std::size_t>(yyleng));
                                      markAccumulatedError("carriage return is not allowed in a raw string literal");
                                  }
<RAW_STRING>\"[#]*{SUFFIX}?       {
                                      int closingHashes = 0;
                                      while (1 + closingHashes < yyleng &&
                                             yytext[1 + closingHashes] == '#') {
                                          ++closingHashes;
                                      }

                                      if (closingHashes < rawHashCount) {
                                          appendAccumulated(yytext, yyleng);
                                          accumulatedValue.append(yytext,
                                              static_cast<std::size_t>(yyleng));
                                      } else {
                                          int usedLength = yyleng;
                                          if (closingHashes > rawHashCount) {
                                              usedLength = 1 + rawHashCount;
                                              yyless(usedLength);
                                              keepMatchedPrefix(yytext, usedLength);
                                          }
                                          appendAccumulated(yytext, usedLength);
                                          finishAccumulated();
                                          BEGIN(INITIAL);
                                      }
                                  }
<RAW_STRING><<EOF>>                {
                                      emitToken("ERROR", accumulatedText,
                                                accumulatedLine, accumulatedColumn);
                                      reportError("raw string literal is not closed", accumulatedText,
                                                  accumulatedLine, accumulatedColumn);
                                      return 0;
                                  }

    /* ================================================================== */
    /* ЗОНА I. Character и byte character literals                       */
    /* Закрытые литералы берёт CHAR_UNIT; BYTE_CHAR ловит незавершённые.  */
    /* ================================================================== */

b\'{CHAR_UNIT}\'{SUFFIX}?        {
                                      emitCharacterLiteral("BYTE_LITERAL", true);
                                  }
\'{CHAR_UNIT}\'{SUFFIX}?         {
                                      emitCharacterLiteral("CHAR_LITERAL", false);
                                  }
b\'                                {
                                      beginAccumulated("BYTE_LITERAL", StringFlavor::Byte,
                                                       yytext, yyleng);
                                      BEGIN(BYTE_CHAR);
                                  }
<BYTE_CHAR>[^\r\n\']+            { appendAccumulated(yytext, yyleng); }
<BYTE_CHAR>\'{SUFFIX}?             {
                                      appendAccumulated(yytext, yyleng);
                                      const std::string error =
                                          validateCharacterLiteral(accumulatedText, true);
                                      if (error.empty()) {
                                          const std::string value =
                                              characterLiteralValue(accumulatedText, true);
                                          emitUnsignedValue("BYTE_LITERAL",
                                              static_cast<unsigned char>(value.front()),
                                              accumulatedLine, accumulatedColumn);
                                      } else {
                                          emitToken("ERROR", accumulatedText,
                                                    accumulatedLine, accumulatedColumn);
                                          reportError(error, accumulatedText,
                                                      accumulatedLine, accumulatedColumn);
                                      }
                                      BEGIN(INITIAL);
                                  }
<BYTE_CHAR>[\r\n]                 {
                                      appendAccumulated(yytext, yyleng);
                                      emitToken("ERROR", accumulatedText,
                                                accumulatedLine, accumulatedColumn);
                                      reportError("byte literal is not closed", accumulatedText,
                                                  accumulatedLine, accumulatedColumn);
                                      BEGIN(INITIAL);
                                  }
<BYTE_CHAR><<EOF>>                 {
                                      emitToken("ERROR", accumulatedText,
                                                accumulatedLine, accumulatedColumn);
                                      reportError("byte literal is not closed", accumulatedText,
                                                  accumulatedLine, accumulatedColumn);
                                      return 0;
                                  }

    /* ================================================================== */
    /* ЗОНА I. Lifetime и raw lifetime                                    */
    /* Эти правила стоят после CHAR_LITERAL, чтобы 'a' был символом,      */
    /* а 'a без закрывающей кавычки — lifetime.                           */
    /* ================================================================== */

\'r#(crate|self|Self|super|_)     { emitCurrentError("this raw lifetime name is reserved"); }
\'r#{IDENTIFIER}                  { emitCurrentToken("RAW_LIFETIME"); }
\'{IDENTIFIER}/#                  {
                                      const std::string_view text(yytext,
                                          static_cast<std::size_t>(yyleng));
                                      if (text == "'r") {
                                          emitCurrentToken("LIFETIME");
                                      } else {
                                          emitCurrentError("reserved lifetime prefix before #");
                                      }
                                  }
\'{IDENTIFIER}                    { emitCurrentToken("LIFETIME"); }

    /* ================================================================== */
    /* ЗОНА J. Raw identifiers                                            */
    /* r#_, r#crate, r#self, r#Self и r#super зарезервированы.             */
    /* ================================================================== */

r#(crate|self|Self|super|_)       { emitCurrentError("this raw identifier name is reserved"); }
r#{IDENTIFIER}                    { emitCurrentToken("RAW_IDENTIFIER"); }

    /* ================================================================== */
    /* ЗОНА K. Целочисленные литералы: binary / octal / hexadecimal       */
    /* Сначала ловятся неоднозначные ошибки, затем корректные основания.  */
    /* ================================================================== */

{BIN_NUMBER}[eE]{ID_CONT}*        { emitCurrentError("binary integer literal may not be followed by e or E"); }
{OCT_NUMBER}[eE]{ID_CONT}*        { emitCurrentError("octal integer literal may not be followed by e or E"); }
({BIN_NUMBER}|{OCT_NUMBER}|{HEX_NUMBER})/\.[0-9] {
                                      emitCurrentError("non-decimal integer literal may not be followed by a period");
                                  }
{BIN_NUMBER}{SUFFIX}?             { emitIntegerLiteral("INTEGER_LITERAL_BIN", 2, 2); }
{OCT_NUMBER}{SUFFIX}?             { emitIntegerLiteral("INTEGER_LITERAL_OCT", 8, 2); }
{HEX_NUMBER}{SUFFIX}?             { emitIntegerLiteral("INTEGER_LITERAL_HEX", 16, 2); }
0b{ID_CONT}*                      { emitCurrentError("invalid binary integer literal"); }
0o{ID_CONT}*                      { emitCurrentError("invalid octal integer literal"); }
0x{ID_CONT}*                      { emitCurrentError("invalid hexadecimal integer literal"); }

    /* ================================================================== */
    /* ЗОНА L. Decimal integer и floating-point literals                  */
    /* Trailing context не даёт принять 1..2 и 1.field за float.          */
    /* ================================================================== */

{DEC_NUMBER}(\.{DEC_NUMBER})?{EXPONENT}{SUFFIX}? {
                                      emitFloatingLiteral();
                                  }
{DEC_NUMBER}(\.{DEC_NUMBER})?[eE][+-]?{ID_CONT}* {
                                      emitCurrentError("floating-point exponent has no digits");
                                  }
{DEC_NUMBER}\.{DEC_NUMBER}{SUFFIX}? { emitFloatingLiteral(); }
{DEC_NUMBER}/\.\.               { emitIntegerLiteral("INTEGER_LITERAL_DEC", 10, 0); }
{DEC_NUMBER}/\.{ID_START}        { emitIntegerLiteral("INTEGER_LITERAL_DEC", 10, 0); }
{DEC_NUMBER}\.                   { emitFloatingLiteral(); }
{DEC_NUMBER}(f32|f64)             { emitFloatingLiteral(); }
{DEC_NUMBER}{SUFFIX}?             { emitIntegerLiteral("INTEGER_LITERAL_DEC", 10, 0); }

    /* ================================================================== */
    /* ЗОНА N. Reserved prefixes и обычные идентификаторы                 */
    /* Пример ошибки: custom"text" или custom#attribute.                 */
    /* ================================================================== */

{IDENTIFIER}/\"                 { emitCurrentError("reserved identifier prefix before a string"); }
{IDENTIFIER}/\'                  { emitCurrentError("reserved identifier prefix before a character quote"); }
{IDENTIFIER}/#                   {
                                      const std::string_view text(yytext,
                                          static_cast<std::size_t>(yyleng));
                                      if (isAllowedBeforePound(text)) {
                                          emitIdentifier();
                                      } else {
                                          emitCurrentError("reserved identifier prefix before #");
                                      }
                                  }

{IDENTIFIER}                      { emitIdentifier(); }

    /* ================================================================== */
    /* ЗОНА O. Составная пунктуация и операторы (проверяется первой)       */
    /* Flex выбирает самое длинное совпадение: >>= раньше, чем >> и >.     */
    /* ================================================================== */

"..="                             { emitCurrentToken("RANGE_INCLUSIVE"); }
"<<="                             { emitCurrentToken("SHIFT_LEFT_ASSIGN"); }
">>="                             { emitCurrentToken("SHIFT_RIGHT_ASSIGN"); }
"!="                              { emitCurrentToken("NOT_EQUAL"); }
"%="                              { emitCurrentToken("REMAINDER_ASSIGN"); }
"&&"                              { emitCurrentToken("LOGICAL_AND"); }
"&="                              { emitCurrentToken("BIT_AND_ASSIGN"); }
"*="                              { emitCurrentToken("MULTIPLY_ASSIGN"); }
"+="                              { emitCurrentToken("PLUS_ASSIGN"); }
"-="                              { emitCurrentToken("MINUS_ASSIGN"); }
"->"                              { emitCurrentToken("RIGHT_ARROW"); }
".."                              { emitCurrentToken("RANGE"); }
"/="                              { emitCurrentToken("DIVIDE_ASSIGN"); }
"::"                              { emitCurrentToken("PATH_SEPARATOR"); }
"<<"                              { emitCurrentToken("SHIFT_LEFT"); }
"<="                              { emitCurrentToken("LESS_EQUAL"); }
"=="                              { emitCurrentToken("EQUAL_EQUAL"); }
"=>"                              { emitCurrentToken("FAT_ARROW"); }
">="                              { emitCurrentToken("GREATER_EQUAL"); }
">>"                              { emitCurrentToken("SHIFT_RIGHT"); }
"^="                              { emitCurrentToken("BIT_XOR_ASSIGN"); }
"|="                              { emitCurrentToken("BIT_OR_ASSIGN"); }
"||"                              { emitCurrentToken("LOGICAL_OR"); }

    /* ================================================================== */
    /* ЗОНА P. Односимвольная пунктуация, операторы и delimiters           */
    /* ================================================================== */

"!"                               { emitCurrentToken("BANG"); }
"#"                               { emitCurrentToken("POUND"); }
"$"                               { emitCurrentToken("DOLLAR"); }
"%"                               { emitCurrentToken("REMAINDER"); }
"&"                               { emitCurrentToken("AMPERSAND"); }
"("                               { emitCurrentToken("LEFT_PAREN"); }
")"                               { emitCurrentToken("RIGHT_PAREN"); }
"*"                               { emitCurrentToken("STAR"); }
"+"                               { emitCurrentToken("PLUS"); }
","                               { emitCurrentToken("COMMA"); }
"-"                               { emitCurrentToken("MINUS"); }
"."                               { emitCurrentToken("DOT"); }
"/"                               { emitCurrentToken("SLASH"); }
":"                               { emitCurrentToken("COLON"); }
";"                               { emitCurrentToken("SEMICOLON"); }
"<"                               { emitCurrentToken("LESS"); }
"="                               { emitCurrentToken("ASSIGN"); }
">"                               { emitCurrentToken("GREATER"); }
"?"                               { emitCurrentToken("QUESTION"); }
"@"                               { emitCurrentToken("AT"); }
"["                               { emitCurrentToken("LEFT_BRACKET"); }
"]"                               { emitCurrentToken("RIGHT_BRACKET"); }
"^"                               { emitCurrentToken("BIT_XOR"); }
"{"                               { emitCurrentToken("LEFT_BRACE"); }
"|"                               { emitCurrentToken("PIPE"); }
"}"                               { emitCurrentToken("RIGHT_BRACE"); }
"~"                               { emitCurrentToken("TILDE"); }

    /* ================================================================== */
    /* ЗОНА Q. Неизвестные символы и конец файла                           */
    /* ================================================================== */

\'                                { emitCurrentError("unexpected single quote"); }
.                                 { emitCurrentError("unknown character"); }

    /* EOF печатается как отдельный маркер, чтобы тестировать конец ввода. */
<<EOF>>                           {
                                      emitToken("EOF", "", currentLine, currentColumn);
                                      return 0;
                                  }

%%

/* Печатает краткую справку при запуске без файла либо с флагом --help. */
static void printUsage(const char* executable)
{
    std::printf("Usage: %s <source.rs>\n", executable);
    std::printf("Prints one recognized lexical token per line.\n");
}

/*
 * CLI-точка входа: открывает один .rs-файл, запускает Flex и преобразует
 * накопленный флаг ошибок в документированные коды возврата 0/1/2.
 */
int main(int argc, char** argv)
{
    if (argc == 2 && (std::strcmp(argv[1], "--help") == 0 ||
                      std::strcmp(argv[1], "-h") == 0)) {
        printUsage(argv[0]);
        return 0;
    }

    if (argc != 2) {
        printUsage(argv[0]);
        return 1;
    }

    sourceName = argv[1];
    yyin = std::fopen(argv[1], "rb");
    if (yyin == nullptr) {
        std::fprintf(stderr, "Cannot open source file: %s\n", argv[1]);
        return 1;
    }

    yylex();
    std::fclose(yyin);
    return hadErrors ? 2 : 0;
}
