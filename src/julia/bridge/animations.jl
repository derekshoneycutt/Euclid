"""
C-compatible bundle of animation callback pointers passed to the native bridge
when registering animation interfaces. Field order must match the Odin
`Animation_Callbacks` struct.
"""
struct AnimationCallbacksABI
    get_view_text::Ptr{Cvoid}
    init::Ptr{Cvoid}
    loop::Ptr{Cvoid}
    clean::Ptr{Cvoid}
end

"""
Pack the four animation callback function objects into a C-compatible
`AnimationCallbacksABI` struct by converting each to its object pointer.
"""
function _animation_callbacks_abi(get_view_text, init, loop, clean)
    AnimationCallbacksABI(
        pointer_from_objref(get_view_text), pointer_from_objref(init),
        pointer_from_objref(loop), pointer_from_objref(clean))
end

"""
Set the null animation for the application

---------

Parameters:

- `state_ptr` : The state of the Euclid application to pass to the API
- `get_view_text` : A function that should be called to retrieve the view text for the animation
- `init` : A function that should be called when the animation is being initialized
- `loop` : A function that should be called when the animation is processing a frame of the loop
- `clean` : A function that should be called when the animation is being cleaned and ended
"""
function set_null_animations(
    state_ptr::Ptr{Cvoid}, get_view_text, init, loop, clean)

    @ccall set_null_animations(state_ptr::Ptr{Cvoid},
        get_view_text::Any, init::Any, loop::Any, clean::Any)::Cvoid
end

"""
Add a new root animation for the application

---------

Parameters:

- `state_ptr` : The state of the Euclid application to pass to the API
- `get_view_text` : A function that should be called to retrieve the view text for the animation
- `init` : A function that should be called when the animation is being initialized
- `loop` : A function that should be called when the animation is processing a frame of the loop
- `clean` : A function that should be called when the animation is being cleaned and ended
- `name` : The name of the animation to show in the tree
- `stable_id` : Canonical UUID string used as stable animation identity

Returns 1 on success and -1 on failure
"""
function add_root_animation_interface(
    state_ptr::Ptr{Cvoid}, get_view_text, init, loop, clean, name::String,
    stable_id::String)

    callbacks = _animation_callbacks_abi(get_view_text, init, loop, clean)
    GC.@preserve get_view_text init loop clean begin
        @ccall add_root_animation_interface(
            state_ptr::Ptr{Cvoid}, callbacks::Ref{AnimationCallbacksABI},
            name::Cstring, stable_id::Cstring)::Int64
    end
end

"""
Add a new child animation for the application

---------

Parameters:

- `state_ptr` : The state of the Euclid application to pass to the API
- `get_view_text` : A function that should be called to retrieve the view text for the animation
- `init` : A function that should be called when the animation is being initialized
- `loop` : A function that should be called when the animation is processing a frame of the loop
- `clean` : A function that should be called when the animation is being cleaned and ended
- `name` : The name of the animation to show in the tree
- `stable_id` : Canonical UUID string used as stable animation identity
- `parent_stable_id` : Canonical UUID string of the parent animation node

Returns 1 on success and -1 on failure
"""
function add_child_animation_interface(
    state_ptr::Ptr{Cvoid}, get_view_text, init, loop, clean, name::String,
    stable_id::String, parent_stable_id::String)

    callbacks = _animation_callbacks_abi(get_view_text, init, loop, clean)
    GC.@preserve get_view_text init loop clean begin
        @ccall add_child_animation_interface(
            state_ptr::Ptr{Cvoid}, callbacks::Ref{AnimationCallbacksABI},
            name::Cstring, stable_id::Cstring, parent_stable_id::Cstring)::Int64
    end
end

"""
Notify the native host that the current animation has reached a cycle boundary.

------

Parameters:

- `state_ptr` : The Euclid application state pointer passed to the native API
"""
function notify_animation_cycle_boundary(state_ptr::Ptr{Cvoid})
    @ccall notify_animation_cycle_boundary(state_ptr::Ptr{Cvoid})::Cvoid
end

"""
Get the native bridge version number.

------

Returns: `Int32` bridge API version
"""
function get_bridge_version()
    @ccall get_bridge_version()::Int32
end

"""
Get the native bridge feature flags bitmask.

------

Returns: `Int32` feature flags
"""
function get_bridge_feature_flags()
    @ccall get_bridge_feature_flags()::Int32
end
