
include("./nullanimation.jl")

function init_euclid_scripts(state_ptr::Ptr{Cvoid})
    EuclidBridge.set_null_animations(
        state_ptr, NullAnimation.initialize, NullAnimation.loop, NullAnimation.clean)


    rootId = EuclidBridge.add_root_animation_interface(
        state_ptr, NullAnimation.initialize, NullAnimation.loop, NullAnimation.clean,
        "Euclid's Elements", "idk")
    book1Id = EuclidBridge.add_child_animation_interface(
        state_ptr, NullAnimation.initialize, NullAnimation.loop, NullAnimation.clean,
        "Book I", "Book I of Euclid's Elements", rootId)
    book1DefsId = EuclidBridge.add_child_animation_interface(
        state_ptr, NullAnimation.initialize, NullAnimation.loop, NullAnimation.clean,
        "Definitions", "Book 1 Definitions", book1Id)
    book1PostsId = EuclidBridge.add_child_animation_interface(
        state_ptr, NullAnimation.initialize, NullAnimation.loop, NullAnimation.clean,
        "Postulates", "Book 1 Postulates", book1Id)
    book1CommNotsId = EuclidBridge.add_child_animation_interface(
        state_ptr, NullAnimation.initialize, NullAnimation.loop, NullAnimation.clean,
        "Common Notions", "Book 1 Common Notions", book1Id)
    book1PropsId = EuclidBridge.add_child_animation_interface(
        state_ptr, NullAnimation.initialize, NullAnimation.loop, NullAnimation.clean,
        "Propositions", "Book 1 Propositions", book1Id)
end

function global_euclid_loop(state_ptr::Ptr{Cvoid}, dt::Float32)
    # Nothing to do here, but is required
end
