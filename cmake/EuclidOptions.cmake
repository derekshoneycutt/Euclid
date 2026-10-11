set(_euclid_harfbuzz_default "JLL")
if(DEFINED ENV{EUCLID_HARFBUZZ_PROVIDER})
    set(_euclid_harfbuzz_default "$ENV{EUCLID_HARFBUZZ_PROVIDER}")
endif()

set(EUCLID_HARFBUZZ_PROVIDER "${_euclid_harfbuzz_default}" CACHE STRING
    "HarfBuzz provider used by Euclid: JLL or SYSTEM")
set_property(CACHE EUCLID_HARFBUZZ_PROVIDER PROPERTY STRINGS JLL SYSTEM)
string(TOUPPER "${EUCLID_HARFBUZZ_PROVIDER}" EUCLID_HARFBUZZ_PROVIDER)
set(EUCLID_HARFBUZZ_PROVIDER "${EUCLID_HARFBUZZ_PROVIDER}" CACHE STRING
    "HarfBuzz provider used by Euclid: JLL or SYSTEM" FORCE)

if(NOT EUCLID_HARFBUZZ_PROVIDER STREQUAL "JLL" AND
   NOT EUCLID_HARFBUZZ_PROVIDER STREQUAL "SYSTEM")
    message(FATAL_ERROR
        "EUCLID_HARFBUZZ_PROVIDER must be either JLL or SYSTEM.")
endif()

if(WIN32 AND EUCLID_HARFBUZZ_PROVIDER STREQUAL "SYSTEM")
    message(FATAL_ERROR "System HarfBuzz linkage is unsupported on Windows.")
endif()

if(EUCLID_HARFBUZZ_PROVIDER STREQUAL "SYSTEM")
    find_package(PkgConfig REQUIRED)
    pkg_check_modules(EUCLID_HARFBUZZ REQUIRED harfbuzz)
endif()

string(TOLOWER "${EUCLID_HARFBUZZ_PROVIDER}"
    EUCLID_HARFBUZZ_PROVIDER_ENV)

option(EUCLID_ODIN_DEBUG "Build Euclid with Odin debug settings" OFF)
option(EUCLID_ODIN_STRICT "Build Euclid with strict Odin validation" OFF)
