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
#include <cctype>
#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <string_view>

/* Состояние позиции и текущей составной лексемы */

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

/*
 * Простая система координат: перевод строки увеличивает номер строки, остальные байты увеличивают колонку.
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

/* Макрос нужный для того что бы выдавать найденный токен и передвигать позицию Flex уже после токена. */
#define YY_USER_ACTION do { beginMatch(yytext, yyleng); } while (0);

/*
 * Исправляет позицию после yyless(), когда Flex возвращает хвост совпадения обратно во входной поток при разборе raw-строк.
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
            }
            else {
                std::fputc(character, stream);
            }
        }
    }
    std::fputc('"', stream);
}

/* Единая точка диагностического вывода корректно распознанного токена. */
static void printToken(const char* kind, std::string_view text, int line, int column)
{
    std::printf("%d:%d  %-32s ", line, column, kind);
    printEscaped(stdout, text);
    std::fputc('\n', stdout);
}

/* Числовые semantic values печатаются числами, без строковых кавычек. */
static void printUnsignedValue(const char* kind, unsigned long long value, int line, int column)
{
    std::printf("%d:%d  %-32s %llu\n", line, column, kind, value);
}

static void printFloatValue(const char* kind, double value, int line, int column)
{
    std::printf("%d:%d  %-32s %.17g\n", line, column, kind, value);
}

/* Печатает текущее совпадение yytext с координатами, сохранёнными Flex. */
static void printCurrentToken(const char* kind)
{
    printToken(kind, std::string_view(yytext, static_cast<std::size_t>(yyleng)), matchLine, matchColumn);
}

/* Регистрирует ошибку, чтобы main вернул код 2, и выводит её в stderr. */
static void reportError(std::string_view message, std::string_view text, int line, int column)
{
    hadErrors = true;
    std::fprintf(stderr, "%s:%d:%d: lexer error: %.*s: ", sourceName, line, column, static_cast<int>(message.size()), message.data());
    printEscaped(stderr, text);
    std::fputc('\n', stderr);
}

/* Выводит текущее совпадение как ERROR и создаёт связанную диагностику. */
static void reportCurrentError(std::string_view message)
{
    const std::string_view text(yytext, static_cast<std::size_t>(yyleng));
    printToken("ERROR", text, matchLine, matchColumn);
    reportError(message, text, matchLine, matchColumn);
}

/* Проверяет, присутствуют ли во фрагменте байты вне ASCII. */
static bool containsNonAscii(std::string_view text)
{
    for (const unsigned char character : text) {
        if (character >= 0x80U) {
            return true;
        }
    }
    return false;
}

/* Считает # в открывающей части raw-строки: r###". */
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

