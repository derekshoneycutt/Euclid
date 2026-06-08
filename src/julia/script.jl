
include("./nullanimation.jl")


function get_view_text_root(state_ptr::Ptr{Cvoid})
    "Welcome to Euclid's Elements!"
end

function get_view_text_BookI(state_ptr::Ptr{Cvoid})
    "Euclid Elements - Book I"
end

function get_view_text_BookI_defs(state_ptr::Ptr{Cvoid})
    "Euclid Elements - Book I - Definitions"
end

function get_view_text_BookI_posts(state_ptr::Ptr{Cvoid})
    "Euclid Elements - Book I - Postulates"
end

function get_view_text_BookI_common(state_ptr::Ptr{Cvoid})
    "Euclid Elements - Book I - Common Notions"
end

function get_view_text_BookI_props(state_ptr::Ptr{Cvoid})
    "Euclid Elements - Book I - Propositions"
end



function init_euclid_scripts(state_ptr::Ptr{Cvoid})
    EuclidBridge.set_null_animations(
        state_ptr, NullAnimation.get_view_text, NullAnimation.initialize,
        NullAnimation.loop, NullAnimation.clean)


    rootId = EuclidBridge.add_root_animation_interface(
        state_ptr, get_view_text_root, NullAnimation.initialize, NullAnimation.loop, NullAnimation.clean,
        "Euclid's Elements")
    book1Id = EuclidBridge.add_child_animation_interface(
        state_ptr, get_view_text_BookI, NullAnimation.initialize, NullAnimation.loop, NullAnimation.clean,
        "Book I", rootId)
    book1DefsId = EuclidBridge.add_child_animation_interface(
        state_ptr, get_view_text_BookI_defs, NullAnimation.initialize, NullAnimation.loop, NullAnimation.clean,
        "Definitions", book1Id)
    book1PostsId = get_view_text_BookI_posts, EuclidBridge.add_child_animation_interface(
        state_ptr, get_view_text_BookI_posts, NullAnimation.initialize, NullAnimation.loop, NullAnimation.clean,
        "Postulates", book1Id)
    book1CommNotsId = EuclidBridge.add_child_animation_interface(
        state_ptr, get_view_text_BookI_common, NullAnimation.initialize, NullAnimation.loop, NullAnimation.clean,
        "Common Notions", book1Id)
    book1PropsId = EuclidBridge.add_child_animation_interface(
        state_ptr, get_view_text_BookI_props, NullAnimation.initialize, NullAnimation.loop, NullAnimation.clean,
        "Propositions", book1Id)
end

function global_euclid_loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    # Nothing to do here, but is required
end
