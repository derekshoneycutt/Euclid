package native

import "core:c"

import sdl "vendor:sdl3"
import stbi "vendor:stb/image"

// sdl_platform_set_icon decodes one RGBA image and applies it to the SDL window.
sdl_platform_set_icon :: proc(platform: ^Sdl_Platform, path: cstring) -> bool {
    if platform == nil || platform^.window == nil || path == nil {
        return false
    }
    width, height, source_channels: c.int
    pixels := stbi.load(path, &width, &height, &source_channels, 4)
    if pixels == nil || width <= 0 || height <= 0 {
        return false
    }
    defer stbi.image_free(pixels)
    surface := sdl.CreateSurfaceFrom(
        width, height, .RGBA32, pixels, width * 4)
    if surface == nil {
        return false
    }
    defer sdl.DestroySurface(surface)
    return sdl.SetWindowIcon(platform^.window, surface)
}