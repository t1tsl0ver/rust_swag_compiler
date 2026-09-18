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

add_executable(rust_swag_lexer ${FLEX_RustSwagLexer_OUTPUTS})

if(MSVC)
    target_compile_options(rust_swag_lexer PRIVATE /W4)
else()
    target_compile_options(rust_swag_lexer PRIVATE -Wall -Wextra -Wpedantic)
endif()

if(MINGW)
    # Produce a self-contained executable which also works when CTest does not
    # inherit the MSYS2 runtime directories through PATH.
    target_link_options(rust_swag_lexer PRIVATE -static)
endif()

# Keep the command from README identical for single- and multi-config generators.
set_target_properties(rust_swag_lexer PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
)
foreach(configuration Debug Release RelWithDebInfo MinSizeRel)
    string(TOUPPER "${configuration}" configuration_upper)
    set_target_properties(rust_swag_lexer PROPERTIES
        "RUNTIME_OUTPUT_DIRECTORY_${configuration_upper}" "${CMAKE_BINARY_DIR}/bin"
    )
endforeach()

if(BUILD_TESTING)
    function(add_lexer_test test_name input_file expected_exit expectations_file)
        add_test(
            NAME "lexer.${test_name}"
            COMMAND "${CMAKE_COMMAND}"
                "-DLEXER=$<TARGET_FILE:rust_swag_lexer>"
                "-DINPUT=${CMAKE_CURRENT_SOURCE_DIR}/_compiler/tests_lexer/${input_file}"
                "-DEXPECTED_EXIT=${expected_exit}"
                "-DEXPECTATIONS=${CMAKE_CURRENT_SOURCE_DIR}/_compiler/tests_lexer/expected/${expectations_file}"
                -P "${CMAKE_CURRENT_SOURCE_DIR}/_compiler/tests_lexer/verify_lexer.cmake"
        )
    endfunction()

    add_lexer_test(all_tokens all_tokens.rs 0 all_tokens.txt)
    add_lexer_test(lab_requirements lab_requirements.rs 0 lab_requirements.txt)
    add_lexer_test(full_valid_program full_valid_program.rs 0 full_valid_program.txt)
    add_lexer_test(positions positions.rs 0 positions.txt)
    add_lexer_test(empty_input empty_input.rs 0 empty_input.txt)
    add_lexer_test(edge_identifiers_numbers edge_identifiers_numbers.rs 0 edge_identifiers_numbers.txt)
    add_lexer_test(edge_strings_comments edge_strings_comments.rs 0 edge_strings_comments.txt)
    add_lexer_test(raw_hash_limits raw_hash_limits.rs 2 raw_hash_limits.txt)
    add_lexer_test(invalid_escape invalid_escape.rs 2 invalid_escape.txt)
    add_lexer_test(invalid_characters invalid_characters.rs 2 invalid_characters.txt)
    add_lexer_test(invalid_string_contents invalid_string_contents.rs 2 invalid_string_contents.txt)
    add_lexer_test(invalid_numeric_boundaries invalid_numeric_boundaries.rs 2 invalid_numeric_boundaries.txt)
    add_lexer_test(invalid_unclosed_string invalid_unclosed_string.rs 2 invalid_unclosed_string.txt)
    add_lexer_test(invalid_unclosed_comment invalid_unclosed_comment.rs 2 invalid_unclosed_comment.txt)
    add_lexer_test(invalid_unclosed_raw_string invalid_unclosed_raw_string.rs 2 invalid_unclosed_raw_string.txt)
    add_lexer_test(invalid_unclosed_byte invalid_unclosed_byte.rs 2 invalid_unclosed_byte.txt)
    add_lexer_test(invalid_numbers invalid_numbers.rs 2 invalid_numbers.txt)
    add_lexer_test(reserved_tokens reserved_tokens.rs 2 reserved_tokens.txt)
endif()
