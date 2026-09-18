if(NOT DEFINED LEXER OR NOT DEFINED INPUT OR NOT DEFINED EXPECTED_EXIT OR
   NOT DEFINED EXPECTATIONS)
    message(FATAL_ERROR "The lexer test runner did not receive all required arguments")
endif()

execute_process(
    COMMAND "${LEXER}" "${INPUT}"
    RESULT_VARIABLE actual_exit
    OUTPUT_VARIABLE lexer_stdout
    ERROR_VARIABLE lexer_stderr
)

if(NOT "${actual_exit}" STREQUAL "${EXPECTED_EXIT}")
    message(FATAL_ERROR
        "Unexpected lexer exit code for ${INPUT}: expected ${EXPECTED_EXIT}, got ${actual_exit}\n"
        "stdout:\n${lexer_stdout}\n"
        "stderr:\n${lexer_stderr}"
    )
endif()

set(complete_output "${lexer_stdout}\n${lexer_stderr}")
file(STRINGS "${EXPECTATIONS}" required_fragments ENCODING UTF-8)

foreach(fragment IN LISTS required_fragments)
    string(STRIP "${fragment}" fragment)
    if(fragment STREQUAL "" OR fragment MATCHES "^#")
        continue()
    endif()

    if(fragment MATCHES "^!")
        string(SUBSTRING "${fragment}" 1 -1 forbidden_fragment)
        string(FIND "${complete_output}" "${forbidden_fragment}" fragment_position)
        if(NOT fragment_position EQUAL -1)
            message(FATAL_ERROR
                "Lexer output for ${INPUT} contains forbidden fragment:\n${forbidden_fragment}\n"
                "stdout:\n${lexer_stdout}\n"
                "stderr:\n${lexer_stderr}"
            )
        endif()
        continue()
    endif()

    string(FIND "${complete_output}" "${fragment}" fragment_position)
    if(fragment_position EQUAL -1)
        message(FATAL_ERROR
            "Lexer output for ${INPUT} does not contain required fragment:\n${fragment}\n"
            "stdout:\n${lexer_stdout}\n"
            "stderr:\n${lexer_stderr}"
        )
    endif()
endforeach()
