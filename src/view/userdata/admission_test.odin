#+test
package viewuserdata

import protocol "../../core/protocol"
import "core:testing"

// Verify only one client can hold a claim and rejected submission releases it.
@(test)
connection_admission_excludes_competing_clients :: proc(t: ^testing.T) {
    admission: protocol.User_Data_Connection_Admission
    testing.expect(t, connection_admission_claim(
        &admission, .Settings_Save, true, false))
    testing.expect_value(t, admission.phase,
        protocol.User_Data_Connection_Admission_Phase.Claimed)
    testing.expect(t, !connection_admission_claim(
        &admission, .Terminal_History, false, false))
    testing.expect(t, connection_admission_release_rejected(
        &admission, .Settings_Save))
    testing.expect(t, connection_admission_is_idle(&admission))
    testing.expect(t, connection_admission_claim(
        &admission, .Terminal_History, false, false))
}

// Verify turn alternation occurs after join and not after a rejected submission.
@(test)
connection_admission_alternates_ready_clients :: proc(t: ^testing.T) {
    admission: protocol.User_Data_Connection_Admission
    testing.expect(t, connection_admission_claim(
        &admission, .Settings_Save, true, false))
    testing.expect(t, connection_admission_mark_submitted(&admission, .Settings_Save))
    testing.expect(t, !connection_admission_release_rejected(&admission, .Settings_Save))
    testing.expect(t, connection_admission_release_joined(&admission, .Settings_Save))
    testing.expect(t, !connection_admission_claim(
        &admission, .Settings_Save, true, false))
    testing.expect(t, connection_admission_claim(
        &admission, .Terminal_History, true, false))
    testing.expect(t, connection_admission_mark_submitted(&admission, .Terminal_History))
    testing.expect(t, connection_admission_release_joined(&admission, .Terminal_History))
    testing.expect(t, connection_admission_claim(
        &admission, .Settings_Save, true, false))
}

// Verify ordinary claims stop at the shared drain boundary but shutdown work may proceed.
@(test)
connection_admission_drain_requires_joined_release :: proc(t: ^testing.T) {
    admission: protocol.User_Data_Connection_Admission
    connection_admission_begin_drain(&admission)
    testing.expect(t, !connection_admission_claim(
        &admission, .Settings_Save, false, false))
    testing.expect(t, connection_admission_drain_complete(&admission))
    testing.expect(t, connection_admission_claim(
        &admission, .Terminal_History, false, true))
    testing.expect(t, connection_admission_mark_submitted(
        &admission, .Terminal_History))
    testing.expect(t, !connection_admission_drain_complete(&admission))
    testing.expect(t, connection_admission_release_joined(
        &admission, .Terminal_History))
    testing.expect(t, connection_admission_drain_complete(&admission))
}
