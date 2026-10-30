const UiMessageSources = LocalizedContent.UiMessageSourceDeclaration[
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1001), "ui.navigation.library",
            "Portrait and landscape accordion header.",
            LocalizedContent.MessageArgument[]),
        "Library"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1002), "ui.gif.save",
            "GIF section header and idle capture action.",
            LocalizedContent.MessageArgument[]),
        "Save GIF"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1003), "ui.navigation.settings",
            "Portrait and landscape accordion header.",
            LocalizedContent.MessageArgument[]),
        "Settings"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1004), "ui.animation.default_title",
            "Fallback title when no animation is selected.",
            LocalizedContent.MessageArgument[]),
        "Animation"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1005),
            "ui.presentation.accessible_label",
            "Accessible name for the presentation panel.",
            LocalizedContent.MessageArgument[]),
        "Presentation"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1006),
            "ui.library.tree_accessible_label",
            "Accessible name for the animation tree.",
            LocalizedContent.MessageArgument[]),
        "Animation library"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1007), "ui.context_menu.label",
            "Accessible name for the transient context menu.",
            LocalizedContent.MessageArgument[]),
        "Context menu"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1008), "ui.context_menu.copy",
            "Copy the originating pane's current selection.",
            LocalizedContent.MessageArgument[]),
        "Copy"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1009), "ui.context_menu.select_all",
            "Select the complete current presentation.",
            LocalizedContent.MessageArgument[]),
        "Select All"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1010), "ui.context_menu.paste",
            "Paste through the current Terminal input owner.",
            LocalizedContent.MessageArgument[]),
        "Paste"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1011), "ui.terminal.accessible_label",
            "Content-free accessible name for the Terminal pane.",
            LocalizedContent.MessageArgument[]),
        "Terminal"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1020), "ui.terminal.history.query",
            "Unboxed Terminal history query label.",
            LocalizedContent.MessageArgument[]),
        "History search: "),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1021), "ui.terminal.history.hints",
            "Terminal history recall and cancellation hints.",
            LocalizedContent.MessageArgument[]),
        "?: help   Enter: recall   Esc: cancel"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1022), "ui.terminal.history.compact",
            "Terminal history minimum-size instruction.",
            LocalizedContent.MessageArgument[]),
        "Enlarge Terminal to explore history. Esc: cancel"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1023), "ui.terminal.history.searching",
            "History scan is still in progress, not an empty result.",
            LocalizedContent.MessageArgument[]),
        "Searching history..."),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1024), "ui.terminal.history.empty",
            "Exhausted history scan with no matches.",
            LocalizedContent.MessageArgument[]),
        "No matching history"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1025), "ui.terminal.history.unavailable",
            "History store unavailable.",
            LocalizedContent.MessageArgument[]),
        "Terminal history unavailable"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1026), "ui.terminal.history.failed",
            "History scan failed.",
            LocalizedContent.MessageArgument[]),
        "History search failed"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1027), "ui.terminal.history.capacity",
            "History query or result exceeded bounded capacity.",
            LocalizedContent.MessageArgument[]),
        "History capacity exceeded"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1028), "ui.terminal.history.ready",
            "A working history page is loaded; not a whole-history count.",
            LocalizedContent.MessageArgument[]),
        "Loaded history"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1029), "ui.terminal.history.preview",
            "Accessible name for the scrollable exact-source preview.",
            LocalizedContent.MessageArgument[]),
        "History source preview"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1030), "ui.terminal.history.preview_loading",
            "Selected history source is loading.",
            LocalizedContent.MessageArgument[]),
        "Loading source..."),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1031), "ui.terminal.history.preview_failed",
            "Selected history source could not be loaded.",
            LocalizedContent.MessageArgument[]),
        "Source preview failed"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1032), "ui.terminal.history.preview_capacity",
            "Selected history source exceeded preview capacity.",
            LocalizedContent.MessageArgument[]),
        "Source exceeds preview capacity"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1033), "ui.terminal.history.age_now",
            "Recent or future-dated history submission.",
            LocalizedContent.MessageArgument[]),
        "now"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1034), "ui.terminal.history.age_seconds",
            "Compact history age in seconds.",
            LocalizedContent.MessageArgument[
                LocalizedContent.MessageArgument("count", LocalizedContent.Int64Argument)]),
        "{count}s"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1035), "ui.terminal.history.age_minutes",
            "Compact history age in minutes.",
            LocalizedContent.MessageArgument[
                LocalizedContent.MessageArgument("count", LocalizedContent.Int64Argument)]),
        "{count}m"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1036), "ui.terminal.history.age_hours",
            "Compact history age in hours.",
            LocalizedContent.MessageArgument[
                LocalizedContent.MessageArgument("count", LocalizedContent.Int64Argument)]),
        "{count}h"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1037), "ui.terminal.history.age_days",
            "Compact history age in days.",
            LocalizedContent.MessageArgument[
                LocalizedContent.MessageArgument("count", LocalizedContent.Int64Argument)]),
        "{count}d"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1038), "ui.terminal.history.help_short",
            "Short history syntax help; prefixes and key names are literal.",
            LocalizedContent.MessageArgument[]),
        "History search: words match source; spaces require all words. Semicolons separate conditions."),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1039), "ui.terminal.history.help_grammar",
            "Extended history grammar and limitations, using native query semantics.",
            LocalizedContent.MessageArgument[]),
        "Regexes use PCRE2, e.g. /(?i)Foo; no closing slash is needed. Inline flags can override regex case behavior."),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1040), "ui.terminal.history.help_keys",
            "Extended help for actual Euclid bindings, bounds, and duplicate policy.",
            LocalizedContent.MessageArgument[]),
        "Up/Down or Ctrl+P/N: select. Enter recalls exact source into the draft; it never runs the entry."),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1041), "ui.terminal.history.help_hints",
            "Help footer; help never accepts a candidate.",
            LocalizedContent.MessageArgument[]),
        "??: details   Up/Down: scroll   Esc: restore search"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1042), "ui.terminal.history.help_compact",
            "Readable minimum-size help instructions.",
            LocalizedContent.MessageArgument[]),
        "History help: enlarge Terminal to read syntax. Esc: restore search. Enter does nothing."),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1043), "ui.terminal.history.skipped",
            "Nonblocking malformed-regex notice, including invalid-only browse behavior.",
            LocalizedContent.MessageArgument[]),
        "Malformed regex skipped; ?? explains syntax. No remaining conditions browses all history."),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1044), "ui.terminal.history.ranges_failed",
            "Nonblocking emphasis failure; exact source and recall remain usable.",
            LocalizedContent.MessageArgument[]),
        "Match emphasis unavailable (range/resource limit or stale source); recall is unchanged."),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1045), "ui.terminal.history.resource_failed",
            "Native memory or regex execution failure, not a malformed-pattern skip.",
            LocalizedContent.MessageArgument[]),
        "Search resource or regex execution limit reached; simplify the query."),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1046), "ui.terminal.history.sql_failed",
            "SQLite execution failure, not an empty result.",
            LocalizedContent.MessageArgument[]),
        "History database search failed."),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1047), "ui.terminal.history.cancelled",
            "Intentional search interruption.",
            LocalizedContent.MessageArgument[]),
        "History search cancelled."),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1048), "ui.terminal.history.invalid_query",
            "Invalid query bytes or query bounds, distinct from skipped explicit regex.",
            LocalizedContent.MessageArgument[]),
        "Invalid history query or query limit exceeded."),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1049), "ui.terminal.history.help_label",
            "Accessible label for the in-place history help document.",
            LocalizedContent.MessageArgument[]),
        "History search help"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1050), "ui.terminal.history.help_prefixes",
            "Short help for text operators; preserve literal query prefixes.",
            LocalizedContent.MessageArgument[]),
        "=text: exact substring   !text: exclude   /pattern: regex   `abbr: initialism   ~text: fuzzy"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1051), "ui.terminal.history.help_modes",
            "Native mode names and union semantics.",
            LocalizedContent.MessageArgument[]),
        "julia>, help>, pkg>, shell>: modes. Multiple modes form a union, then combine with text conditions."),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1052), "ui.terminal.history.help_matches",
            "Explain the non-destructive positive-match cue.",
            LocalizedContent.MessageArgument[]),
        "Overlines mark positive matches without changing syntax faces. Exclusions and modes have no source emphasis."),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1053), "ui.terminal.history.help_usage",
            "Short help interaction and restoration.",
            LocalizedContent.MessageArgument[]),
        "?: help   ??: details   Esc: restore search   Enter: no action in help. Edit the query to search again."),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1054), "ui.terminal.history.help_case",
            "Segment-wide smart case for ordinary terms.",
            LocalizedContent.MessageArgument[]),
        "Smart case: uppercase in an ordinary semicolon segment makes all its words case-sensitive; otherwise they ignore case."),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1055), "ui.terminal.history.help_escapes",
            "Query escape syntax examples.",
            LocalizedContent.MessageArgument[]),
        "Escape semicolons with \\; e.g. =a\\;b. Other backslashes are preserved, including regex escapes such as /\\d+."),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1056), "ui.terminal.history.help_skips",
            "Malformed-pattern compatibility, distinct from real errors.",
            LocalizedContent.MessageArgument[]),
        "Malformed regex conditions are skipped. No effective conditions browses all history. Memory/execution failures are errors."),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1057), "ui.terminal.history.help_fuzzy",
            "Generated abbreviation matching examples.",
            LocalizedContent.MessageArgument[]),
        "~fb matches with gaps (fuzzy); `fb follows word/camel boundaries (initialism), e.g. fooBar."),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1058), "ui.terminal.history.help_pages",
            "Actual chronological paging and edge bindings.",
            LocalizedContent.MessageArgument[]),
        "PageUp/PageDown or Alt+V/Ctrl+V: adjacent page. Alt+Shift+< / >: oldest/newest."),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1059), "ui.terminal.history.help_scroll",
            "Actual independent source and help scrolling bindings.",
            LocalizedContent.MessageArgument[]),
        "Alt+PageUp/PageDown or preview wheel: scroll source. In help, Up/Down, PageUp/PageDown and wheel scroll help."),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1060), "ui.terminal.history.help_limits",
            "Bounded query and presentation storage.",
            LocalizedContent.MessageArgument[]),
        "Limits: 1024 query UTF-8 bytes, 64 conditions, 256 ranges per page or preview. Source stays readable if emphasis cannot fit."),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1061), "ui.terminal.history.help_duplicates",
            "Euclid chronology and duplicate policy.",
            LocalizedContent.MessageArgument[]),
        "Equal distinct submissions stay separate. Linked saved/session copies appear once. Recall preserves original source and mode."),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1101), "ui.library.search_input",
            "Search input label and placeholder.",
            LocalizedContent.MessageArgument[]),
        "Search animations"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1102), "ui.library.clear_search",
            "Visible and accessible clear-search action.",
            LocalizedContent.MessageArgument[]),
        "Clear search"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1103),
            "ui.library.search_status_label",
            "Accessible name for the Library search status.",
            LocalizedContent.MessageArgument[]),
        "Library search status"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1104),
            "ui.library.suggestion_prompt",
            "Visible search correction prompt.",
            LocalizedContent.MessageArgument[]),
        "Did you mean..."),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1105),
            "ui.library.suggestion_action_fallback",
            "Defensive fallback for an undersized suggestion label.",
            LocalizedContent.MessageArgument[]),
        "Use suggested search"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1106),
            "ui.library.suggestion_action",
            "Accessible search correction action.",
            LocalizedContent.MessageArgument[
                LocalizedContent.MessageArgument("query",
                    LocalizedContent.TextArgument)]),
        "Use suggested search: {query}"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1107), "ui.library.status.invalid",
            "Library search status for an invalid query.",
                LocalizedContent.MessageArgument[]),
        "Search query is invalid"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1108), "ui.library.status.searching",
            "Library search status while results are loading.",
                LocalizedContent.MessageArgument[]),
        "Searching animations"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1109),
            "ui.library.status.no_matches",
            "Library search status when no result matches.",
                LocalizedContent.MessageArgument[]),
        "No matching animations"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1110),
            "ui.library.status.match_count",
            "Library search result count.", LocalizedContent.MessageArgument[
                LocalizedContent.MessageArgument("count",
                    LocalizedContent.UInt32Argument)]),
        "Matching animations: {count}"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1111),
            "ui.library.status.match_count_more",
            "Library search count when more results remain.",
                LocalizedContent.MessageArgument[
                LocalizedContent.MessageArgument("count",
                    LocalizedContent.UInt32Argument)]),
        "Matching animations: {count} or more"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1112), "ui.library.actions_for",
            "Accessible disclosure and drawer name for a selected Favorite.",
            LocalizedContent.MessageArgument[
                LocalizedContent.MessageArgument("name", LocalizedContent.TextArgument)]),
        "Actions for {name}"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1113), "ui.library.move_up",
            "Move the selected Favorite one sibling position upward.",
            LocalizedContent.MessageArgument[]),
        "Move Up"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1114), "ui.library.move_down",
            "Move the selected Favorite one sibling position downward.",
            LocalizedContent.MessageArgument[]),
        "Move Down"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1115),
            "ui.library.unicode_completion",
            "Accessible inline Unicode completion hint, not an input value or Tab stop.",
            LocalizedContent.MessageArgument[
                LocalizedContent.MessageArgument("symbol", LocalizedContent.TextArgument)]),
        "Unicode completion: {symbol}. Press Right Arrow to insert; Escape to dismiss."),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1116), "ui.library.entry_name",
            "Accessible label for the single collection or placement name editor.",
            LocalizedContent.MessageArgument[]),
        "Library name"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1117), "ui.library.create_collection",
            "Accessible name of the selected Collections root's plus button.",
            LocalizedContent.MessageArgument[]),
        "Create collection"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1118), "ui.library.new_collection",
            "Initial durable name of a custom collection; duplicate names are permitted.",
            LocalizedContent.MessageArgument[]),
        "New Collection"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1119), "ui.library.delete_collection",
            "First activation warns; collection deletion requires deliberate confirmation.",
            LocalizedContent.MessageArgument[]),
        "Delete collection"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1120), "ui.library.confirm_delete",
            "Armed collection deletion warning; rapid repeated activation cannot confirm.",
            LocalizedContent.MessageArgument[]),
        "Confirm delete"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1219), "ui.settings.reduce_motion",
            "Interface-only reduced motion checkbox; system requests also apply.",
            LocalizedContent.MessageArgument[]),
        "Reduce interface motion"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1220),
            "ui.settings.system_reduce_motion",
            "Settings notice when the platform independently requests reduced motion.",
            LocalizedContent.MessageArgument[]),
        "System requests reduced motion"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1223),
            "ui.settings.increased_contrast",
            "Increased interface contrast checkbox; system requests also apply.",
            LocalizedContent.MessageArgument[]),
        "Increased contrast"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1224),
            "ui.settings.system_increased_contrast",
            "Settings notice when the platform independently requests increased contrast.",
            LocalizedContent.MessageArgument[]),
        "System requests increased contrast"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1225),
            "ui.settings.text_size",
            "Interface text-size slider label; applies to interface, Dynview, and Terminal text.",
            LocalizedContent.MessageArgument[]),
        "Text size"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1226),
            "ui.settings.section.accessibility",
            "Settings section heading for accessibility preferences.",
            LocalizedContent.MessageArgument[]),
        "Accessibility"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1227),
            "ui.settings.section.particles",
            "Settings section heading for particle preferences and statistics.",
            LocalizedContent.MessageArgument[]),
        "Particles"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1228),
            "ui.settings.section.other",
            "Settings section heading for the Julia animation count and other settings.",
            LocalizedContent.MessageArgument[]),
        "Other Settings"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1229),
            "ui.settings.section.history",
            "Settings section heading for Terminal history retention and deletion.",
            LocalizedContent.MessageArgument[]),
        "History"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1230),
            "ui.settings.persist_terminal_history",
            "Opt-in checkbox for retaining submitted Terminal history between launches.",
            LocalizedContent.MessageArgument[]),
        "Persist Terminal History"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1231),
            "ui.settings.delete_terminal_history",
            "First activation arms deletion of all submitted Terminal history.",
            LocalizedContent.MessageArgument[]),
        "Delete Terminal History"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1232),
            "ui.settings.confirm_delete_terminal_history",
            "Armed destructive action requiring a second activation to delete history.",
            LocalizedContent.MessageArgument[]),
        "Confirm Delete"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1233),
            "ui.settings.history_delete.confirm_value",
            "Accessible state explaining that a second activation confirms deletion.",
            LocalizedContent.MessageArgument[]),
        "Confirmation required; activate again to delete Terminal history."),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1234),
            "ui.settings.history_delete.pending",
            "Terminal history deletion was accepted and is waiting for database commit.",
            LocalizedContent.MessageArgument[]),
        "Deleting Terminal history..."),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1235),
            "ui.settings.history_delete.succeeded",
            "Terminal history deletion completed successfully.",
            LocalizedContent.MessageArgument[]),
        "Terminal history deleted."),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1236),
            "ui.settings.history_delete.failed",
            "Terminal history deletion failed; retained history remains available.",
            LocalizedContent.MessageArgument[]),
        "Terminal history could not be deleted."),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1237),
            "ui.settings.animation_scale",
            "Animation ink-size slider label.",
            LocalizedContent.MessageArgument[]),
        "Animation scale"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1238),
            "ui.settings.animation_scale.tooltip",
            "Tooltip describing the animation ink-size multiplier and default.",
            LocalizedContent.MessageArgument[]),
        "Scales animation ink after viewport fitting; 100% preserves authored sizing."),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1239),
            "ui.settings.animation_scale.default",
            "Displayed animation scale value when the saved preference is at default.",
            LocalizedContent.MessageArgument[]),
        "100% (Default)"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1240),
            "ui.settings.monochrome",
            "Persisted monochrome animation preference checkbox label.",
            LocalizedContent.MessageArgument[]),
        "Monochrome"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1241),
            "ui.settings.hover_focus",
            "Opt-in checkbox label for moving keyboard focus with pointer hover.",
            LocalizedContent.MessageArgument[]),
        "Focus follows mouse hover"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1242),
            "ui.settings.hover_focus.tooltip",
            "Explains that hover focus does not activate controls or move input carets.",
            LocalizedContent.MessageArgument[]),
        "Move keyboard focus as the pointer moves. Hover does not activate controls or change input carets."),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1243),
            "ui.settings.control_size",
            "Label for the non-font interface control-size slider.",
            LocalizedContent.MessageArgument[]),
        "Control size"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1244),
            "ui.settings.control_size.tooltip",
            "Explains the control-size scale and its independence from text and animation size.",
            LocalizedContent.MessageArgument[]),
        "Scales interface controls and pointer targets without changing text or animation geometry."),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1245),
            "ui.settings.show_magnifier",
            "Opt-in checkbox label for the pointer-following display magnifier.",
            LocalizedContent.MessageArgument[]),
        "Show magnifier"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1246),
            "ui.settings.show_magnifier.tooltip",
            "Explains that the magnifier enlarges a visual sample but does not enlarge pointer targets.",
            LocalizedContent.MessageArgument[]),
        "Magnifies a view of the completed frame near the pointer. It does not change hit targets."),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1247),
            "ui.settings.magnifier_input_lock",
            "Opt-in checkbox label for locking the magnifier to an eligible text caret.",
            LocalizedContent.MessageArgument[]),
        "Lock magnifier to text input"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1248),
            "ui.settings.magnifier_input_lock.tooltip",
            "Explains that input lock follows visible focused carets and never falls back to pointer mode.",
            LocalizedContent.MessageArgument[]),
        "Shows the magnifier only at a visible focused text caret. It hides when no eligible input is focused."),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1201), "ui.settings.display_fps",
            "Display FPS checkbox label.", LocalizedContent.MessageArgument[]),
        "Display FPS"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1202), "ui.settings.limit_fps",
            "Limit FPS checkbox label.", LocalizedContent.MessageArgument[]),
        "Limit FPS"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1203), "ui.settings.drawing_sound",
            "Drawing sound checkbox label.", LocalizedContent.MessageArgument[]),
        "Enable Drawing Sound"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1204), "ui.settings.simd_available",
            "SIMD projection checkbox when available.",
                LocalizedContent.MessageArgument[]),
        "Use SIMD Projection"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1205),
            "ui.settings.simd_unavailable",
            "Disabled SIMD projection checkbox label.",
                LocalizedContent.MessageArgument[]),
        "Use SIMD Projection (Unavailable)"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1206),
            "ui.settings.gpu_dust_available",
            "GPU dust checkbox when available.", LocalizedContent.MessageArgument[]),
        "GPU Dust Instancing"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1207),
            "ui.settings.gpu_dust_unavailable",
            "Disabled GPU dust checkbox label.", LocalizedContent.MessageArgument[]),
        "GPU Dust Instancing (Unavailable)"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1208), "ui.settings.maximum_dust",
            "Maximum dust slider label and accessible name.",
                LocalizedContent.MessageArgument[]),
        "Maximum Dust particles"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1209), "ui.settings.stats.dust",
            "Peak rendered dust count in the previous five-second interval.",
            LocalizedContent.MessageArgument[
                LocalizedContent.MessageArgument("count",
                    LocalizedContent.Int64Argument)]),
        "Dust particles Rendered: {count}"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1210), "ui.settings.stats.trail",
            "Peak rendered trail count in the previous five-second interval.",
            LocalizedContent.MessageArgument[
                LocalizedContent.MessageArgument("count",
                    LocalizedContent.Int64Argument)]),
        "Trail particles Rendered: {count}"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1211), "ui.settings.stats.flicker",
            "Peak rendered flicker count in the previous five-second interval.",
            LocalizedContent.MessageArgument[
                LocalizedContent.MessageArgument("count",
                    LocalizedContent.Int64Argument)]),
        "Flicker particles Rendered: {count}"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1221), "ui.settings.stats.ui_dust",
            "Peak total live UI dust count in the previous five-second interval.",
            LocalizedContent.MessageArgument[
                LocalizedContent.MessageArgument("count",
                    LocalizedContent.Int64Argument)]),
        "UI Dust particles: {count}"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1222), "ui.settings.stats.interval",
            "Explains the particle counters' fixed five-second peak reporting.",
            LocalizedContent.MessageArgument[]),
        "Peaks per 5-second interval."),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1212),
            "ui.settings.stats.animation_entries",
            "Count of Julia animation entries added.", LocalizedContent.MessageArgument[
                LocalizedContent.MessageArgument("count",
                    LocalizedContent.Int64Argument)]),
        "Julia animation entries added: {count}"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1214),
            "ui.settings.save.saved", "User-data persistence is current.",
            LocalizedContent.MessageArgument[]),
        "User data saved"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1215),
            "ui.settings.save.pending",
            "Accepted user-data changes are waiting to be saved.",
            LocalizedContent.MessageArgument[]),
        "User data not saved yet"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1216),
            "ui.settings.save.saving", "User data is being saved.",
            LocalizedContent.MessageArgument[]),
        "Saving user data..."),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1217),
            "ui.settings.save.unavailable", "User-data storage is unavailable.",
            LocalizedContent.MessageArgument[]),
        "User-data storage unavailable"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1218),
            "ui.settings.save.failed", "User data could not be saved.",
            LocalizedContent.MessageArgument[]),
        "User data could not be saved"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1213), "ui.fps.overlay",
            "Optional rolling FPS overlay; retain one decimal place.",
            LocalizedContent.MessageArgument[
                LocalizedContent.MessageArgument("fps",
                    LocalizedContent.Float32OneDecimalArgument)]),
        "FPS {fps}"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1301), "ui.gif.output_scale",
            "GIF output-scale control label.", LocalizedContent.MessageArgument[]),
        "Output scale"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1302), "ui.gif.capture_every",
            "GIF capture cadence label and accessible name.",
                LocalizedContent.MessageArgument[]),
        "Capture every"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1303), "ui.gif.playback_timing",
            "GIF playback-timing selector label.", LocalizedContent.MessageArgument[]),
        "Playback timing"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1304), "ui.gif.timing.animation",
            "Animation-timing option.", LocalizedContent.MessageArgument[]),
        "Animation"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1305), "ui.gif.timing.recorded",
            "Recorded-timing option.", LocalizedContent.MessageArgument[]),
        "Recorded"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1306),
            "ui.gif.timing.animation_description",
            "Accessible description for animation timing.",
            LocalizedContent.MessageArgument[]),
        "Use animation timing"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1307),
            "ui.gif.timing.recorded_description",
            "Accessible description for recorded timing.",
            LocalizedContent.MessageArgument[]),
        "Use recorded timing"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1308),
            "ui.gif.downsample_accessible",
            "Accessible name for the GIF downsample slider.",
            LocalizedContent.MessageArgument[]),
        "Downsample"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1309),
            "ui.gif.saved_path.label",
            "Visible label for the saved GIF path.",
            LocalizedContent.MessageArgument[]),
        "Path"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1310),
            "ui.gif.saved_path.accessible",
            "Accessible name for the saved-path input.",
            LocalizedContent.MessageArgument[]),
        "Saved GIF path"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1311),
            "ui.gif.output_scale.100",
            "Output-scale value for full-resolution capture.",
            LocalizedContent.MessageArgument[]),
        "100%"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1312),
            "ui.gif.output_scale.50",
            "Output-scale value for half-resolution capture.",
            LocalizedContent.MessageArgument[]),
        "50%"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1313),
            "ui.gif.output_scale.33",
            "Output-scale value for one-third-resolution capture.",
            LocalizedContent.MessageArgument[]),
        "33%"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1314),
            "ui.gif.output_scale.25",
            "Output-scale value for quarter-resolution capture.",
            LocalizedContent.MessageArgument[]),
        "25%"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1315),
            "ui.gif.cadence.single",
            "GIF capture cadence when every frame is captured.",
            LocalizedContent.MessageArgument[]),
        "frame"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1316),
            "ui.gif.cadence.multiple",
            "GIF capture cadence for multi-frame steps.",
            LocalizedContent.MessageArgument[
                LocalizedContent.MessageArgument("count",
            LocalizedContent.UInt32Argument)]),
        "{count} frames"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1317),
            "ui.gif.action.cancel",
            "GIF action while capture is armed.",
            LocalizedContent.MessageArgument[]),
        "Cancel GIF"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1318),
            "ui.gif.action.recording",
            "GIF action status while recording.",
            LocalizedContent.MessageArgument[]),
        "Recording..."),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1319),
            "ui.gif.action.saving",
            "GIF action status while saving.",
            LocalizedContent.MessageArgument[]),
        "Saving..."),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1320),
            "ui.gif.status.idle",
            "Visible GIF capture status while idle.",
            LocalizedContent.MessageArgument[]),
        "Status: Idle"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1321),
            "ui.gif.status.armed",
            "Visible GIF capture status while armed.",
            LocalizedContent.MessageArgument[]),
        "Status: Armed"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1322),
            "ui.gif.status.recording",
            "Visible GIF capture status with recorded frame count.",
            LocalizedContent.MessageArgument[
                LocalizedContent.MessageArgument("count",
            LocalizedContent.Int64Argument)]),
        "Status: Recording ({count} frames)"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1323),
            "ui.gif.status.saving",
            "Visible GIF capture status while finalizing.",
            LocalizedContent.MessageArgument[]),
        "Status: Saving"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1324),
            "ui.gif.status.saved",
            "Visible GIF capture status after completion.",
            LocalizedContent.MessageArgument[]),
        "Status: Saved"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1325),
            "ui.gif.status.error",
            "Visible GIF capture error status.",
            LocalizedContent.MessageArgument[]),
        "Status: Error"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1326),
            "ui.gif.accessibility.idle",
            "Accessible GIF milestone while idle.",
            LocalizedContent.MessageArgument[]),
        "GIF capture idle"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1327),
            "ui.gif.accessibility.armed",
            "Accessible GIF milestone while armed.",
            LocalizedContent.MessageArgument[]),
        "GIF capture armed"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1328),
            "ui.gif.accessibility.recording",
            "Accessible GIF milestone while recording.",
            LocalizedContent.MessageArgument[]),
        "GIF capture recording"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1329),
            "ui.gif.accessibility.saving",
            "Accessible GIF milestone while saving.", LocalizedContent.MessageArgument[]),
        "GIF capture saving"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1330),
            "ui.gif.accessibility.saved",
            "Accessible GIF milestone after saving.", LocalizedContent.MessageArgument[]),
        "GIF capture saved"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1331),
            "ui.gif.accessibility.error",
            "Accessible GIF error milestone.", LocalizedContent.MessageArgument[]),
        "GIF capture error"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1332),
            "ui.gif.error.begin",
            "Visible notice when beginning GIF capture fails.",
            LocalizedContent.MessageArgument[]),
        "Error: failed to begin GIF capture session."),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1333),
            "ui.gif.error.finalize",
            "Visible notice when finalizing the GIF file fails.",
            LocalizedContent.MessageArgument[]),
        "Error: failed to finalize GIF file."),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1334),
            "ui.gif.cancelled_during_pause",
            "Visible notice when refresh during pause cancels GIF capture.",
            LocalizedContent.MessageArgument[]),
        "Canceled: refresh during pause interrupts GIF capture."),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1335),
            "ui.gif.error.submit_frame",
            "Visible notice when submitting a GIF frame fails.",
            LocalizedContent.MessageArgument[]),
        "Error: failed to submit GIF frame."),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1336),
            "ui.gif.cancelled_window_resize",
            "Visible notice when a window resize cancels GIF capture.",
            LocalizedContent.MessageArgument[]),
        "Window resized; GIF capture cancelled."),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1401), "ui.animation.restart",
            "Accessible name for the animation restart action.",
            LocalizedContent.MessageArgument[]),
        "Restart animation"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1402), "ui.animation.pause",
            "Accessible name for the running animation pause action.",
            LocalizedContent.MessageArgument[]),
        "Pause animation"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1403), "ui.animation.resume",
            "Accessible name for the paused animation resume action.",
            LocalizedContent.MessageArgument[]),
        "Resume animation"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1404),
            "ui.animation.add_favorite",
            "Animation control tooltip for adding the selected animation to Favorites.",
            LocalizedContent.MessageArgument[]),
        "Add to Favorites"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1405),
            "ui.animation.remove_favorite",
            "Animation control tooltip for removing the selected animation from Favorites.",
            LocalizedContent.MessageArgument[]),
        "Remove from Favorites"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1406),
            "ui.animation.add_collections",
            "Animation control tooltip and title of the custom-collection checkbox popup.",
            LocalizedContent.MessageArgument[]),
        "Add to collections"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1407),
            "ui.animation.hide_controls",
            "Action label for the view's borderless eye control.",
            LocalizedContent.MessageArgument[]),
        "Hide animation controls"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1408),
            "ui.animation.show_controls",
            "Action label for the view's crossed-out eye control.",
            LocalizedContent.MessageArgument[]),
        "Show animation controls"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1409),
            "ui.animation.speed_normal",
            "Current playback rate and the speed button's next action.",
            LocalizedContent.MessageArgument[]),
        "Playback speed: 1x. Change to 2x"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1410),
            "ui.animation.speed_double",
            "Current playback rate and the speed button's next action.",
            LocalizedContent.MessageArgument[]),
        "Playback speed: 2x. Change to 4x"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1411),
            "ui.animation.speed_quadruple",
            "Current playback rate and the speed button's next action.",
            LocalizedContent.MessageArgument[]),
        "Playback speed: 4x. Change to 1x"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1412),
            "ui.animation.speed_capture",
            "Disabled playback speed during GIF arming, recording, and finalization.",
            LocalizedContent.MessageArgument[]),
        "Playback speed: 1x. Locked during GIF capture"),
]
