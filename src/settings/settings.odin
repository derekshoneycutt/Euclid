package settings

import particlemodel "../particles/model"

WINDOW_LANDSCAPE_WIDTH :: 1280
WINDOW_LANDSCAPE_HEIGHT :: 720
WINDOW_PORTRAIT_WIDTH :: 640
WINDOW_PORTRAIT_HEIGHT :: 720
WINDOW_MIN_WIDTH :: 320
WINDOW_MIN_HEIGHT :: 240
WINDOW_MAX_EXTENT :: 16384
DUST_LIMIT_MAX :: particlemodel.MAX_LOW_PARTICLES

Setting_Id :: enum u8 {
    Window_Width,
    Window_Height,
    Window_Mode,
    Window_Layout,
    Rendering_Vsync,
    Rendering_Antialiasing,
    Rendering_Limit_Fps,
    Rendering_Simd,
    Rendering_Gpu_Dust_Instancing,
    Drawing_Dust_Limit,
    Drawing_Sound_Enabled,
    Interface_Display_Fps,
}

SETTING_COUNT :: 12
Setting_Set :: bit_set[Setting_Id; u16]
ALL_SETTING_IDS :: [SETTING_COUNT]Setting_Id{
    .Window_Width,
    .Window_Height,
    .Window_Mode,
    .Window_Layout,
    .Rendering_Vsync,
    .Rendering_Antialiasing,
    .Rendering_Limit_Fps,
    .Rendering_Simd,
    .Rendering_Gpu_Dust_Instancing,
    .Drawing_Dust_Limit,
    .Drawing_Sound_Enabled,
    .Interface_Display_Fps,
}

Window_Mode :: enum u8 {
    Fixed,
    Resizable,
}

Layout_Preference :: enum u8 {
    Auto,
    Landscape,
    Portrait,
}

Window_Startup_Policy :: struct {
    width: int,
    height: int,
    mode: Window_Mode,
    layout: Layout_Preference,
}

Setting_Value_Kind :: enum u8 {
    Boolean,
    Integer,
    Window_Mode,
    Layout_Preference,
}

Setting_Storage_Kind :: enum u8 {
    Boolean,
    Integer,
    Text,
}

Setting_Definition :: struct {
    id: Setting_Id,
    namespace: string,
    key: string,
    storage_kind: Setting_Storage_Kind,
}

SETTING_DEFINITIONS :: [SETTING_COUNT]Setting_Definition{
    {.Window_Width, "window", "width", .Integer},
    {.Window_Height, "window", "height", .Integer},
    {.Window_Mode, "window", "mode", .Text},
    {.Window_Layout, "window", "layout", .Text},
    {.Rendering_Vsync, "rendering", "vsync", .Boolean},
    {.Rendering_Antialiasing, "rendering", "antialiasing", .Boolean},
    {.Rendering_Limit_Fps, "rendering", "limit_fps", .Boolean},
    {.Rendering_Simd, "rendering", "simd", .Boolean},
    {.Rendering_Gpu_Dust_Instancing, "rendering", "gpu_dust_instancing", .Boolean},
    {.Drawing_Dust_Limit, "drawing", "dust_limit", .Integer},
    {.Drawing_Sound_Enabled, "drawing", "sound_enabled", .Boolean},
    {.Interface_Display_Fps, "interface", "display_fps", .Boolean},
}

Setting_Value :: struct {
    kind: Setting_Value_Kind,
    boolean: bool,
    integer: int,
    window_mode: Window_Mode,
    layout: Layout_Preference,
}

Preference_Source :: enum u8 {
    Saved,
    Override,
}

Rendering_Preferences :: struct {
    vsync: bool,
    antialiasing: bool,
    limit_fps: bool,
    simd: bool,
    gpu_dust_instancing: bool,
}

Drawing_Preferences :: struct {
    dust_limit: int,
    sound_enabled: bool,
}

Interface_Preferences :: struct {
    display_fps: bool,
}

