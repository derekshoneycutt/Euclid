println("[Julia] Script loaded successfully.")

function call_c_backend()
    val1 = 5.5
    val2 = 4.5
    
    result = add_with_c(val1, val2)
    
    println("[Julia] Result received from C: ", result)
end
call_c_backend()
