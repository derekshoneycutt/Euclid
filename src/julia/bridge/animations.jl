"""
Set the null animation for the application

---------

Parameters:

- `state_ptr` : The state of the Euclid application to pass to the API
- `getViewText` : A function that should be called to retrieve the view text for the animation
- `init` : A function that should be called when the animation is being initialized
- `loop` : A function that should be called when the animation is processing a frame of the loop
- `clean` : A function that should be called when the animation is being cleaned and ended
"""
function set_null_animations(
    state_ptr::Ptr{Cvoid}, getViewText, init, loop, clean)

    @ccall set_null_animations(state_ptr::Ptr{Cvoid},
        getViewText::Any, init::Any, loop::Any, clean::Any)::Cvoid
end

"""
Add a new root animation for the application

---------

Parameters:

- `state_ptr` : The state of the Euclid application to pass to the API
- `getViewText` : A function that should be called to retrieve the view text for the animation
- `init` : A function that should be called when the animation is being initialized
- `loop` : A function that should be called when the animation is processing a frame of the loop
- `clean` : A function that should be called when the animation is being cleaned and ended
- `name` : The name of the animation to show in the tree
- `stable_id` : Canonical UUID string used as stable animation identity

Returns the index of the new root animation
"""
function add_root_animation_interface(
    state_ptr::Ptr{Cvoid}, getViewText, init, loop, clean, name::String, stable_id::String)

    @ccall add_root_animation_interface(
        state_ptr::Ptr{Cvoid}, getViewText::Any, init::Any, loop::Any, clean::Any,
        name::Cstring, stable_id::Cstring)::Int64
end

"""
Add a new child animation for the application

---------

Parameters:

- `state_ptr` : The state of the Euclid application to pass to the API
- `getViewText` : A function that should be called to retrieve the view text for the animation
- `init` : A function that should be called when the animation is being initialized
- `loop` : A function that should be called when the animation is processing a frame of the loop
- `clean` : A function that should be called when the animation is being cleaned and ended
- `name` : The name of the animation to show in the tree
- `stable_id` : Canonical UUID string used as stable animation identity
- `parentId` : The index of the parent animation to place the child under in the tree

Returns the index of the new child animation
"""
function add_child_animation_interface(
    state_ptr::Ptr{Cvoid}, getViewText, init, loop, clean, name::String,
    stable_id::String, parentId::Integer)

    @ccall add_child_animation_interface(
        state_ptr::Ptr{Cvoid}, getViewText::Any, init::Any, loop::Any, clean::Any,
        name::Cstring, stable_id::Cstring, parentId::Int64)::Int64
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
