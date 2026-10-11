package native

import sdl "vendor:sdl3"
import image "vendor:sdl3/image"

// sdl_platform_set_icon applies one decoded image and releases its temporary surface.
sdl_platform_set_icon :: proc(platform: ^Sdl_Platform, path: cstring) -> bool {
    if platform == nil || platform^.window == nil || path == nil {
        return false
    }
    surface := image.Load(path)
    if surface == nil {
        return false
    }
    defer sdl.DestroySurface(surface)
    return sdl.SetWindowIcon(platform^.window, surface)
}