/* Начинает накапливать строку, raw-строку или блочный комментарий. */
static void beginAccumulated(const char* kind, const char* text, int length, bool hasSemanticValue = false)
{
    accumulatedKind = kind;
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

/* Проверяет ASCII-ограничение строки. */
static void validateStringContent(std::string_view text)
{
    if (containsNonAscii(text)) {
        markAccumulatedError("a string literal may contain only ASCII characters");
    }
}

/*
 * Завершает составную лексему: печатает исходный текст комментария либо вычисленное значение строкового литерала.
 */
static void finishAccumulated()
{
    if (!accumulatedError.empty()) {
        printToken("ERROR", accumulatedText, accumulatedLine, accumulatedColumn);
        reportError(accumulatedError, accumulatedText, accumulatedLine, accumulatedColumn);
    }
    else {
        printToken(accumulatedKind,
        accumulatedHasSemanticValue ? std::string_view(accumulatedValue) : std::string_view(accumulatedText),
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
static unsigned int parseHex(std::string_view text)
{
    unsigned int value = 0;
    for (const char character : text) {
        value *= 16U;
        if (character >= '0' && character <= '9') {
            value += static_cast<unsigned int>(character - '0');
        }
        else if (character >= 'a' && character <= 'f') {
            value += 10U + static_cast<unsigned int>(character - 'a');
        }
        else {
            value += 10U + static_cast<unsigned int>(character - 'A');
        }
    }
    return value;
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
        output.push_back(static_cast<char>(parseHex(escape.substr(2))));
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
static void handleIntegerLiteral(const char* kind, int base, int prefixLength)
{
    const std::string_view source(yytext, static_cast<std::size_t>(yyleng));
    const std::string normalized = withoutUnderscores(source);
    const char* digits = normalized.c_str() + prefixLength;
    char* end = nullptr;
    errno = 0;
    const unsigned long long value = std::strtoull(digits, &end, base);

    if (end == digits || errno == ERANGE) {
        printToken("ERROR", source, matchLine, matchColumn);
        reportError("integer literal is outside the supported range", source, matchLine, matchColumn);
        return;
    }

    printUnsignedValue(kind, value, matchLine, matchColumn);
}

/* Вычисляет semantic value вещественного литерала. */
static void handleFloatingLiteral()
{
    const std::string_view source(yytext, static_cast<std::size_t>(yyleng));
    const std::string normalized = withoutUnderscores(source);
    char* end = nullptr;
    errno = 0;
    const double value = std::strtod(normalized.c_str(), &end);

    if (end == normalized.c_str() || errno == ERANGE) {
        printToken("ERROR", source, matchLine, matchColumn);
        reportError("floating-point literal is outside the supported range", source, matchLine, matchColumn);
        return;
    }

    printFloatValue("FLOAT_LITERAL", value, matchLine, matchColumn);
}

/* Проверяет ASCII-ограничение escape вида \xNN в строке. */
static void validateHexEscape(std::string_view escape)
{
    const unsigned int value = parseHex(escape.substr(2));

    if (value > 0x7FU) {
        markAccumulatedError("a string \\x escape must be in the ASCII range");
    }
}

/*
 * Проверяет содержимое символьного литерала (ровно один символ или один допустимый escape).
 * Суффикс после закрывающей кавычки здесь не анализируется.
 */
static std::string validateCharacterLiteral(std::string_view literal)
{
    const std::size_t contentStart = 1U;
    std::size_t closingQuote = contentStart;
    bool escaped = false;

    // поиск закрывающей кавычки
    for ( ; closingQuote < literal.size(); ++closingQuote) {
        const char character = literal[closingQuote];
        if (!escaped && character == '\'') {
            break;
        }
        if (!escaped && character == '\\') {
            escaped = true;
        }
        else {
            escaped = false;
        }
    }
    // не нашли закрывающую кавычку. (для '\''\')
    if (closingQuote == literal.size()) {
        return "character literal is not closed";
    }

    const std::string_view content =
        literal.substr(contentStart, closingQuote - contentStart);
    if (content.empty()) {
        return "character literal is empty";
    }

    // escape
    if (content.front() == '\\') {
        if (content.size() == 2 && std::string_view("nrt0\\\'\"").find(content[1]) != std::string_view::npos) {
            return {};
        }

        if (content.size() == 4 && content[1] == 'x' &&
            isHexDigit(content[2]) && isHexDigit(content[3])) {
            const unsigned int value = parseHex(content.substr(2));
            if (value > 0x7FU) {
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

static std::string characterLiteralValue(std::string_view literal)
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
        }
        else {
            escaped = false;
        }
    }

    const std::string_view content =
        literal.substr(contentStart, closingQuote - contentStart);
    std::string value;
    if (content.front() == '\\') {
        decodeEscape(content, value);
    }
    else {
        value.assign(content);
    }
    return value;
}

/* Выводит проверенный CHAR_LITERAL либо ERROR. */
static void handleCharacterLiteral()
{
    const std::string_view text(yytext, static_cast<std::size_t>(yyleng));
    const std::string error = validateCharacterLiteral(text);
    if (error.empty()) {
        printToken("CHAR_LITERAL", characterLiteralValue(text), matchLine, matchColumn);
    }
    else {
        printToken("ERROR", text, matchLine, matchColumn);
        reportError(error, text, matchLine, matchColumn);
    }
}

/* Все неключевые слова, включая имена типов, остаются идентификаторами. */
static void handleIdentifier()
{
    printCurrentToken("ID");
}

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

"_"         { printCurrentToken("UNDERSCORE"); }
"as"        { printCurrentToken("AS"); }
"async"     { printCurrentToken("ASYNC"); }
"await"     { printCurrentToken("AWAIT"); }
"break"     { printCurrentToken("BREAK"); }
"const"     { printCurrentToken("CONST"); }
"continue"  { printCurrentToken("CONTINUE"); }
"crate"     { printCurrentToken("CRATE"); }
"dyn"       { printCurrentToken("DYN"); }
"else"      { printCurrentToken("ELSE"); }
"enum"      { printCurrentToken("ENUM"); }
"extern"    { printCurrentToken("EXTERN"); }
"false"     { printCurrentToken("FALSE"); }
"fn"        { printCurrentToken("FN"); }
"for"       { printCurrentToken("FOR"); }
"if"        { printCurrentToken("IF"); }
"impl"      { printCurrentToken("IMPL"); }
"in"        { printCurrentToken("IN"); }
"let"       { printCurrentToken("LET"); }
"loop"      { printCurrentToken("LOOP"); }
"match"     { printCurrentToken("MATCH"); }
"mod"       { printCurrentToken("MOD"); }
"move"      { printCurrentToken("MOVE"); }
"mut"       { printCurrentToken("MUT"); }
"pub"       { printCurrentToken("PUB"); }
"ref"       { printCurrentToken("REF"); }
"return"    { printCurrentToken("RETURN"); }
"self"      { printCurrentToken("SELF_VALUE"); }
"Self"      { printCurrentToken("SELF_TYPE"); }
"static"    { printCurrentToken("STATIC"); }
"struct"    { printCurrentToken("STRUCT"); }
"super"     { printCurrentToken("SUPER"); }
"trait"     { printCurrentToken("TRAIT"); }
"true"      { printCurrentToken("TRUE"); }
"type"      { printCurrentToken("TYPE"); }
"unsafe"    { printCurrentToken("UNSAFE"); }
"use"       { printCurrentToken("USE"); }
"where"     { printCurrentToken("WHERE"); }
"while"     { printCurrentToken("WHILE"); }

"abstract"  { printCurrentToken("ABSTRACT"); }
"become"    { printCurrentToken("BECOME"); }
"box"       { printCurrentToken("BOX"); }
"do"        { printCurrentToken("DO"); }
"final"     { printCurrentToken("FINAL"); }
"macro"     { printCurrentToken("MACRO"); }
"override"  { printCurrentToken("OVERRIDE"); }
"priv"      { printCurrentToken("PRIV"); }
"try"       { printCurrentToken("TRY"); }
"typeof"    { printCurrentToken("TYPEOF"); }
"unsized"   { printCurrentToken("UNSIZED"); }
"virtual"   { printCurrentToken("VIRTUAL"); }
"yield"     { printCurrentToken("YIELD"); }


 /* ЗОНА 3 Однострочные комментарии и line doc comments */

"//!"[^\r\n]*               { printCurrentToken("INNER_LINE_DOC_COMMENT"); }
"///"([^/\r\n][^\r\n]*)?    { printCurrentToken("OUTER_LINE_DOC_COMMENT"); }
"//"[^\r\n]*                { printCurrentToken("LINE_COMMENT"); }


 /* ЗОНА 4 Вложенные блочные и block doc comments */

"/*"                            {
                                      beginAccumulated("BLOCK_COMMENT", yytext, yyleng);
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
                                      printToken("ERROR", accumulatedText,
                                                accumulatedLine, accumulatedColumn);
                                      reportError("block comment is not closed", accumulatedText,
                                                  accumulatedLine, accumulatedColumn);
                                      return 0;
                                  }


 /* ЗОНА 5 Открывающая часть raw-строки */

r[#]*\"                          {
                                      beginAccumulated("RAW_STRING_LITERAL",
                                                       yytext, yyleng, true);
                                      rawHashCount = countOpeningHashes(accumulatedText);
                                      if (rawHashCount > 255) {
                                          markAccumulatedError("raw strings may use at most 255 # characters");
                                      }
                                      BEGIN(RAW_STRING);
                                  }


 /* ЗОНА 6 Обычная строка */

\"                                {
                                      beginAccumulated("STRING_LITERAL", yytext, yyleng, true);
                                      BEGIN(STRING);
                                  }


 /* ЗОНА 7 Содержимое обычных строк и escape-последовательности */

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
                                  }
<STRING>\\x[0-9a-fA-F]{2}       {
                                      appendAccumulated(yytext, yyleng);
                                      decodeEscape(
                                          std::string_view(yytext, static_cast<std::size_t>(yyleng)),
                                          accumulatedValue);
                                      validateHexEscape(
                                          std::string_view(yytext, static_cast<std::size_t>(yyleng)));
                                  }
<STRING>\\\r?\n{PATTERN_WS}*       { appendAccumulated(yytext, yyleng); }
<STRING>\\.                       {
                                      appendAccumulated(yytext, yyleng);
                                      markAccumulatedError("unknown string escape");
                                  }
<STRING>\\                        {
                                      appendAccumulated(yytext, yyleng);
                                      markAccumulatedError("unfinished string escape");
                                  }
<STRING>\r\n                       {
                                      appendAccumulated(yytext, yyleng);
                                      accumulatedValue.push_back('\n');
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
                                      printToken("ERROR", accumulatedText,
                                                accumulatedLine, accumulatedColumn);
                                      reportError("string literal is not closed", accumulatedText,
                                                  accumulatedLine, accumulatedColumn);
                                      return 0;
                                  }


 /* ЗОНА 8 Содержимое raw-строк */

<RAW_STRING>[^\"\r]+             {
                                      appendAccumulated(yytext, yyleng);
                                      accumulatedValue.append(yytext,
                                          static_cast<std::size_t>(yyleng));
                                      const std::string_view content(yytext,
                                          static_cast<std::size_t>(yyleng));
                                      if (containsNonAscii(content)) {
                                          markAccumulatedError("a string literal may contain only ASCII characters");
                                      }
                                  }
<RAW_STRING>\r\n                   {
                                      appendAccumulated(yytext, yyleng);
                                      accumulatedValue.push_back('\n');
                                  }
<RAW_STRING>\r                     {
                                      appendAccumulated(yytext, yyleng);
                                      accumulatedValue.append(yytext,
                                          static_cast<std::size_t>(yyleng));
                                      markAccumulatedError("carriage return is not allowed in a raw string literal");
                                  }
<RAW_STRING>\"[#]*{SUFFIX}?     {
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
<RAW_STRING><<EOF>>               {
                                      printToken("ERROR", accumulatedText,
                                                accumulatedLine, accumulatedColumn);
                                      reportError("raw string literal is not closed", accumulatedText,
                                                  accumulatedLine, accumulatedColumn);
                                      return 0;
                                  }


 /* ЗОНА 9 Символьные литералы */

\'{CHAR_UNIT}\'{SUFFIX}?         {
                                      handleCharacterLiteral();
                                  }


 /* ЗОНА 10. Raw identifiers */

r#(crate|self|Self|super|_)       { reportCurrentError("this raw identifier name is reserved"); }
r#{IDENTIFIER}                    { printCurrentToken("RAW_IDENTIFIER"); }


 /* ЗОНА 11 Целочисленные литералы: binary / octal / hexadecimal */

 /* 0b101e10 - было бы 0b101 и отдельно e10*/
 
{BIN_NUMBER}[eE]{ID_CONT}*        { reportCurrentError("binary integer literal may not be followed by e or E"); }
{OCT_NUMBER}[eE]{ID_CONT}*        { reportCurrentError("octal integer literal may not be followed by e or E"); }
({BIN_NUMBER}|{OCT_NUMBER}|{HEX_NUMBER})/\.[0-9] {
                                      reportCurrentError("non-decimal integer literal may not be followed by a period");
                                  }

{BIN_NUMBER}{SUFFIX}?             { handleIntegerLiteral("INTEGER_LITERAL_BIN", 2, 2); }
{OCT_NUMBER}{SUFFIX}?             { handleIntegerLiteral("INTEGER_LITERAL_OCT", 8, 2); }
{HEX_NUMBER}{SUFFIX}?             { handleIntegerLiteral("INTEGER_LITERAL_HEX", 16, 2); }

0b{ID_CONT}*                      { reportCurrentError("invalid binary integer literal"); }
0o{ID_CONT}*                      { reportCurrentError("invalid octal integer literal"); }
0x{ID_CONT}*                      { reportCurrentError("invalid hexadecimal integer literal"); }


 /* ЗОНА 12 Decimal integer и floating-point literals */

{DEC_NUMBER}(\.{DEC_NUMBER})?{EXPONENT}{SUFFIX}? {
                                      handleFloatingLiteral();
                                  }
{DEC_NUMBER}(\.{DEC_NUMBER})?[eE][+-]?{ID_CONT}* {
                                      reportCurrentError("floating-point exponent has no digits");
                                  }
{DEC_NUMBER}\.{DEC_NUMBER}{SUFFIX}? { handleFloatingLiteral(); }
{DEC_NUMBER}/\.\.               { handleIntegerLiteral("INTEGER_LITERAL_DEC", 10, 0); }
{DEC_NUMBER}/\.{ID_START}        { handleIntegerLiteral("INTEGER_LITERAL_DEC", 10, 0); }
{DEC_NUMBER}\.                   { handleFloatingLiteral(); }
{DEC_NUMBER}(f32|f64)             { handleFloatingLiteral(); }
{DEC_NUMBER}{SUFFIX}?             { handleIntegerLiteral("INTEGER_LITERAL_DEC", 10, 0); }

 /* ЗОНА 13 Reserved prefixes и обычные идентификаторы */

{IDENTIFIER}/\"                 { reportCurrentError("reserved identifier prefix before a string"); }
{IDENTIFIER}/\'                  { reportCurrentError("reserved identifier prefix before a character quote"); }
{IDENTIFIER}/#                   {
                                      const std::string_view text(yytext,
                                          static_cast<std::size_t>(yyleng));
                                      if (text == "r") {
                                          handleIdentifier();
                                      } else {
                                          reportCurrentError("reserved identifier prefix before #");
                                      }
                                  }

{IDENTIFIER}                      { handleIdentifier(); }


 /* ЗОНА 14 Составная пунктуация и операторы (проверяется первой) */

"..="                             { printCurrentToken("RANGE_INCLUSIVE"); }
"<<="                             { printCurrentToken("SHIFT_LEFT_ASSIGN"); }
">>="                             { printCurrentToken("SHIFT_RIGHT_ASSIGN"); }
"!="                              { printCurrentToken("NOT_EQUAL"); }
"%="                              { printCurrentToken("REMAINDER_ASSIGN"); }
"&&"                              { printCurrentToken("LOGICAL_AND"); }
"&="                              { printCurrentToken("BIT_AND_ASSIGN"); }
"*="                              { printCurrentToken("MULTIPLY_ASSIGN"); }
"+="                              { printCurrentToken("PLUS_ASSIGN"); }
"-="                              { printCurrentToken("MINUS_ASSIGN"); }
"->"                              { printCurrentToken("RIGHT_ARROW"); }
".."                              { printCurrentToken("RANGE"); }
"/="                              { printCurrentToken("DIVIDE_ASSIGN"); }
"::"                              { printCurrentToken("PATH_SEPARATOR"); }
"<<"                              { printCurrentToken("SHIFT_LEFT"); }
"<="                              { printCurrentToken("LESS_EQUAL"); }
"=="                              { printCurrentToken("EQUAL_EQUAL"); }
"=>"                              { printCurrentToken("FAT_ARROW"); }
">="                              { printCurrentToken("GREATER_EQUAL"); }
">>"                              { printCurrentToken("SHIFT_RIGHT"); }
"^="                              { printCurrentToken("BIT_XOR_ASSIGN"); }
"|="                              { printCurrentToken("BIT_OR_ASSIGN"); }
"||"                              { printCurrentToken("LOGICAL_OR"); }


 /* ЗОНА 15 Односимвольная пунктуация, операторы и delimiters */

"!"                               { printCurrentToken("BANG"); }
"#"                               { printCurrentToken("POUND"); }
"$"                               { printCurrentToken("DOLLAR"); }
"%"                               { printCurrentToken("REMAINDER"); }
"&"                               { printCurrentToken("AMPERSAND"); }
"("                               { printCurrentToken("LEFT_PAREN"); }
")"                               { printCurrentToken("RIGHT_PAREN"); }
"*"                               { printCurrentToken("STAR"); }
"+"                               { printCurrentToken("PLUS"); }
","                               { printCurrentToken("COMMA"); }
"-"                               { printCurrentToken("MINUS"); }
"."                               { printCurrentToken("DOT"); }
"/"                               { printCurrentToken("SLASH"); }
":"                               { printCurrentToken("COLON"); }
";"                               { printCurrentToken("SEMICOLON"); }
"<"                               { printCurrentToken("LESS"); }
"="                               { printCurrentToken("ASSIGN"); }
">"                               { printCurrentToken("GREATER"); }
"?"                               { printCurrentToken("QUESTION"); }
"@"                               { printCurrentToken("AT"); }
"["                               { printCurrentToken("LEFT_BRACKET"); }
"]"                               { printCurrentToken("RIGHT_BRACKET"); }
"^"                               { printCurrentToken("BIT_XOR"); }
"{"                               { printCurrentToken("LEFT_BRACE"); }
"|"                               { printCurrentToken("PIPE"); }
"}"                               { printCurrentToken("RIGHT_BRACE"); }
"~"                               { printCurrentToken("TILDE"); }


 /* ЗОНА 16 Неизвестные символы и конец файла */

\'                                { reportCurrentError("unexpected single quote"); }
.                                 { reportCurrentError("unknown character"); }

 /* EOF печатается как отдельный маркер, чтобы тестировать конец ввода. */
<<EOF>>                           {
                                      printToken("EOF", "", currentLine, currentColumn);
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
 * CLI-точка входа: открывает один .rs-файл, запускает Flex и преобразует накопленный флаг ошибок в документированные коды возврата 0/1/2.
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