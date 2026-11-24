cmake_minimum_required(VERSION 3.20)

project(rust_swag_compiler LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

include(CTest)
find_package(FLEX 2.6 REQUIRED)
find_package(BISON 3.8 REQUIRED)

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

bison_target(
    RustSwagParser
    "${CMAKE_CURRENT_SOURCE_DIR}/_compiler/parser/parser.y"
    "${CMAKE_CURRENT_BINARY_DIR}/generated/rust_parser.cpp"
    DEFINES_FILE "${CMAKE_CURRENT_BINARY_DIR}/generated/rust_parser.hpp"
)

add_library(rust_swag_parser STATIC
    ${BISON_RustSwagParser_OUTPUTS}
    "_compiler/parser/Parser.cpp"
    "_compiler/parser/Ast.cpp"
)
target_link_libraries(rust_swag_parser PUBLIC rust_swag_lexer)
target_include_directories(rust_swag_parser
    PUBLIC "_compiler/parser"
    PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/generated"
)

add_executable(parser_tree "_compiler/parser/main.cpp")
target_link_libraries(parser_tree PRIVATE rust_swag_parser)

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

    add_executable(parser_ast_test "_compiler/tests_parser/ast_test.cpp")
    target_link_libraries(parser_ast_test PRIVATE rust_swag_parser)
    add_test(NAME parser.ast
        COMMAND parser_ast_test
                "${CMAKE_CURRENT_SOURCE_DIR}/_compiler/tests_parser/ast.rs"
                "${CMAKE_CURRENT_SOURCE_DIR}/_compiler/tests_parser/invalid.rs"
                "${CMAKE_CURRENT_SOURCE_DIR}/_compiler/tests_lexer/stream_unclosed.rs")
    add_test(NAME parser.nested_control_flow
        COMMAND parser_ast_test
                "${CMAKE_CURRENT_SOURCE_DIR}/_compiler/tests_parser/nested_control_flow.rs")
endif()
