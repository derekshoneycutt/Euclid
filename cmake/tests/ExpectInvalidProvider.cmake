if(NOT DEFINED EUCLID_SOURCE_DIR OR NOT DEFINED EUCLID_TEST_BINARY_DIR)
    message(FATAL_ERROR "The configure contract test requires source and binary paths.")
endif()

file(REMOVE_RECURSE "${EUCLID_TEST_BINARY_DIR}")
execute_process(
    COMMAND "${CMAKE_COMMAND}"
        -S "${EUCLID_SOURCE_DIR}"
        -B "${EUCLID_TEST_BINARY_DIR}"
        -G Ninja
        -DEUCLID_HARFBUZZ_PROVIDER=invalid
    RESULT_VARIABLE configure_result
    OUTPUT_VARIABLE configure_output
    ERROR_VARIABLE configure_error
)

if(configure_result EQUAL 0)
    message(FATAL_ERROR "Invalid HarfBuzz provider unexpectedly configured.")
endif()

set(configure_log "${configure_output}${configure_error}")
if(NOT configure_log MATCHES
   "EUCLID_HARFBUZZ_PROVIDER must be either JLL or SYSTEM")
    message(FATAL_ERROR
        "Configure failed without the expected provider diagnostic:\n${configure_log}")
endif()

file(REMOVE_RECURSE "${EUCLID_TEST_BINARY_DIR}")
