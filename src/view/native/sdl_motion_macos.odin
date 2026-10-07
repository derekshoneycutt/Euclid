#+build darwin

package native

import objc "core:sys/darwin/Foundation"

@(objc_class="NSWorkspace")
Sdl_Motion_Workspace :: struct {using _: objc.Object}

// sdl_query_reduced_motion reads NSWorkspace accessibility policy on the display owner.
sdl_query_reduced_motion :: proc() -> (bool, Sdl_Motion_Status) {
    workspace := objc.msgSend(
        ^Sdl_Motion_Workspace, Sdl_Motion_Workspace, "sharedWorkspace")
    if workspace == nil {
        return false, .Failed
    }
    selector := objc.sel_registerName("accessibilityDisplayShouldReduceMotion")
    if !bool(objc.class_respondsToSelector(
        objc.object_getClass(cast(objc.id)workspace), selector)) {
        return false, .Unavailable
    }
    requested := objc.msgSend(
        objc.BOOL, workspace, "accessibilityDisplayShouldReduceMotion")
    return bool(requested), .Supported
}
