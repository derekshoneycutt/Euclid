package viewcapture

// Package capture defines display-owned framebuffer request and result contracts.

// Consumer selected for one framebuffer acquisition.
Target :: enum u8 {
    Scenario_Png,
    Gif_Frame,
}

// Portable pixel layout exposed to capture consumers.
Pixel_Format :: enum u8 {
    Invalid,
    Rgba8,
}

// Lifecycle state for one synchronous or delayed capture operation.
Completion_Status :: enum u8 {
    Pending,
    Completed,
    Failed,
}

// Stable reason a capture operation could not produce its target.
Failure_Reason :: enum u8 {
    None,
    Invalid_Request,
    Readback_Failed,
    Normalization_Failed,
    Materialization_Failed,
}

// Presented frame and simulation step associated with one capture request.
Frame_Identity :: struct {
    presented_frame: u64,
    fixed_step: u64,
}

// Top-left framebuffer rectangle requested from the acquired image.
Region :: struct {
    x: int,
    y: int,
    width: int,
    height: int,
}

// Requested normalized output dimensions; zero preserves the cropped dimensions.
Extent :: struct {
    width: int,
    height: int,
}

// Application-owned description of one framebuffer acquisition request.
Request :: struct {
    target: Target,
    identity: Frame_Identity,
    region: Region,
    output: Extent,
    format: Pixel_Format,
}

Owned_Frame :: struct {
    pixels: []u8,
    width: int,
    height: int,
    pitch: int,
    format: Pixel_Format,
    release: Frame_Release_Proc,
}

// Backend release operation retained by one acquired frame.
Frame_Release_Proc :: proc(frame: ^Owned_Frame)

// Result of one immediate acquisition or a future delayed completion.
Completion :: struct {
    status: Completion_Status,
    failure_reason: Failure_Reason,
    target: Target,
    identity: Frame_Identity,
    frame: Owned_Frame,
    readback_bytes: u64,
    normalization_bytes: u64,
}

// Report whether one request has complete dimensions and a supported pixel format.
request_valid :: proc(request: Request) -> bool {
    region_empty := request.region.width == 0 && request.region.height == 0
    region_valid := request.region.x >= 0 && request.region.y >= 0 &&
        request.region.width > 0 && request.region.height > 0
    output_empty := request.output.width == 0 && request.output.height == 0
    output_valid := request.output.width > 0 && request.output.height > 0
    return request.format == .Rgba8 && (region_empty || region_valid) &&
        (output_empty || output_valid)
}

// Report whether one owned frame exposes complete tightly described pixel storage.
frame_valid :: proc(frame: ^Owned_Frame) -> bool {
    if frame == nil || frame.format != .Rgba8 || frame.width <= 0 ||
        frame.height <= 0 || frame.pitch < frame.width * 4 {
        return false
    }
    return len(frame.pixels) >= frame.pitch * frame.height
}

// Release one frame through its backend owner and clear its public description.
frame_release :: proc(frame: ^Owned_Frame) {
    if frame == nil {
        return
    }
    release := frame.release
    if release != nil {
        release(frame)
    }
    frame^ = {}
}