Preferences :: struct {
    window: Window_Startup_Policy,
    rendering: Rendering_Preferences,
    drawing: Drawing_Preferences,
    interface: Interface_Preferences,
    present: Setting_Set,
    overrides: Setting_Set,
}

Change_Kind :: enum u8 {
    Set,
    Reset,
}

Change :: struct {
    id: Setting_Id,
    kind: Change_Kind,
    value: Setting_Value,
}

Change_Set :: struct {
    changes: [SETTING_COUNT]Change,
    count: int,
}

// Return the established startup dimensions, modes, and no-database defaults.
default_preferences :: proc() -> Preferences {
    return {
        window = {
            width = WINDOW_LANDSCAPE_WIDTH,
            height = WINDOW_LANDSCAPE_HEIGHT,
            mode = .Fixed,
            layout = .Auto,
        },
        rendering = {
            vsync = true,
            antialiasing = true,
            limit_fps = true,
            simd = true,
            gpu_dust_instancing = true,
        },
        drawing = {
            dust_limit = particlemodel.MAX_LOW_PARTICLES,
            sound_enabled = false,
        },
        interface = {display_fps = false},
    }
}

// Check the shared minimum and maximum for a startup width.
valid_window_width :: proc(width: i64) -> bool {
    return width >= i64(WINDOW_MIN_WIDTH) && width <= i64(WINDOW_MAX_EXTENT)
}

// Check the shared minimum and maximum for a startup height.
valid_window_height :: proc(height: i64) -> bool {
    return height >= i64(WINDOW_MIN_HEIGHT) && height <= i64(WINDOW_MAX_EXTENT)
}

// Check both startup extents with the canonical preference bounds.
valid_window_dimensions :: proc(width, height: i64) -> bool {
    return valid_window_width(width) && valid_window_height(height)
}

// Check a window mode enum value before it enters preference state.
valid_window_mode :: proc(mode: Window_Mode) -> bool {
    return mode == .Fixed || mode == .Resizable
}

// Check a layout preference enum value before it enters preference state.
valid_layout_preference :: proc(layout: Layout_Preference) -> bool {
    return layout == .Auto || layout == .Landscape || layout == .Portrait
}

// Check the existing dust particle capacity range.
valid_dust_limit :: proc(limit: i64) -> bool {
    return limit >= 0 && limit <= i64(DUST_LIMIT_MAX)
}

// Check that an identifier names one of the bounded initial preferences.
valid_setting_id :: proc(id: Setting_Id) -> bool {
    switch id {
    case .Window_Width, .Window_Height, .Window_Mode, .Window_Layout,
         .Rendering_Vsync, .Rendering_Antialiasing, .Rendering_Limit_Fps,
         .Rendering_Simd, .Rendering_Gpu_Dust_Instancing,
         .Drawing_Dust_Limit, .Drawing_Sound_Enabled, .Interface_Display_Fps:
        return true
    }
    return false
}

// Resolve one stable durable namespace/key and its generic scalar storage type.
setting_definition :: proc(id: Setting_Id) -> (Setting_Definition, bool) {
    if !valid_setting_id(id) {
        return {}, false
    }
    definitions := SETTING_DEFINITIONS
    return definitions[int(id)], true
}

// Return whether a typed scalar is valid for its known setting.
valid_setting_value :: proc(id: Setting_Id, value: Setting_Value) -> bool {
    switch id {
    case .Window_Width:
        return value.kind == .Integer && valid_window_width(i64(value.integer))
    case .Window_Height:
        return value.kind == .Integer && valid_window_height(i64(value.integer))
    case .Window_Mode:
        return value.kind == .Window_Mode && valid_window_mode(value.window_mode)
    case .Window_Layout:
        return value.kind == .Layout_Preference &&
            valid_layout_preference(value.layout)
    case .Rendering_Vsync, .Rendering_Antialiasing, .Rendering_Limit_Fps,
         .Rendering_Simd, .Rendering_Gpu_Dust_Instancing,
         .Drawing_Sound_Enabled, .Interface_Display_Fps:
        return value.kind == .Boolean
    case .Drawing_Dust_Limit:
        return value.kind == .Integer && valid_dust_limit(i64(value.integer))
    }
    return false
}

