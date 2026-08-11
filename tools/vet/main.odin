//   Euclid Odin static analyzer.
//
//   This tool replaces the external `lizard` C++-mode analysis with a real Odin
//   parser pass. It walks every `.odin` file under a source root, measures each
//   named procedure against the coding standards (NLOC, cyclomatic complexity,
//   parameter count), and traces allocation call sites. Results are emitted on
//   stdout as tab-separated records so `make-vet.jl` can render the vet report.
package main

import "core:fmt"
import "core:os"
import "core:odin/ast"
import "core:odin/parser"
import "core:odin/tokenizer"
import "core:slice"
import "core:strings"

//   Marker prefix that grants a procedure a documented vet exception.
FORGIVENESS_PREFIX :: "forgives("

//   Marker name that forgives cyclomatic complexity above the standard.
COMPLEXITY_FORGIVENESS_MARKER :: "cyclomatic_complexity"

//   Marker name that forgives an allocation without an explicit allocator.
IMPLICIT_ALLOCATOR_MARKER :: "implicit_allocator"

//   Marker name that forgives an allocation on the default heap allocator.
HEAP_ALLOCATOR_MARKER :: "heap_allocator"

//   Maximum length of an allocation expression snippet in the report.
SNIPPET_MAX :: 120

//   One measured procedure in the analyzed source tree.
Proc_Metric :: struct {
    file:     string,
    line:     int,
    name:     string,
    nloc:     int,
    ccn:      int,
    params:   int,
    forgiven: bool,
}

//   One allocation call site discovered inside a procedure body.
Alloc_Record :: struct {
    file:        string,
    line:        int,
    scope:       string,
    kind:        string,
    alloc_class: string,
    status:      string,
    expr:        string,
}

//   Accumulated analysis output for the whole source root.
Analysis_Result :: struct {
    metrics:      [dynamic]Proc_Metric,
    allocations:  [dynamic]Alloc_Record,
    parse_errors: [dynamic]string,
    files_seen:   int,
}

//   Collect all `.odin` source files beneath `root` in deterministic order.
collect_odin_files :: proc(root: string) -> []string {
    files: [dynamic]string
    walker := os.walker_create(root)
    defer os.walker_destroy(&walker)

    for info in os.walker_walk(&walker) {
        if info.type != .Regular {
            continue
        }
        if !strings.has_suffix(info.fullpath, ".odin") {
            continue
        }
        append(&files, strings.clone(info.fullpath))
    }

    if path, err := os.walker_error(&walker); err != nil {
        fmt.eprintfln("walk error at %s: %v", path, err)
    }

    slice.sort(files[:])
    return files[:]
}

//   Return `path` relative to `root` when it sits beneath it.
relative_path :: proc(root, path: string) -> string {
    prefix := fmt.aprintf("%s/", root, allocator = context.temp_allocator)
    if strings.has_prefix(path, prefix) {
        return strings.clone(path[len(prefix):])
    }
    return strings.clone(path)
}

//   Record the set of source lines that hold at least one real token.
//   Comment-only and blank lines stay unmarked, approximating executable lines.
//   Comment lines carrying a `#vet forgives(NAME)` marker record the name.
scan_token_lines :: proc(
    src, path: string,
    lines: ^map[int]bool,
    marker_lines: ^map[int]string) {
    t: tokenizer.Tokenizer
    tokenizer.init(&t, src, path)
    for {
        token := tokenizer.scan(&t)
        if token.kind == .EOF {
            break
        }
        if token.kind == .Comment {
            if marker, ok := marker_name_from_comment(token.text); ok {
                marker_lines[token.pos.line] = marker
            }
            continue
        }
        last_line := token.pos.line + strings.count(token.text, "\n")
        for line in token.pos.line ..= last_line {
            lines[line] = true
        }
    }
}

//   Extract the NAME from a comment carrying `#vet forgives(NAME)`.
marker_name_from_comment :: proc(text: string) -> (string, bool) {
    index := strings.index(text, FORGIVENESS_PREFIX)
    if index < 0 {
        return "", false
    }
    rest := text[index + len(FORGIVENESS_PREFIX):]
    close := strings.index(rest, ")")
    if close <= 0 {
        return "", false
    }
    return strings.clone(rest[:close]), true
}

