//   Allocation call-site tracing for the Euclid Odin static analyzer.
//
//   Built-in allocator calls (`new`, `make`, `append`, and family) are matched
//   directly, along with a curated set of allocating core-library helpers such
//   as `strings.clone` and `fmt.aprintf`. Allocations inside nested procedure
//   literals are attributed to the enclosing named procedure scope.
package main

import "core:fmt"
import "core:odin/ast"
import "core:slice"
import "core:strings"

//   Built-in Odin calls that allocate on an allocator.
BUILTIN_ALLOCATORS :: []string{
    "new", "new_clone",
    "make", "make_slice",
    "make_dynamic_array", "make_dynamic_array_len", "make_dynamic_array_len_cap",
    "make_map", "make_map_cap",
    "append", "append_elem", "append_elems", "append_nothing",
    "append_soa", "append_string",
    "reserve", "resize",
}

//   Allocating core-library helpers, keyed as `package.name`.
ALLOCATING_HELPERS :: []string{
    "strings.clone", "strings.clone_to_cstring", "strings.to_cstring",
    "strings.join", "strings.concatenate",
    "strings.replace", "strings.replace_all",
    "fmt.aprintf", "fmt.aprintfln", "fmt.aprintln",
    "slices.clone", "slices.concatenate",
    "os.read_entire_file",
}

//   Walker state carried while tracing allocations in one procedure body.
Alloc_Visit_State :: struct {
    scope:  string,
    file:   string,
    src:    string,
    result: ^Analysis_Result,
}

//   Walk one procedure body and record every allocation expression it contains.
trace_allocations :: proc(
    lit: ^ast.Proc_Lit,
    scope, file, src: string,
    result: ^Analysis_Result) {
    state := Alloc_Visit_State{
        scope = scope, file = file, src = src, result = result,
    }
    visitor := ast.Visitor{visit = alloc_visit, data = &state}
    ast.walk(&visitor, lit.body)
}

//   Record one allocation record for each allocating call expression visited.
alloc_visit :: proc(visitor: ^ast.Visitor, node: ^ast.Node) -> ^ast.Visitor {
    if node == nil {
        return nil
    }

    call, is_call := node.derived.(^ast.Call_Expr)
    if !is_call {
        return visitor
    }

    kind, ok := allocation_kind(call.expr)
    if !ok {
        return visitor
    }

    state := cast(^Alloc_Visit_State)visitor.data
    append(&state.result.allocations, Alloc_Record{
        file = state.file,
        line = call.pos.line,
        scope = state.scope,
        kind = kind,
        expr = snippet(state.src, node),
    })
    return visitor
}

//   Return the allocation kind for a call target, or false when non-allocating.
allocation_kind :: proc(callee: ^ast.Expr) -> (string, bool) {
    if ident, is_ident := callee.derived.(^ast.Ident); is_ident {
        if slice.contains(BUILTIN_ALLOCATORS, ident.name) {
            return ident.name, true
        }
        return "", false
    }

    selector, is_selector := callee.derived.(^ast.Selector_Expr)
    if !is_selector {
        return "", false
    }
    pkg, is_pkg := selector.expr.derived.(^ast.Ident)
    if !is_pkg {
        return "", false
    }

    qualified := fmt.aprintf(
        "%s.%s", pkg.name, selector.field.name, allocator = context.temp_allocator)
    if slice.contains(ALLOCATING_HELPERS, qualified) {
        return strings.clone(qualified), true
    }
    return "", false
}

//   Extract a bounded single-line source snippet for one node.
snippet :: proc(src: string, node: ^ast.Node) -> string {
    start := clamp(node.pos.offset, 0, len(src))
    finish := clamp(node.end.offset, start, len(src))

    text, _ := strings.replace_all(
        src[start:finish], "\n", " ", context.temp_allocator)
    text, _ = strings.replace_all(text, "\t", " ", context.temp_allocator)
    if len(text) > SNIPPET_MAX {
        text = fmt.aprintf(
            "%s...", text[:SNIPPET_MAX - 3], allocator = context.temp_allocator)
    }
    return strings.clone(text)
}
