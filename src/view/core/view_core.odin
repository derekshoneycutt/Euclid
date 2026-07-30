package view_core

import "../../core"
import "../../files"

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

ISO_SCALE_VALUE :: 800
ISO_X_OFFSET :: 450
ISO_Y_OFFSET :: 450

LIMIT_FPS :: 60
FIXED_DT :: 1.0 / LIMIT_FPS
MAX_FRAME_DT :: 0.25
MAX_STEPS_PER_FRAME :: 6
FPS_AVERAGE_BUCKET_COUNT :: 60

ALLOWED_CONSTRAINT_ERROR :: 0.0001

WINDOW_HEIGHT :: 720
WINDOW_WIDTH :: 1280

VIEW_HEIGHT :: 500
BOTTOM_BAR_HEIGHT :: WINDOW_HEIGHT - VIEW_HEIGHT
VIEW_WIDTH :: 900
RIGHT_BAR_WIDTH :: WINDOW_WIDTH - VIEW_WIDTH

WINDOW_TITLE :: "Euclid's Elements"

JULIA_MONO_FONT_LOAD_SIZE :: 32

BACKGROUND_COLOR :: rl.Color{36, 5, 16, 255}
TOOL_COLOR :: rl.Color{96, 72, 82, 255}

UI_BACK_COLOR :: rl.Color{66, 35, 46, 255}
UI_BORDER_COLOR :: rl.Color{86, 55, 66, 255}
UI_TEXT_COLOR :: rl.Color{175, 150, 150, 255}

UI_COMPONENT_BACKGROUND_COLOR :: rl.Color{25, 25, 25, 255}

SURFACE_COLOR :: rl.Color{25, 25, 25, 255}
SURFACE_EDGE_SIZE :: 0.05
SURFACE_EDGE_COLOR :: rl.Color{96, 65, 76, 255}


TREE_FONT_SIZE :: 16


