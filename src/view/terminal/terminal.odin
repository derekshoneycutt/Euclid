package terminalview

import "../../core/protocol"
import termgrid "../../terminal/grid"
import termemulator "../../terminal/emulator"

import rl "vendor:raylib"

// Primary Julia prompt for normal evaluation mode.
TERMINAL_PROMPT :: "julia> "

// Primary Julia prompt for help-query mode.
TERMINAL_HELP_PROMPT :: "help?> "

// Primary Julia prompt for package-manager mode.
TERMINAL_PKG_PROMPT :: "pkg> "

// Primary prompt for shell-command mode.
TERMINAL_SHELL_PROMPT :: "shell> "

// Fixed-width prefix aligning continuation lines with primary prompt input.
TERMINAL_CONTINUATION_PROMPT :: "       "

// Monospace terminal font height in screen pixels.
TERMINAL_FONT_SIZE :: f32(16)

// Additional vertical pixels between terminal baselines.
TERMINAL_LINE_SPACING :: f32(4)

// Preserve native monospace advances so contextual-alternate glyphs join cleanly.
TERMINAL_TEXT_SPACING :: f32(0)

// Inset in pixels between the terminal rectangle and drawable content.
TERMINAL_PADDING :: f32(10)

// Quiet time after editing before an automatic completion request is emitted.
TERMINAL_COMPLETION_DEBOUNCE_SECONDS :: f64(0.12)

// Default terminal foreground color.
TERMINAL_TEXT_COLOR :: rl.RAYWHITE

// Matches view.BACKGROUND_COLOR so glyphs read as inverted under the cursor block.
TERMINAL_CURSOR_TEXT_COLOR :: rl.Color{36, 5, 16, 255}

// Prompt colors distinguish Julia's four input modes.
TERMINAL_PROMPT_COLOR :: rl.Color{0x38, 0x98, 0x26, 0xFF}
TERMINAL_HELP_PROMPT_COLOR :: rl.Color{0xD4, 0xB0, 0x06, 0xFF}
TERMINAL_PKG_PROMPT_COLOR :: rl.Color{0x40, 0x63, 0xD8, 0xFF}
TERMINAL_SHELL_PROMPT_COLOR :: rl.Color{0xCB, 0x3C, 0x33, 0xFF}

// Muted foreground used for noncommitted inline completion insertion.
TERMINAL_COMPLETION_PREVIEW_COLOR :: rl.Color{0x59, 0x59, 0x59, 0xFF}

// Termhist history-entry tags recording which prompt mode submitted a line.
TERMINAL_HISTORY_TAG_NORMAL :: 0
TERMINAL_HISTORY_TAG_HELP :: 1
TERMINAL_HISTORY_TAG_PKG :: 2
TERMINAL_HISTORY_TAG_SHELL :: 3

// Initial byte capacity of termhist's recyclable editable text storage.
TERMINAL_INITIAL_TEXT_CAPACITY :: 128

// Initial command-entry capacity of termhist history storage.
TERMINAL_INITIAL_HISTORY_CAPACITY :: 64

// Initial primary and alternate terminal viewport width in character cells.
TERMINAL_GRID_COLUMNS :: 128

// Initial primary and alternate terminal viewport height in character cells.
TERMINAL_GRID_ROWS :: 34

// Inclusive terminal geometry policy used for viewport-derived candidates.
TERMINAL_DIMENSION_LIMITS :: protocol.Terminal_Dimension_Limits{
    minimum = {columns = 20, rows = 4},
    maximum = {columns = 256, rows = 128},
}

TERMINAL_SYNCHRONIZED_OUTPUT_DEADLINE_SECONDS :: 0.250

// Stable terminal support implemented by rendering, parsing, and input encoding.
TERMINAL_CAPABILITIES :: protocol.Terminal_Capabilities{
    version = protocol.TERMINAL_CAPABILITY_VERSION,
    encoding = .Utf8,
    color = .Truecolor,
    modify_other_keys_level = 2,
    kitty_keyboard_flags = termemulator.KITTY_KEYBOARD_SUPPORTED_FLAGS,
    features = {
        .Alternate_Screen,
        .Bracketed_Paste,
        .Focus_Events,
        .Sgr_Mouse,
        .Query_Modify_Other_Keys,
        .Query_Kitty_Keyboard,
        .Query_Primary_Device_Attributes,
        .Query_Secondary_Device_Attributes,
        .Query_Device_Status,
        .Query_Cursor_Position,
        .Query_Private_Mode_Status,
        .Query_Window_Pixels,
        .Query_Cell_Pixels,
        .Query_Text_Area_Size,
        .Kitty_Graphics,
        .Sixel_Graphics,
        .Iterm2_Inline_Images,
        .Hyperlinks,
        .Clipboard_Writes,
        .Synchronized_Output,
    },
}

// Maximum exact-cell rows retained behind the primary terminal viewport.
TERMINAL_SCROLLBACK_ROWS :: 1024

// Maximum supported row width and bounded cells shaped in one stack workspace.
TERMINAL_MAX_COLUMNS :: int(TERMINAL_DIMENSION_LIMITS.maximum.columns)
TERMINAL_SHAPING_RUN_COLUMNS :: TERMINAL_GRID_COLUMNS
TERMINAL_SHAPING_CAPACITY ::
    TERMINAL_SHAPING_RUN_COLUMNS * termgrid.CELL_GRAPHEME_CAPACITY
TERMINAL_COMMAND_SEARCH_TEXT_BYTE_CAPACITY :: 4096
TERMINAL_COMMAND_SEARCH_POSITION_CAPACITY ::
    TERMINAL_COMMAND_SEARCH_TEXT_BYTE_CAPACITY + 1
