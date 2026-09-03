cmake_minimum_required(VERSION 3.28)

project(Euclid LANGUAGES NONE)

if(CMAKE_SOURCE_DIR STREQUAL CMAKE_BINARY_DIR)
    message(FATAL_ERROR
        "In-source builds are unsupported. Use a checked-in CMake preset.")
endif()

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")

include(EuclidOptions)

find_program(EUCLID_JULIA_EXECUTABLE NAMES julia REQUIRED)
find_program(EUCLID_ODIN_EXECUTABLE NAMES odin REQUIRED)

if(NOT EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/tools/analysis/Project.toml")
    message(FATAL_ERROR
        "Analysis submodule missing. Run: git submodule update --init --recursive")
endif()

if(WIN32)
    find_program(EUCLID_GENDEF_EXECUTABLE NAMES gendef REQUIRED)
endif()

include(EuclidBootstrap)
include(EuclidTargets)
include(EuclidTests)

message(STATUS "Euclid HarfBuzz provider: ${EUCLID_HARFBUZZ_PROVIDER}")
message(STATUS "Euclid Julia executable: ${EUCLID_JULIA_EXECUTABLE}")
message(STATUS "Euclid Odin executable: ${EUCLID_ODIN_EXECUTABLE}")