//   Full codepoint set used for JuliaMono font loading.
JULIA_MONO_CODE_POINTS :: []rune{
		// Basic ASCII (0x20 to 0x7E)
		0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 0x29, 0x2a, 0x2b, 0x2c,
		0x2d, 0x2e, 0x2f, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39,
		0x3a, 0x3b, 0x3c, 0x3d, 0x3e, 0x3f, 0x40, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46,
		0x47, 0x48, 0x49, 0x4a, 0x4b, 0x4c, 0x4d, 0x4e, 0x4f, 0x50, 0x51, 0x52, 0x53,
		0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5a, 0x5b, 0x5c, 0x5d, 0x5e, 0x5f, 0x60,
		0x61, 0x62, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6a, 0x6b, 0x6c, 0x6d,
		0x6e, 0x6f, 0x70, 0x71, 0x72, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a,
		0x7b, 0x7c, 0x7d, 0x7e,

		// Latin-1 accented letters and ligatures (common Western/Central European text).
		0x00c0, 0x00c1, 0x00c2, 0x00c3, 0x00c4, 0x00c5, 0x00c6, 0x00c7,
		0x00c8, 0x00c9, 0x00ca, 0x00cb, 0x00cc, 0x00cd, 0x00ce, 0x00cf,
		0x00d0, 0x00d1, 0x00d2, 0x00d3, 0x00d4, 0x00d5, 0x00d6, 0x00d8,
		0x00d9, 0x00da, 0x00db, 0x00dc, 0x00dd, 0x00de,
		0x00e0, 0x00e1, 0x00e2, 0x00e3, 0x00e4, 0x00e5, 0x00e6, 0x00e7,
		0x00e8, 0x00e9, 0x00ea, 0x00eb, 0x00ec, 0x00ed, 0x00ee, 0x00ef,
		0x00f0, 0x00f1, 0x00f2, 0x00f3, 0x00f4, 0x00f5, 0x00f6, 0x00f8,
		0x00f9, 0x00fa, 0x00fb, 0x00fc, 0x00fd, 0x00fe, 0x00ff,

		// Greek and Coptic Blocks (0x370 to 0x3CE)
		0x370, 0x371, 0x372, 0x373, 0x374, 0x375, 0x376, 0x377, 0x37a, 0x37b, 0x37c,
		0x37d, 0x37e, 0x384, 0x385, 0x386, 0x388, 0x389, 0x38a, 0x38c, 0x38e, 0x38f,
		0x390, 0x391, 0x392, 0x393, 0x394, 0x395, 0x396, 0x397, 0x398, 0x399, 0x39a,
		0x39b, 0x39c, 0x39d, 0x39e, 0x39f, 0x3a0, 0x3a1, 0x3a3, 0x3a4, 0x3a5, 0x3a6,
		0x3a7, 0x3a8, 0x3a9, 0x3aa, 0x3ab, 0x3ac, 0x3ad, 0x3ae, 0x3af, 0x3b0, 0x3b1,
		0x3b2, 0x3b3, 0x3b4, 0x3b5, 0x3b6, 0x3b7, 0x3b8, 0x3b9, 0x3ba, 0x3bb, 0x3bc,
		0x3bd, 0x3be, 0x3bf, 0x3c0, 0x3c1, 0x3c2, 0x3c3, 0x3c4, 0x3c5, 0x3c6, 0x3c7,
		0x3c8, 0x3c9, 0x3ca, 0x3cb, 0x3cc, 0x3cd, 0x3ce,

		// Alphanumeric superscripts and subscripts.
		0x00b2, 0x00b3, 0x00b9, 0x2070, 0x2071, 0x2074, 0x2075, 0x2076, 0x2077,
		0x2078, 0x2079, 0x207a, 0x207b, 0x207c, 0x207d, 0x207e, 0x207f,
		0x2080, 0x2081, 0x2082, 0x2083, 0x2084, 0x2085, 0x2086, 0x2087,
		0x2088, 0x2089, 0x208a, 0x208b, 0x208c, 0x208d, 0x208e,

		// Superscript letters (Unicode-supported subset).
		0x00aa, 0x00ba, 0x02b0, 0x02b2, 0x02b3, 0x02b7, 0x02b8, 0x02e1,
		0x02e2, 0x02e3, 0x02e4, 0x1d2c, 0x1d2e, 0x1d30, 0x1d31, 0x1d33,
		0x1d34, 0x1d35, 0x1d36, 0x1d37, 0x1d38, 0x1d39, 0x1d3a, 0x1d3c,
		0x1d3e, 0x1d3f, 0x1d40, 0x1d41, 0x1d42, 0x1d43, 0x1d47, 0x1d48,
		0x1d49, 0x1d4d, 0x1d4f, 0x1d50, 0x1d52, 0x1d56, 0x1d57, 0x1d58,
		0x1d5b, 0x1d5d, 0x1d5e, 0x1d5f, 0x1d60, 0x1d61, 0x1d9c, 0x1da0,
		0x1dbb, 0x2c7d,

		// Subscript letters (Unicode-supported subset).
		0x1d62, 0x1d63, 0x1d64, 0x1d65, 0x1d66, 0x1d67, 0x1d68, 0x1d69,
		0x1d6a, 0x2090, 0x2091, 0x2092, 0x2093, 0x2094, 0x2095, 0x2096,
		0x2097, 0x2098, 0x2099, 0x209a, 0x209b, 0x209c, 0x2c7c,

		// Common math symbols beyond ASCII and Greek.
		0x002b, 0x003c, 0x003d, 0x003e, 0x007e, 0x00a7, 0x00ac, 0x00b0, 0x00b1, 0x00b2,
		0x00b3, 0x00b7, 0x00b9, 0x00d7, 0x00f7, 0x2220, 0x2032, 0x2033, 0x220e, 0x2260,
		0x2102, 0x2115, 0x211a,
		0x211d, 0x2124, 0x2190, 0x2191, 0x2192, 0x2193, 0x2194, 0x21a6, 0x21d2, 0x21d4,
		0x2200, 0x2203, 0x2205, 0x2208, 0x2209, 0x220b, 0x220f, 0x2211, 0x2212, 0x2217,
		0x221a, 0x2218, 0x221d, 0x221e, 0x2220, 0x2225, 0x2227, 0x2228, 0x2229, 0x222a,
		0x222b, 0x2234, 0x223c, 0x2248, 0x2260, 0x2261, 0x2262, 0x2264, 0x2265, 0x2282,
		0x2283, 0x2286, 0x2287, 0x2295, 0x22a5, 0x25cb, 0x2026, 0x22ca,
}

MAX_KINEPOINTS :: core.MAX_KINEPOINTS
TOOL_LENGTH :: core.TOOL_LENGTH

