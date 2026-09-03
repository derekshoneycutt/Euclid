set(EUCLID_DRIVER "${CMAKE_SOURCE_DIR}/tools/make.jl")

function(euclid_add_driver_target target)
    cmake_parse_arguments(EUCLID_TARGET "ALL;NO_BOOTSTRAP" "" "ARGS" ${ARGN})
    set(_all_argument)
    if(EUCLID_TARGET_ALL)
        set(_all_argument ALL)
    endif()
    set(_dependencies)
    if(NOT EUCLID_TARGET_NO_BOOTSTRAP)
        list(APPEND _dependencies euclid-bootstrap)
    endif()

    add_custom_target(${target} ${_all_argument}
        COMMAND "${CMAKE_COMMAND}" -E env
            "EUCLID_HARFBUZZ_PROVIDER=${EUCLID_HARFBUZZ_PROVIDER_ENV}"
            "${EUCLID_JULIA_EXECUTABLE}" "${EUCLID_DRIVER}"
            ${EUCLID_TARGET_ARGS}
        WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}"
        DEPENDS ${_dependencies}
        USES_TERMINAL
        VERBATIM
    )
endfunction()

set(_euclid_mode_arguments)
if(EUCLID_ODIN_DEBUG)
    list(APPEND _euclid_mode_arguments --debug)
endif()
if(EUCLID_ODIN_STRICT)
    list(APPEND _euclid_mode_arguments --strict)
endif()

set(_euclid_run_only_arguments)
if(EUCLID_ODIN_DEBUG)
    list(APPEND _euclid_run_only_arguments --debug)
endif()

euclid_add_driver_target(euclid ALL ARGS build ${_euclid_mode_arguments})
add_custom_target(build DEPENDS euclid)
euclid_add_driver_target(run ARGS run ${_euclid_mode_arguments})
euclid_add_driver_target(run-only ARGS run-only ${_euclid_run_only_arguments})
euclid_add_driver_target(assets ARGS assets)
euclid_add_driver_target(unit ARGS unit)
euclid_add_driver_target(check ARGS test)
euclid_add_driver_target(vet ARGS vet)
euclid_add_driver_target(sysimage ARGS sysimage ${_euclid_mode_arguments})
euclid_add_driver_target(harness ARGS harness)
euclid_add_driver_target(analyzer-test ARGS analyzer-test)
euclid_add_driver_target(wiki ARGS wiki)
euclid_add_driver_target(check-wiki ARGS check-wiki)
euclid_add_driver_target(clean-all NO_BOOTSTRAP ARGS clean)
euclid_add_driver_target(euclid-help NO_BOOTSTRAP ARGS help)
