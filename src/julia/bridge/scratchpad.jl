"""Notify the host that one queued Scratchpad request finished evaluation."""
function scratchpad_evaluation_completed(state_ptr::Ptr{Cvoid}, request_id::Integer)
    @ccall scratchpad_evaluation_completed(
        state_ptr::Ptr{Cvoid}, UInt64(request_id)::UInt64)::Cvoid
end