Vector2 :: core.Vector2
Vector3 :: core.Vector3
Iso_Scale :: core.Iso_Scale
Kine_Shape_Point_Type :: core.Kine_Shape_Point_Type
Kine_Shape_Point :: core.Kine_Shape_Point
Kine_Constraint :: core.Kine_Constraint
Kine_Point_System :: core.Kine_Point_System
Particle :: core.Particle
Particle_System :: core.Particle_System
Euclid_Drawing_Surface :: core.Euclid_Drawing_Surface
Euclid_General_State :: core.Euclid_General_State
Euclid_Run_Settings :: core.Euclid_Run_Settings

//   Return canonical weight ordering rank for heaviest-flag resolution.
font_weight_rank :: #force_inline proc(weight: core.Font_Weight) -> int {
	switch weight {
	case .Light:
		return 1
	case .Regular:
		return 2
	case .Medium:
		return 3
	case .SemiBold:
		return 4
	case .Bold:
		return 5
	case .ExtraBold:
		return 6
	case .Black:
		return 7
	}

	return 2
}

//   Return true when one requested variant-flag bit is present.
font_has_flag :: #force_inline proc(flags, flag: core.Font_Variant_Flags) -> bool {
	return (u32(flags) & u32(flag)) != 0
}

//   Resolve one weight from possibly multiple weight bits by choosing the heaviest bit set.
font_resolve_weight_from_flags :: #force_inline proc(flags: core.Font_Variant_Flags) -> core.Font_Weight {
	resolved := core.Font_Weight.Regular
	resolved_rank := font_weight_rank(resolved)

	if font_has_flag(flags, .Light) {
		rank := font_weight_rank(.Light)
		if rank > resolved_rank {
			resolved = .Light
			resolved_rank = rank
		}
	}
	if font_has_flag(flags, .Regular) {
		rank := font_weight_rank(.Regular)
		if rank > resolved_rank {
			resolved = .Regular
			resolved_rank = rank
		}
	}
	if font_has_flag(flags, .Medium) {
		rank := font_weight_rank(.Medium)
		if rank > resolved_rank {
			resolved = .Medium
			resolved_rank = rank
		}
	}
	if font_has_flag(flags, .SemiBold) {
		rank := font_weight_rank(.SemiBold)
		if rank > resolved_rank {
			resolved = .SemiBold
			resolved_rank = rank
		}
	}
	if font_has_flag(flags, .Bold) {
		rank := font_weight_rank(.Bold)
		if rank > resolved_rank {
			resolved = .Bold
			resolved_rank = rank
		}
	}
	if font_has_flag(flags, .ExtraBold) {
		rank := font_weight_rank(.ExtraBold)
		if rank > resolved_rank {
			resolved = .ExtraBold
			resolved_rank = rank
		}
	}
	if font_has_flag(flags, .Black) {
		rank := font_weight_rank(.Black)
		if rank > resolved_rank {
			resolved = .Black
			resolved_rank = rank
		}
	}

	return resolved
}

//   Resolve one static JuliaMono filename from weight and italic style.
font_variant_filename :: #force_inline proc(weight: core.Font_Weight, italic: bool) -> string {
	switch weight {
	case .Light:
		if italic {
			return "JuliaMono-LightItalic.ttf"
		}
		return "JuliaMono-Light.ttf"
	case .Regular:
		if italic {
			return "JuliaMono-RegularItalic.ttf"
		}
		return "JuliaMono-Regular.ttf"
	case .Medium:
		if italic {
			return "JuliaMono-MediumItalic.ttf"
		}
		return "JuliaMono-Medium.ttf"
	case .SemiBold:
		if italic {
			return "JuliaMono-SemiBoldItalic.ttf"
		}
		return "JuliaMono-SemiBold.ttf"
	case .Bold:
		if italic {
			return "JuliaMono-BoldItalic.ttf"
		}
		return "JuliaMono-Bold.ttf"
	case .ExtraBold:
		if italic {
			return "JuliaMono-ExtraBoldItalic.ttf"
		}
		return "JuliaMono-ExtraBold.ttf"
	case .Black:
		if italic {
			return "JuliaMono-BlackItalic.ttf"
		}
		return "JuliaMono-Black.ttf"
	}

	return "JuliaMono-Regular.ttf"
}