//   Analyze one source file: measure its procedures and trace its allocations.
analyze_file :: proc(root, path: string, result: ^Analysis_Result) {
    src_bytes, read_err := os.read_entire_file(path, context.allocator)
    if read_err != nil {
        append(&result.parse_errors, fmt.aprintf("%s: file unreadable", path))
        return
    }
    src := string(src_bytes)

    token_lines: map[int]bool
    marker_lines: map[int]string
    scan_token_lines(src, path, &token_lines, &marker_lines)

    p := parser.default_parser()
    file := ast.File{src = src}
    if !parser.parse_file(&p, &file) {
        append(&result.parse_errors, fmt.aprintf("%s: parse failed", path))
        return
    }

    rel := relative_path(root, path)
    for decl in file.decls {
        value_decl, is_value := decl.derived.(^ast.Value_Decl)
        if !is_value {
            continue
        }
        for value, index in value_decl.values {
            proc_lit, is_proc := value.derived.(^ast.Proc_Lit)
            if !is_proc || proc_lit.body == nil {
                continue
            }
            name := decl_name(value_decl, index)
            metric := measure_proc(proc_lit, name, rel, &token_lines)
            metric.forgiven = proc_has_marker(
                value_decl, proc_lit, &marker_lines, COMPLEXITY_FORGIVENESS_MARKER)
            append(&result.metrics, metric)
            trace_allocations(proc_lit, value_decl, name, rel, src,
                &marker_lines, result)
        }
    }
}

//   Return the declared name for one value in a declaration.
decl_name :: proc(decl: ^ast.Value_Decl, index: int) -> string {
    if index >= len(decl.names) {
        return "<anonymous>"
    }
    if ident, is_ident := decl.names[index].derived.(^ast.Ident); is_ident {
        return ident.name
    }
    return "<anonymous>"
}

//   Return true when the procedure carries a documented exception marker.
//   The marker is accepted in the declaration doc comments or anywhere on a
//   comment line inside the procedure span, matching the legacy lizard style.
proc_has_marker :: proc(
    decl: ^ast.Value_Decl,
    lit: ^ast.Proc_Lit,
    marker_lines: ^map[int]string,
    name: string) -> bool {
    if comment_group_has_marker(decl.docs, name) ||
        comment_group_has_marker(decl.comment, name) {
        return true
    }
    for line in lit.pos.line ..= lit.end.line {
        if marker, found := marker_lines[line]; found && marker == name {
            return true
        }
    }
    return false
}

//   Return true when a comment group contains the named forgiveness marker.
comment_group_has_marker :: proc(group: ^ast.Comment_Group, name: string) -> bool {
    if group == nil {
        return false
    }
    for token in group.list {
        marker, ok := marker_name_from_comment(token.text)
        if ok && marker == name {
            return true
        }
    }
    return false
}

//   Emit the full analysis result as tab-separated records on stdout.
emit_report :: proc(result: ^Analysis_Result) {
    for metric in result.metrics {
        fmt.printfln(
            "PROC\t%s\t%d\t%s\t%d\t%d\t%d\t%v",
            metric.file, metric.line, metric.name, metric.nloc, metric.ccn,
            metric.params, metric.forgiven)
    }
    for record in result.allocations {
        fmt.printfln(
            "ALLOC\t%s\t%d\t%s\t%s\t%s\t%s\t%s",
            record.file, record.line, record.scope, record.kind,
            record.alloc_class, record.status, record.expr)
    }
    for failure in result.parse_errors {
        fmt.printfln("PARSE_ERROR\t%s", failure)
    }
    fmt.printfln(
        "SUMMARY\tfiles=%d\tprocs=%d\tallocs=%d\tparse_errors=%d",
        result.files_seen, len(result.metrics), len(result.allocations),
        len(result.parse_errors))
}

//   Entrypoint: analyze every Odin file beneath the given source root.
main :: proc() {
    if len(os.args) != 2 {
        fmt.eprintln("Usage: euclid_vet_analyzer <src-root>")
        os.exit(2)
    }

    root := os.args[1]
    result: Analysis_Result
    for path in collect_odin_files(root) {
        result.files_seen += 1
        analyze_file(root, path, &result)
    }

    emit_report(&result)
    if len(result.parse_errors) > 0 {
        os.exit(1)
    }
}
