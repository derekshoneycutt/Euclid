package native

TEXTURE_OPERATION_CAPACITY :: 256
TEXTURE_UPLOAD_BYTE_CAPACITY :: 64 * 1024 * 1024

// Texture_Pixel_Format identifies one supported CPU upload representation.
Texture_Pixel_Format :: enum u8 {
    Gray_Alpha8,
    Rgb8,
    Rgba8,
}

// Sampled_Texture is one display-owned native texture with portable dimensions.
Sampled_Texture :: struct {
    handle: rawptr,
    width:  u32,
    height: u32,
}

// Texture_Operation_Kind identifies one ordered native texture mutation.
Texture_Operation_Kind :: enum u8 {
    Create,
    Update,
    Retire,
}

// Texture_Operation_Completion reports one exact native submission result.
Texture_Operation_Completion :: #type proc(
    user_data: rawptr, identity, generation: u64, succeeded: bool)

// Texture_Operation_Callback groups one optional completion and its owner context.
Texture_Operation_Callback :: struct {
    handler: Texture_Operation_Completion,
    user_data: rawptr,
}

// Texture_Upload_Request describes one complete queued create or update copy.
Texture_Upload_Request :: struct {
    kind: Texture_Operation_Kind,
    texture: Sampled_Texture,
    format: Texture_Pixel_Format,
    source: []u8,
    identity: u64,
    generation: u64,
    callback: Texture_Operation_Callback,
}

// Texture_Operation is one bounded request retaining no source pixel ownership.
Texture_Operation :: struct {
    kind:       Texture_Operation_Kind,
    texture:    rawptr,
    width:      u32,
    height:     u32,
    format:     Texture_Pixel_Format,
    source:     []u8,
    byte_offset: u32,
    byte_count: u32,
    identity:   u64,
    generation: u64,
    completion: Texture_Operation_Completion,
    user_data:  rawptr,
}

// Texture_Operation_Queue stores ordered requests in caller-owned fixed storage.
Texture_Operation_Queue :: struct {
    operations: [TEXTURE_OPERATION_CAPACITY]Texture_Operation,
    count:      int,
    byte_count: u32,
    overflow_count: u32,
}

// sampled_texture_is_valid reports whether one complete texture is drawable.
sampled_texture_is_valid :: proc(texture: Sampled_Texture) -> bool {
    return texture.handle != nil && texture.width > 0 && texture.height > 0
}

// texture_rgba8_byte_count returns the normalized resident/upload byte count.
texture_rgba8_byte_count :: proc(width, height: u32) -> (u32, bool) {
    if width == 0 || height == 0 || width > max(u32) / height / 4 {
        return 0, false
    }
    return width * height * 4, true
}

// texture_source_byte_count returns the exact source size for one pixel format.
texture_source_byte_count :: proc(
    width, height: u32, format: Texture_Pixel_Format) -> (u32, bool) {
    pixel_count := u64(width) * u64(height)
    bytes_per_pixel: u64
    switch format {
    case .Gray_Alpha8: bytes_per_pixel = 2
    case .Rgb8: bytes_per_pixel = 3
    case .Rgba8: bytes_per_pixel = 4
    }
    byte_count := pixel_count * bytes_per_pixel
    if pixel_count == 0 || byte_count > u64(max(u32)) {
        return 0, false
    }
    return u32(byte_count), true
}

// texture_normalize_rgba8 expands one supported payload into exact RGBA8 storage.
texture_normalize_rgba8 :: proc(
    destination, source: []u8, format: Texture_Pixel_Format) -> bool {
    source_stride: int
    switch format {
    case .Gray_Alpha8: source_stride = 2
    case .Rgb8: source_stride = 3
    case .Rgba8: source_stride = 4
    }
    if len(source) == 0 || len(source) % source_stride != 0 ||
        len(destination) != len(source) / source_stride * 4 {
        return false
    }
    for pixel_index in 0..<len(source) / source_stride {
        source_index := pixel_index * source_stride
        destination_index := pixel_index * 4
        switch format {
        case .Gray_Alpha8:
            gray := source[source_index]
            destination[destination_index] = gray
            destination[destination_index + 1] = gray
            destination[destination_index + 2] = gray
            destination[destination_index + 3] = source[source_index + 1]
        case .Rgb8:
            copy(destination[destination_index:destination_index + 3],
                source[source_index:source_index + 3])
            destination[destination_index + 3] = 255
        case .Rgba8:
            copy(destination[destination_index:destination_index + 4],
                source[source_index:source_index + 4])
        }
    }
    return true
}

// texture_operation_enqueue appends one complete request or rejects it atomically.
texture_operation_enqueue :: proc(
    queue: ^Texture_Operation_Queue, operation: Texture_Operation) -> bool {
    if queue == nil || queue^.count >= len(queue^.operations) ||
        operation.generation == 0 || operation.texture == nil {
        if queue != nil {queue^.overflow_count += 1}
        return false
    }
    candidate := operation
    if candidate.kind != .Retire {
        source_bytes, source_valid := texture_source_byte_count(
            candidate.width, candidate.height, candidate.format)
        rgba_bytes, rgba_valid := texture_rgba8_byte_count(
            candidate.width, candidate.height)
        if !source_valid || !rgba_valid || len(candidate.source) != int(source_bytes) {
            queue^.overflow_count += 1
            return false
        }
        candidate.byte_offset = queue^.byte_count
        candidate.byte_count = rgba_bytes
    } else {
        candidate.source = nil
        candidate.byte_offset = 0
        candidate.byte_count = 0
    }
    if candidate.byte_count > TEXTURE_UPLOAD_BYTE_CAPACITY - queue^.byte_count {
        queue^.overflow_count += 1
        return false
    }
    queue^.operations[queue^.count] = candidate
    queue^.count += 1
    queue^.byte_count += candidate.byte_count
    return true
}

// texture_operation_enqueue_upload validates and queues one create or update copy.
texture_operation_enqueue_upload :: proc(
    queue: ^Texture_Operation_Queue, request: Texture_Upload_Request) -> bool {
    if request.kind != .Create && request.kind != .Update ||
        !sampled_texture_is_valid(request.texture) {
        if queue != nil {queue^.overflow_count += 1}
        return false
    }
    return texture_operation_enqueue(queue, {
        kind = request.kind,
        texture = request.texture.handle,
        width = request.texture.width,
        height = request.texture.height,
        format = request.format,
        source = request.source,
        identity = request.identity,
        generation = request.generation,
        completion = request.callback.handler,
        user_data = request.callback.user_data,
    })
}

// texture_operation_enqueue_retire queues release after successful submission.
texture_operation_enqueue_retire :: proc(
    queue: ^Texture_Operation_Queue, texture: Sampled_Texture,
    identity, generation: u64, callback: Texture_Operation_Callback = {}) -> bool {
    if !sampled_texture_is_valid(texture) {
        if queue != nil {queue^.overflow_count += 1}
        return false
    }
    return texture_operation_enqueue(queue, {
        kind = .Retire,
        texture = texture.handle,
        identity = identity,
        generation = generation,
        completion = callback.handler,
        user_data = callback.user_data,
    })
}