//   Return packed slot index for one weight/italic pair.
font_variant_slot_index :: #force_inline proc(weight: core.Font_Weight, italic: bool) -> int {
	base := 0
	switch weight {
	case .Light:
		base = 0
	case .Regular:
		base = 2
	case .Medium:
		base = 4
	case .SemiBold:
		base = 6
	case .Bold:
		base = 8
	case .ExtraBold:
		base = 10
	case .Black:
		base = 12
	}

	if italic {
		return base + 1
	}
	return base
}

//   Load one variant and return true when raylib reports a valid texture handle.
font_load_variant :: proc(state: ^core.Euclid_General_State, slot_index: int, weight: core.Font_Weight, italic: bool, font_size: i32) -> bool {
	if state == nil {
		return false
	}

	if slot_index < 0 || slot_index >= len(state^.font_runtime.variants) {
		return false
	}

	slot := &state^.font_runtime.variants[slot_index]
	if slot^.loaded {
		return true
	}

	filename := font_variant_filename(weight, italic)
	font_path := files.packaged_asset_path(filename, context.temp_allocator)
	if len(font_path) == 0 {
		if !slot^.missing_warned {
			slot^.missing_warned = true
			fmt.eprintln("font load fallback: unable to resolve asset path for ", filename)
		}
		return false
	}

	code_points := JULIA_MONO_CODE_POINTS
	code_point_count := i32(len(code_points))
	font_file := strings.clone_to_cstring(font_path, context.temp_allocator)
	font := rl.LoadFontEx(font_file, font_size, &code_points[0], code_point_count)
	if font.texture.id == 0 {
		if !slot^.missing_warned {
			slot^.missing_warned = true
			fmt.eprintln("font load fallback: failed to load ", filename)
		}
		return false
	}

	slot^.font = font
	slot^.loaded = true
	return true
}

//   Resolve or load a requested variant from flags, with fallback to Regular.
font_runtime_resolve :: proc(state: ^core.Euclid_General_State, flags: core.Font_Variant_Flags, font_size: i32) -> rl.Font {
	if state == nil {
		return rl.Font{}
	}

	requested_weight := font_resolve_weight_from_flags(flags)
	requested_italic := font_has_flag(flags, .Italic)
	requested_slot := font_variant_slot_index(requested_weight, requested_italic)

	if font_load_variant(state, requested_slot, requested_weight, requested_italic, font_size) {
		return state^.font_runtime.variants[requested_slot].font
	}

	regular_slot := state^.font_runtime.regular_slot_index
	if regular_slot < 0 || regular_slot >= len(state^.font_runtime.variants) {
		regular_slot = font_variant_slot_index(.Regular, false)
		state^.font_runtime.regular_slot_index = regular_slot
	}

	if font_load_variant(state, regular_slot, .Regular, false, font_size) {
		state^.font = state^.font_runtime.variants[regular_slot].font
		return state^.font_runtime.variants[regular_slot].font
	}

	return state^.font
}

//   Preload and set the Regular variant during startup.
font_runtime_init_with_regular :: proc(state: ^core.Euclid_General_State, font_size: i32) -> bool {
	if state == nil {
		return false
	}

	state^.font_runtime.regular_slot_index = font_variant_slot_index(.Regular, false)
	loaded := font_load_variant(state, state^.font_runtime.regular_slot_index, .Regular, false, font_size)
	if loaded {
		state^.font = state^.font_runtime.variants[state^.font_runtime.regular_slot_index].font
	}

	return loaded
}

//   Unload all lazily loaded variants and reset runtime tracking.
font_runtime_unload_all :: proc(state: ^core.Euclid_General_State) {
	if state == nil {
		return
	}

	for i in 0..<len(state^.font_runtime.variants) {
		slot := &state^.font_runtime.variants[i]
		if !slot^.loaded {
			continue
		}

		rl.UnloadFont(slot^.font)
		slot^.font = rl.Font{}
		slot^.loaded = false
	}

	state^.font = rl.Font{}
}

//   Build flags for simple bold/italic requests using Regular as default weight.
font_flags_from_bold_italic :: #force_inline proc(bold, italic: bool) -> core.Font_Variant_Flags {
	flags := core.Font_Variant_Flags.Regular
	if bold {
		flags = core.Font_Variant_Flags.Bold
	}
	if italic {
		flags = core.Font_Variant_Flags(u32(flags) | u32(core.Font_Variant_Flags.Italic))
	}
	return flags
}
