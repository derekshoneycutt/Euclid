
include("./1.fivegroupsaxioms/fivegroupsaxioms.jl")


"""Emit the Hilbert Foundations of Geometry root view text."""
function get_view_text_root_hilbert(state_ptr::Ptr{Cvoid})
    fallback = """David Hilbert - Foundations of Geometry ; Translated by E. J. Townsend
    
"All human knowledge begins with intuitions, thence passes to concepts and ends with ideas."
Kant, Critique of Pure Reason

Geometry, like arithmetic, requires for its logical development only a small number of simple, fundamental principles. These fundamental principles are called the axioms of geometry. The choice of the axioms and the investigation of their relations to one another is a problem which, since the time of Euclid, has been discussed in numerous excellent memoirs to be found in the mathematical literature. This problem is tantamount to the logical analysis of our intuition of space.
The following investigation is a new attempt to choose for geometry a simple and complete set of independent axioms and to deduce from these the most important geometrical theorems in such a manner as to bring out as clearly as possible the significance of the different groups of axioms and the scope of the conclusions to be derived from the individual axioms."""
    latex = raw"""\textbf{David Hilbert - Foundations of Geometry} ; Translated by E. J. Townsend
    
\textit{"All human knowledge begins with intuitions, thence passes to concepts and ends with ideas."}\\
\textit{Kant, Critique of Pure Reason}

Geometry, like arithmetic, requires for its logical development only a small number of simple, fundamental principles. These fundamental principles are called the axioms of geometry. The choice of the axioms and the investigation of their relations to one another is a problem which, since the time of Euclid, has been discussed in numerous excellent memoirs to be found in the mathematical literature. This problem is tantamount to the logical analysis of our intuition of space.
The following investigation is a new attempt to choose for geometry a simple and complete set of independent axioms and to deduce from these the most important geometrical theorems in such a manner as to bring out as clearly as possible the significance of the different groups of axioms and the scope of the conclusions to be derived from the individual axioms."""

    EuclidLatex.emit_latex_view_text!(state_ptr, latex, fallback)
end

"""Publish this category view when its animation node is selected."""
function initialize_view_root_hilbert(state_ptr::Ptr{Cvoid})
    NullAnimation.initialize(state_ptr)
    OdinJuliaBridge.publish_view_update(state_ptr, get_view_text_root_hilbert)
end

"""Register the Hilbert Foundations root animation interface and chapter content."""
function init_euclid_scripts_hilbert(state_ptr::Ptr{Cvoid})
    root_stable_id = OdinJuliaBridge.animation_stable_id_from_key(
        "root:Hilbert's Foundations of Geometry")
    OdinJuliaBridge.add_root_animation_interface(
        state_ptr, initialize_view_root_hilbert,
        NullAnimation.loop, NullAnimation.clean,
        "Hilbert's Foundations of Geometry",
        root_stable_id)

    HilbertChapterOne.init_euclid_scripts(state_ptr, root_stable_id)
end
