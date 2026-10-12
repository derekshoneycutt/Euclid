cmake_minimum_required(VERSION 3.28)
project(EuclidShadercrossMacOSProvider LANGUAGES C CXX)

add_subdirectory("${EUCLID_PROVIDER_SDL_SOURCE}" sdl)
add_subdirectory("${EUCLID_PROVIDER_SHADERCROSS_SOURCE}" shadercross)
