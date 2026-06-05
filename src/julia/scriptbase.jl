
function add_with_c(val1, val2)
    @ccall c_add_numbers(val1::Cdouble, val2::Cdouble)::Cdouble
end
