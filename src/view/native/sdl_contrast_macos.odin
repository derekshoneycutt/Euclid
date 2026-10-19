#+build darwin

package native

import "base:intrinsics"
import objc "core:sys/darwin/Foundation"

@(objc_class="NSWorkspace")
Sdl_Contrast_Workspace :: struct {using _: objc.Object}

// sdl_query_system_contrast reads NSWorkspace accessibility display policy.
sdl_query_system_contrast :: proc(
    _: ^Sdl_Contrast_Preference,
    should_query: bool) -> Sdl_Contrast_Query_Result {
    if !should_query {
        return {}
    }
    workspace := intrinsics.objc_send(
        ^Sdl_Contrast_Workspace, Sdl_Contrast_Workspace, "sharedWorkspace")
    if workspace == nil {
        return {status = .Failed, complete = true}
    }
    selector := objc.sel_registerName("accessibilityDisplayShouldIncreaseContrast")
    if !bool(objc.class_respondsToSelector(
        objc.object_getClass(cast(objc.id)workspace), selector)) {
        return {status = .Unavailable, complete = true}
    }
    requested := intrinsics.objc_send(
        objc.BOOL, workspace, "accessibilityDisplayShouldIncreaseContrast")
    return {requested = bool(requested), status = .Supported, complete = true}
}

// macOS contrast acquisition has no asynchronous resources to retire.
sdl_contrast_native_destroy :: proc(
    preference: ^Sdl_Contrast_Preference) {
    preference^ = {}
}
