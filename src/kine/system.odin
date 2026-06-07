package kine

kine_update_last_cache_vectors :: proc(
    pointSystem: ^KinePointSystem) {

    for i in 0..<MAX_KINEPOINTS {
        pointSystem^.PreviousVectors[i] = pointSystem^.Points[i].Position
    }
}

kine_freeze_system_indices :: proc(
    pointSystem: ^KinePointSystem) {

    pointSystem^.AnimPointsStart = pointSystem^.NextPointIndex
    pointSystem^.AnimConstraintsStart = pointSystem^.NextConstraintIndex
}

kine_clear_animation_data :: proc(
    pointSystem: ^KinePointSystem) {

    for i in pointSystem^.AnimPointsStart..<MAX_KINEPOINTS {
        pointSystem^.Points[i] = {}
        pointSystem^.Points[i].DoDraw = false
    }
    for i in pointSystem^.AnimConstraintsStart..<MAX_KINECONSTRAINTS {
        pointSystem^.Constraints[i] = {}
        pointSystem^.Constraints[i].DoApply = false
    }
}