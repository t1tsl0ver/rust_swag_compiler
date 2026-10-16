cmake_minimum_required(VERSION 3.20)

project(rust_swag_compiler LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

include(CTest)
find_package(FLEX 2.6 REQUIRED)

file(MAKE_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}/generated")

flex_target(
    RustSwagLexer
    "${CMAKE_CURRENT_SOURCE_DIR}/_compiler/lexer/lex.l"
    "${CMAKE_CURRENT_BINARY_DIR}/generated/lex.yy.cpp"
)

add_library(rust_swag_lexer STATIC
    ${FLEX_RustSwagLexer_OUTPUTS}
    "_compiler/lexer/LexerContext.cpp"
)
target_include_directories(rust_swag_lexer PUBLIC "_compiler/lexer")

if(MSVC)
    target_compile_options(rust_swag_lexer PRIVATE /W4)
else()
    target_compile_options(rust_swag_lexer PRIVATE -Wall -Wextra -Wpedantic)
endif()

if(BUILD_TESTING)
    add_executable(lexer_stream_test "_compiler/tests_lexer/stream_test.cpp")
    target_link_libraries(lexer_stream_test PRIVATE rust_swag_lexer)
    if(MINGW)
        target_link_options(lexer_stream_test PRIVATE -static)
    endif()

    add_test(NAME lexer.valid_stream
        COMMAND lexer_stream_test valid
                "${CMAKE_CURRENT_SOURCE_DIR}/_compiler/tests_lexer/stream_valid.rs")
    add_test(NAME lexer.error_recovery
        COMMAND lexer_stream_test errors
                "${CMAKE_CURRENT_SOURCE_DIR}/_compiler/tests_lexer/stream_errors.rs")
    add_test(NAME lexer.unclosed_comment
        COMMAND lexer_stream_test unclosed
                "${CMAKE_CURRENT_SOURCE_DIR}/_compiler/tests_lexer/stream_unclosed.rs")
endif()
