include(CTest)

if(BUILD_TESTING)
    function(euclid_add_driver_test name)
        cmake_parse_arguments(EUCLID_TEST "" "" "ARGS;LABELS" ${ARGN})
        add_test(NAME ${name}
            COMMAND "${CMAKE_COMMAND}" -E env
                "EUCLID_HARFBUZZ_PROVIDER=${EUCLID_HARFBUZZ_PROVIDER_ENV}"
                "${EUCLID_JULIA_EXECUTABLE}" "${EUCLID_DRIVER}"
                ${EUCLID_TEST_ARGS}
        )
        set_tests_properties(${name} PROPERTIES
            WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
            FIXTURES_REQUIRED euclid-bootstrap
            LABELS "${EUCLID_TEST_LABELS}"
        )
    endfunction()

    add_test(NAME bootstrap
        COMMAND "${CMAKE_COMMAND}" --build "${CMAKE_BINARY_DIR}"
            --target euclid-bootstrap
    )
    set_tests_properties(bootstrap PROPERTIES
        FIXTURES_SETUP euclid-bootstrap
        LABELS bootstrap
    )

    add_test(NAME cmake-invalid-harfbuzz-provider
        COMMAND "${CMAKE_COMMAND}"
            "-DEUCLID_SOURCE_DIR=${CMAKE_SOURCE_DIR}"
            "-DEUCLID_TEST_BINARY_DIR=${CMAKE_BINARY_DIR}/configure-tests/invalid-provider"
            -P "${CMAKE_SOURCE_DIR}/cmake/tests/ExpectInvalidProvider.cmake"
    )
    set_tests_properties(cmake-invalid-harfbuzz-provider PROPERTIES
        LABELS cmake
    )

    euclid_add_driver_test(julia-unit
        ARGS unit julia
        LABELS "unit;julia")
    euclid_add_driver_test(odin-unit
        ARGS unit odin
        LABELS "unit;native")

    set(EUCLID_ODIN_TEST_PACKAGES
        .
        bridge
        core
        diagnostics
        dynview/compile
        dynview/core
        dynview/layout
        dynview/math
        evidence/allocation
        evidence/artifact
        evidence/capture
        evidence/checkpoint
        evidence/export
        evidence/observe
        evidence/profile
        evidence/scenario
        evidence/session
        evidence/text
        evidence/trace
        files
        grid
        particles
        shapes
        taskpool
        view
        view/core
        view/font
        view/ui
        view/ui/dynview
    )
    foreach(package_path IN LISTS EUCLID_ODIN_TEST_PACKAGES)
        string(REPLACE "/" "-" package_name "${package_path}")
        if(package_name STREQUAL ".")
            set(package_name root)
        endif()
        euclid_add_driver_test(odin-package-${package_name}
            ARGS unit odin "--package=${package_path}"
            LABELS "odin-package;native")
    endforeach()

    euclid_add_driver_test(analyzer-regression
        ARGS analyzer-test
        LABELS "analysis")
    euclid_add_driver_test(headless-harness
        ARGS harness
        LABELS "integration;native")
endif()
