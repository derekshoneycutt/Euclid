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

//   Built-in Odin calls that take an optional trailing allocator parameter.
PARAM_ALLOCATORS :: []string{
    "new", "new_clone",
    "make", "make_slice",
    "make_dynamic_array", "make_dynamic_array_len", "make_dynamic_array_len_cap",
    "make_map", "make_map_cap",
}

//   Built-in dynamic-array mutators. These allocate through the array's own
//   stored allocator, so no allocator can be passed at the call site.
ARRAY_ALLOCATORS :: []string{
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

//   Allocation source classes emitted in ALLOC records.
//   - array: dynamic-array mutator; allocator is fixed at array creation.
//   - temp: explicit context.temp_allocator.
//   - heap: explicit default heap allocator (context.allocator / heap).
//   - custom: explicit allocator whose source is not statically obvious.
//   - implicit: no allocator argument; silently uses the default heap.
ALLOC_CLASS_ARRAY :: "array"
ALLOC_CLASS_TEMP :: "temp"
ALLOC_CLASS_HEAP :: "heap"
ALLOC_CLASS_CUSTOM :: "custom"
ALLOC_CLASS_IMPLICIT :: "implicit"

//   Walker state carried while tracing allocations in one procedure body.
Alloc_Visit_State :: struct {
    scope:            string,
    file:             string,
    src:              string,
    forgive_implicit: bool,
    forgive_heap:     bool,
    result:           ^Analysis_Result,
}

//   Walk one procedure body and record every allocation expression it contains.
trace_allocations :: proc(
    lit: ^ast.Proc_Lit,
    decl: ^ast.Value_Decl,
    scope, file, src: string,
    marker_lines: ^map[int]string,
    result: ^Analysis_Result) {
    state := Alloc_Visit_State{
        scope = scope,
        file = file,
        src = src,
        forgive_implicit = proc_has_marker(
            decl, lit, marker_lines, IMPLICIT_ALLOCATOR_MARKER),
        forgive_heap = proc_has_marker(
            decl, lit, marker_lines, HEAP_ALLOCATOR_MARKER),
        result = result,
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

    kind, family, ok := allocation_kind(call.expr)
    if !ok {
        return visitor
    }

    state := cast(^Alloc_Visit_State)visitor.data
    alloc_class := classify_call_allocator(call, family)
    append(&state.result.allocations, Alloc_Record{
        file = state.file,
        line = call.pos.line,
        scope = state.scope,
        kind = kind,
        alloc_class = alloc_class,
        status = allocation_status(state, alloc_class),
        expr = snippet(state.src, node),
    })
    return visitor
}

//   Return the vet status for one allocation site given proc-level forgiveness.
allocation_status :: proc(state: ^Alloc_Visit_State, alloc_class: string) -> string {
    switch alloc_class {
    case ALLOC_CLASS_IMPLICIT:
        return "forgiven" if state.forgive_implicit else "block"
    case ALLOC_CLASS_HEAP:
        return "forgiven" if state.forgive_heap else "warn"
    }
    return "ok"
}

//   Return the allocation kind and family for a call target.
//   Family is "array" for dynamic-array mutators, "param" otherwise.
allocation_kind :: proc(callee: ^ast.Expr) -> (kind, family: string, ok: bool) {
    if ident, is_ident := callee.derived.(^ast.Ident); is_ident {
        if slice.contains(PARAM_ALLOCATORS, ident.name) {
            return ident.name, "param", true
        }
        if slice.contains(ARRAY_ALLOCATORS, ident.name) {
            return ident.name, "array", true
        }
        return "", "", false
    }

    selector, is_selector := callee.derived.(^ast.Selector_Expr)
    if !is_selector {
        return "", "", false
    }
    pkg, is_pkg := selector.expr.derived.(^ast.Ident)
    if !is_pkg {
        return "", "", false
    }

    qualified := fmt.aprintf(
        "%s.%s", pkg.name, selector.field.name, allocator = context.temp_allocator)
    if slice.contains(ALLOCATING_HELPERS, qualified) {
        return strings.clone(qualified), "param", true
    }
    return "", "", false
}

//   Classify the allocator source for one allocating call.
classify_call_allocator :: proc(call: ^ast.Call_Expr, family: string) -> string {
    if family == "array" {
        return ALLOC_CLASS_ARRAY
    }
    for arg in call.args {
        if class, found := allocator_expr_class(arg); found {
            return class
        }
    }
    return ALLOC_CLASS_IMPLICIT
}

//   State for scanning one expression subtree for allocator references.
Allocator_Scan :: struct {
    class: string,
    found: bool,
}

//   Return the allocator class referenced by an expression, when it mentions one.
allocator_expr_class :: proc(expr: ^ast.Expr) -> (string, bool) {
    scan := Allocator_Scan{}
    visitor := ast.Visitor{visit = allocator_scan_visit, data = &scan}
    ast.walk(&visitor, expr)
    return scan.class, scan.found
}

//   Visit one node while scanning for allocator references.
allocator_scan_visit :: proc(visitor: ^ast.Visitor, node: ^ast.Node) -> ^ast.Visitor {
    if node == nil {
        return nil
    }
    scan := cast(^Allocator_Scan)visitor.data
    if scan.found {
        return nil
    }

    #partial switch e in node.derived {
    case ^ast.Field_Value:
        // A named `allocator = value` argument: classify the value, and do not
        // descend into the field name itself (it would read as a bare ident).
        if ident, is_ident := e.field.derived.(^ast.Ident); is_ident &&
            ident.name == "allocator" {
            class, found := allocator_expr_class(e.value)
            scan.class = found ? class : ALLOC_CLASS_CUSTOM
            scan.found = true
            return nil
        }
    case ^ast.Selector_Expr:
        if class, ok := allocator_field_class(e); ok {
            scan.class = class
            scan.found = true
            return nil
        }
    case ^ast.Ident:
        if e.name == "temp_allocator" {
            scan.class = ALLOC_CLASS_TEMP
            scan.found = true
            return nil
        }
        if e.name == "allocator" || strings.has_suffix(e.name, "_allocator") {
            scan.class = ALLOC_CLASS_CUSTOM
            scan.found = true
            return nil
        }
    }
    return visitor
}

//   Classify one selector field as an allocator reference, when it names one.
//   `context.allocator` parses with an Implicit base ("context" is not an Ident).
allocator_field_class :: proc(e: ^ast.Selector_Expr) -> (string, bool) {
    switch e.field.name {
    case "temp_allocator":
        return ALLOC_CLASS_TEMP, true
    case "allocator":
        if pkg, is_pkg := e.expr.derived.(^ast.Ident); is_pkg && pkg.name == "heap" {
            return ALLOC_CLASS_HEAP, true
        }
        if imp, is_imp := e.expr.derived.(^ast.Implicit); is_imp &&
            imp.tok.text == "context" {
            return ALLOC_CLASS_HEAP, true
        }
        return ALLOC_CLASS_CUSTOM, true
    }
    if strings.has_suffix(e.field.name, "_allocator") {
        return ALLOC_CLASS_CUSTOM, true
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
