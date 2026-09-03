set(EUCLID_BOOTSTRAP_STAMP "${CMAKE_BINARY_DIR}/euclid-bootstrap.stamp")
set(EUCLID_APPLICATION_PROJECT "${CMAKE_SOURCE_DIR}/src/julia")
set(EUCLID_ANALYSIS_PROJECT "${CMAKE_SOURCE_DIR}/tools/analysis")
set(_euclid_pkg_expression "using Pkg; Pkg.instantiate(); Pkg.precompile()")

add_custom_command(
    OUTPUT "${EUCLID_BOOTSTRAP_STAMP}"
    COMMAND "${EUCLID_JULIA_EXECUTABLE}"
        "--project=${EUCLID_APPLICATION_PROJECT}"
        -e "${_euclid_pkg_expression}"
    COMMAND "${EUCLID_JULIA_EXECUTABLE}"
        "--project=${EUCLID_ANALYSIS_PROJECT}"
        -e "${_euclid_pkg_expression}"
    COMMAND "${CMAKE_COMMAND}" -E touch "${EUCLID_BOOTSTRAP_STAMP}"
    DEPENDS
        "${EUCLID_APPLICATION_PROJECT}/Project.toml"
        "${EUCLID_APPLICATION_PROJECT}/Manifest.toml"
        "${EUCLID_ANALYSIS_PROJECT}/Project.toml"
        "${EUCLID_ANALYSIS_PROJECT}/Manifest.toml"
    COMMENT "Instantiating Euclid Julia environments"
    VERBATIM
)

add_custom_target(euclid-bootstrap DEPENDS "${EUCLID_BOOTSTRAP_STAMP}")
add_custom_target(configure DEPENDS euclid-bootstrap)
