#+build windows

package native

import win "core:sys/windows"

Sdl_Windows_High_Contrast :: struct {
    size: u32,
    flags: u32,
    default_scheme: ^u16,
}

SDL_SPI_GETHIGHCONTRAST :: 0x0042
SDL_HCF_HIGHCONTRASTON :: 0x00000001

// sdl_query_system_contrast reads the Windows accessibility high-contrast flag.
sdl_query_system_contrast :: proc(
    _: ^Sdl_Contrast_Preference,
    should_query: bool) -> Sdl_Contrast_Query_Result {
    if !should_query {
        return {}
    }
    setting := Sdl_Windows_High_Contrast{size = u32(size_of(Sdl_Windows_High_Contrast))}
    if !win.SystemParametersInfoW(
        SDL_SPI_GETHIGHCONTRAST, setting.size, &setting, 0) {
        return {status = .Failed, complete = true}
    }
    return {requested = setting.flags & SDL_HCF_HIGHCONTRASTON != 0,
        status = .Supported, complete = true}
}

// Windows contrast acquisition has no asynchronous resources to retire.
sdl_contrast_native_destroy :: proc(
    preference: ^Sdl_Contrast_Preference) {
    preference^ = {}
}