// Apply one boolean preference to its owning field.
apply_boolean_preference :: proc(
    preferences: ^Preferences, id: Setting_Id, value: bool) {
    #partial switch id {
    case .Rendering_Vsync:
        preferences^.rendering.vsync = value
    case .Rendering_Antialiasing:
        preferences^.rendering.antialiasing = value
    case .Rendering_Limit_Fps:
        preferences^.rendering.limit_fps = value
    case .Rendering_Simd:
        preferences^.rendering.simd = value
    case .Rendering_Gpu_Dust_Instancing:
        preferences^.rendering.gpu_dust_instancing = value
    case .Drawing_Sound_Enabled:
        preferences^.drawing.sound_enabled = value
    case .Interface_Display_Fps:
        preferences^.interface.display_fps = value
    }
}

// Apply one integer preference to its owning field.
apply_integer_preference :: proc(
    preferences: ^Preferences, id: Setting_Id, value: int) {
    #partial switch id {
    case .Window_Width:
        preferences^.window.width = value
    case .Window_Height:
        preferences^.window.height = value
    case .Drawing_Dust_Limit:
        preferences^.drawing.dust_limit = value
    }
}

// Apply one validated saved value or explicit invocation override.
apply_setting_value :: proc(
    preferences: ^Preferences,
    id: Setting_Id,
    value: Setting_Value,
    source: Preference_Source) -> bool {
    if preferences == nil || !valid_setting_value(id, value) ||
        (source != .Saved && source != .Override) {
        return false
    }
    switch value.kind {
    case .Boolean:
        apply_boolean_preference(preferences, id, value.boolean)
    case .Integer:
        apply_integer_preference(preferences, id, value.integer)
    case .Window_Mode:
        preferences^.window.mode = value.window_mode
    case .Layout_Preference:
        preferences^.window.layout = value.layout
    }
    if source == .Saved {
        preferences^.present += Setting_Set{id}
    } else {
        preferences^.overrides += Setting_Set{id}
    }
    return true
}

// Build a typed scalar value for a boolean preference.
boolean_value :: proc(value: bool) -> Setting_Value {
    return {kind = .Boolean, boolean = value}
}

// Build a typed scalar value for an integer preference.
integer_value :: proc(value: int) -> Setting_Value {
    return {kind = .Integer, integer = value}
}

// Build a typed scalar value for the window mode preference.
window_mode_value :: proc(value: Window_Mode) -> Setting_Value {
    return {kind = .Window_Mode, window_mode = value}
}

// Build a typed scalar value for the layout preference.
layout_preference_value :: proc(value: Layout_Preference) -> Setting_Value {
    return {kind = .Layout_Preference, layout = value}
}

// Read one typed scalar from the fixed preference record.
read_integer_preference :: proc(
    preferences: Preferences, id: Setting_Id) -> Setting_Value {
    #partial switch id {
    case .Window_Width:
        return integer_value(preferences.window.width)
    case .Window_Height:
        return integer_value(preferences.window.height)
    case .Drawing_Dust_Limit:
        return integer_value(preferences.drawing.dust_limit)
    }
    return {}
}

// Read one boolean preference from the fixed preference record.
read_boolean_preference :: proc(
    preferences: Preferences, id: Setting_Id) -> Setting_Value {
    #partial switch id {
    case .Rendering_Vsync:
        return boolean_value(preferences.rendering.vsync)
    case .Rendering_Antialiasing:
        return boolean_value(preferences.rendering.antialiasing)
    case .Rendering_Limit_Fps:
        return boolean_value(preferences.rendering.limit_fps)
    case .Rendering_Simd:
        return boolean_value(preferences.rendering.simd)
    case .Rendering_Gpu_Dust_Instancing:
        return boolean_value(preferences.rendering.gpu_dust_instancing)
    case .Drawing_Sound_Enabled:
        return boolean_value(preferences.drawing.sound_enabled)
    case .Interface_Display_Fps:
        return boolean_value(preferences.interface.display_fps)
    }
    return {}
}

