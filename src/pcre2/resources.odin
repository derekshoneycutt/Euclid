package pcre2

import "core:c"
import raw "../../libs/pcre2"

// Acquire compiled code with PCRE2 defaults; tests may fail at this API boundary.
acquire_code :: proc(
    compiled: ^Compiled, pattern: []u8, options: u32,
    error_code: ^c.int, error_offset: ^uintptr) -> ^raw.Code {
    when ODIN_TEST {
        if resource_test_reject_acquisition(compiled.test_resources) {
            error_code^ = raw.ERROR_HEAP_FAILED
            return nil
        }
    }
    empty_pattern: u8
    pattern_data := raw_data(pattern)
    if len(pattern) == 0 {
        pattern_data = &empty_pattern
    }
    handle := raw.pcre2_compile_8(
        pattern_data, uintptr(len(pattern)), options, error_code, error_offset, nil)
    when ODIN_TEST {
        resource_test_acquired(compiled.test_resources, handle)
    }
    return handle
}

// Acquire reusable match data without replacing PCRE2's allocation policy.
acquire_match_data :: proc(compiled: ^Compiled) -> ^raw.Match_Data {
    when ODIN_TEST {
        if resource_test_reject_acquisition(compiled.test_resources) {
            return nil
        }
    }
    handle := raw.pcre2_match_data_create_from_pattern_8(compiled.code, nil)
    when ODIN_TEST {
        resource_test_acquired(compiled.test_resources, handle)
    }
    return handle
}

// Acquire an execution context without a custom PCRE2 allocation context.
acquire_match_context :: proc(compiled: ^Compiled) -> ^raw.Match_Context {
    when ODIN_TEST {
        if resource_test_reject_acquisition(compiled.test_resources) {
            return nil
        }
    }
    handle := raw.pcre2_match_context_create_8(nil)
    when ODIN_TEST {
        resource_test_acquired(compiled.test_resources, handle)
    }
    return handle
}

// Release the compiled pattern through its matching PCRE2 API.
release_code :: proc(compiled: ^Compiled) {
    when ODIN_TEST {
        resource_test_released(compiled.test_resources, compiled.code)
    }
    raw.pcre2_code_free_8(compiled.code)
}

// Release reusable match storage through its matching PCRE2 API.
release_match_data :: proc(compiled: ^Compiled) {
    when ODIN_TEST {
        resource_test_released(compiled.test_resources, compiled.match_data)
    }
    raw.pcre2_match_data_free_8(compiled.match_data)
}

// Release the execution context through its matching PCRE2 API.
release_match_context :: proc(compiled: ^Compiled) {
    when ODIN_TEST {
        resource_test_released(compiled.test_resources, compiled.match_context)
    }
    raw.pcre2_match_context_free_8(compiled.match_context)
}
