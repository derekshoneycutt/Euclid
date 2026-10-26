package viewuserdata

import protocol "../../core/protocol"

// Claim the connection when free and honor the other borrower's turn when it is ready.
connection_admission_claim :: proc(
    admission: ^protocol.User_Data_Connection_Admission,
    client: protocol.User_Data_Connection_Client,
    other_ready, drain_work: bool) -> bool {
    if admission == nil || !connection_admission_client_valid(client) {
        return false
    }
    if admission^.phase != .Idle {
        return false
    }
    if admission^.draining && !drain_work {
        return false
    }
    if drain_work && !admission^.draining {
        return false
    }
    if other_ready && admission^.next_turn != .None &&
       admission^.next_turn != client {
        return false
    }
    admission^.owner = client
    admission^.phase = .Claimed
    return true
}

// Mark an accepted worker task as submitted while retaining connection ownership.
connection_admission_mark_submitted :: proc(
    admission: ^protocol.User_Data_Connection_Admission,
    client: protocol.User_Data_Connection_Client) -> bool {
    if !connection_admission_owned_by(
        admission, client, .Claimed) {
        return false
    }
    admission^.phase = .Submitted
    return true
}

// Release a claim immediately when the task pool rejected submission.
connection_admission_release_rejected :: proc(
    admission: ^protocol.User_Data_Connection_Admission,
    client: protocol.User_Data_Connection_Client) -> bool {
    if !connection_admission_owned_by(admission, client, .Claimed) {
        return false
    }
    connection_admission_clear_owner(admission)
    return true
}

// Release submitted connection access only after its task handle was joined.
connection_admission_release_joined :: proc(
    admission: ^protocol.User_Data_Connection_Admission,
    client: protocol.User_Data_Connection_Client) -> bool {
    if !connection_admission_owned_by(admission, client, .Submitted) {
        return false
    }
    admission^.next_turn = connection_admission_other_client(client)
    connection_admission_clear_owner(admission)
    return true
}

// Begin the shared shutdown drain and reject ordinary new connection claims.
connection_admission_begin_drain :: proc(
    admission: ^protocol.User_Data_Connection_Admission) {
    if admission != nil {
        admission^.draining = true
    }
}

// Report whether all borrowed connection access has been joined and released.
connection_admission_is_idle :: proc(
    admission: ^protocol.User_Data_Connection_Admission) -> bool {
    return admission != nil && admission^.owner == .None &&
        admission^.phase == .Idle
}

// Report completion of a begun drain once every service has joined its task.
connection_admission_drain_complete :: proc(
    admission: ^protocol.User_Data_Connection_Admission) -> bool {
    return admission != nil && admission^.draining &&
        connection_admission_is_idle(admission)
}

// Validate one borrower and the exact phase required for its transition.
connection_admission_owned_by :: proc(
    admission: ^protocol.User_Data_Connection_Admission,
    client: protocol.User_Data_Connection_Client,
    phase: protocol.User_Data_Connection_Admission_Phase) -> bool {
    return admission != nil && connection_admission_client_valid(client) &&
        admission^.owner == client && admission^.phase == phase
}

// Clear the current borrower without changing fair-turn or drain state.
connection_admission_clear_owner :: proc(
    admission: ^protocol.User_Data_Connection_Admission) {
    admission^.owner = .None
    admission^.phase = .Idle
}

// Validate the supported connection borrowers.
connection_admission_client_valid :: proc(
    client: protocol.User_Data_Connection_Client) -> bool {
    return client == .Settings_Save || client == .Terminal_History
}

// Select the peer whose turn follows a successful joined task.
connection_admission_other_client :: proc(
    client: protocol.User_Data_Connection_Client) ->
        protocol.User_Data_Connection_Client {
    if client == .Settings_Save {
        return .Terminal_History
    }
    return .Settings_Save
}