// Read one typed scalar from the fixed preference record.
setting_value :: proc(preferences: Preferences, id: Setting_Id) -> Setting_Value {
    switch id {
    case .Window_Width, .Window_Height, .Drawing_Dust_Limit:
        return read_integer_preference(preferences, id)
    case .Rendering_Vsync, .Rendering_Antialiasing, .Rendering_Limit_Fps,
         .Rendering_Simd, .Rendering_Gpu_Dust_Instancing,
         .Drawing_Sound_Enabled, .Interface_Display_Fps:
        return read_boolean_preference(preferences, id)
    case .Window_Mode:
        return window_mode_value(preferences.window.mode)
    case .Window_Layout:
        return layout_preference_value(preferences.window.layout)
    }
    return {}
}

// Find the stored operation for one known setting.
change_index :: proc(changes: ^Change_Set, id: Setting_Id) -> int {
    for index in 0..<changes^.count {
        if changes^.changes[index].id == id {
            return index
        }
    }
    return -1
}

// Store a validated Set operation, replacing an older operation for its key.
change_set_set :: proc(
    changes: ^Change_Set, id: Setting_Id, value: Setting_Value) -> bool {
    if changes == nil || !valid_change_set(changes^) ||
        !valid_setting_value(id, value) {
        return false
    }
    index := change_index(changes, id)
    if index < 0 {
        if changes^.count >= SETTING_COUNT {
            return false
        }
        index = changes^.count
        changes^.count += 1
    }
    changes^.changes[index] = {id = id, kind = .Set, value = value}
    return true
}

// Store a Reset operation, replacing an older operation for its key.
change_set_reset :: proc(changes: ^Change_Set, id: Setting_Id) -> bool {
    if changes == nil || !valid_change_set(changes^) || !valid_setting_id(id) {
        return false
    }
    index := change_index(changes, id)
    if index < 0 {
        if changes^.count >= SETTING_COUNT {
            return false
        }
        index = changes^.count
        changes^.count += 1
    }
    changes^.changes[index] = {id = id, kind = .Reset}
    return true
}

// Merge newer operations over existing operations by setting identity.
change_set_merge_newer :: proc(
    destination: ^Change_Set, newer: Change_Set) -> bool {
    if destination == nil || !valid_change_set(destination^) ||
        !valid_change_set(newer) {
        return false
    }
    for index in 0..<newer.count {
        change := newer.changes[index]
        if change.kind == .Set {
            if !change_set_set(destination, change.id, change.value) {
                return false
            }
        } else if !change_set_reset(destination, change.id) {
            return false
        }
    }
    return true
}

// Restore failed older operations only where no newer pending edit exists.
merge_failed_batch :: proc(
    pending: ^Change_Set, failed: Change_Set) -> bool {
    if pending == nil || !valid_change_set(pending^) ||
        !valid_change_set(failed) {
        return false
    }
    for index in 0..<failed.count {
        change := failed.changes[index]
        if change_index(pending, change.id) >= 0 {
            continue
        }
        if pending^.count >= SETTING_COUNT {
            return false
        }
        pending^.changes[pending^.count] = change
        pending^.count += 1
    }
    return true
}

// Reject malformed externally assembled batches before any merge is applied.
valid_change_set :: proc(changes: Change_Set) -> bool {
    if changes.count < 0 || changes.count > SETTING_COUNT {
        return false
    }
    seen: Setting_Set
    for index in 0..<changes.count {
        change := changes.changes[index]
        if !valid_setting_id(change.id) || change.id in seen {
            return false
        }
        if change.kind == .Set {
            if !valid_setting_value(change.id, change.value) {
                return false
            }
        } else if change.kind != .Reset {
            return false
        }
        seen += Setting_Set{change.id}
    }
    return true
}
