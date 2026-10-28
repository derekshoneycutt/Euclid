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
        "Enter: recall   Esc: cancel"),
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
