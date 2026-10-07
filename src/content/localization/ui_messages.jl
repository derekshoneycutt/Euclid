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
            "Rendered dust-particle statistic.", LocalizedContent.MessageArgument[
                LocalizedContent.MessageArgument("count",
                    LocalizedContent.Int64Argument)]),
        "Dust particles Rendered: {count}"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1210), "ui.settings.stats.trail",
            "Rendered trail-particle statistic.", LocalizedContent.MessageArgument[
                LocalizedContent.MessageArgument("count",
                    LocalizedContent.Int64Argument)]),
        "Trail particles Rendered: {count}"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1211), "ui.settings.stats.flicker",
            "Rendered flicker-particle statistic.", LocalizedContent.MessageArgument[
                LocalizedContent.MessageArgument("count",
                    LocalizedContent.Int64Argument)]),
        "Flicker particles Rendered: {count}"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1212),
            "ui.settings.stats.animation_entries",
            "Count of Julia animation entries added.", LocalizedContent.MessageArgument[
                LocalizedContent.MessageArgument("count",
                    LocalizedContent.Int64Argument)]),
        "Julia animation entries added: {count}"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1214),
            "ui.settings.save.saved", "Settings persistence is current.",
            LocalizedContent.MessageArgument[]),
        "Settings saved"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1215),
            "ui.settings.save.pending", "Settings edits are waiting to be saved.",
            LocalizedContent.MessageArgument[]),
        "Settings not saved yet"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1216),
            "ui.settings.save.saving", "Settings are being saved.",
            LocalizedContent.MessageArgument[]),
        "Saving settings..."),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1217),
            "ui.settings.save.unavailable", "Settings persistence is unavailable.",
            LocalizedContent.MessageArgument[]),
        "Settings storage unavailable"),
    LocalizedContent.UiMessageSourceDeclaration(
        LocalizedContent.UiMessageDeclaration(UInt16(1218),
            "ui.settings.save.failed", "Settings could not be saved after retries.",
            LocalizedContent.MessageArgument[]),
        "Settings could not be saved"),
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
]
