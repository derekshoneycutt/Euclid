//   Procedure metric measurement for the Euclid Odin static analyzer.
//
//   Cyclomatic complexity counts each branching construct once: `if`, `for`,
//   ranged `for`, `switch`, each `case` clause, ternary `if`, `or_else`, and
//   each `&&` / `||` operator. Nested procedure literals are not descended
//   into; their control flow belongs to the enclosing allocation scope instead.
package main

import "core:odin/ast"

//   Measure line span, cyclomatic complexity, and parameter count of a procedure.
measure_proc :: proc(
    lit: ^ast.Proc_Lit,
    name, file: string,
    token_lines: ^map[int]bool) -> Proc_Metric {
    nloc := 0
    for line in lit.body.pos.line ..= lit.body.end.line {
        if token_lines[line] {
            nloc += 1
        }
    }

    ccn := 1
    visitor := ast.Visitor{visit = complexity_visit, data = &ccn}
    ast.walk(&visitor, lit.body)

    return Proc_Metric{
        file = file,
        line = lit.pos.line,
        name = name,
        nloc = nloc,
        ccn = ccn,
        params = count_params(lit.type),
    }
}

//   Count branching constructs beneath one node for cyclomatic complexity.
complexity_visit :: proc(visitor: ^ast.Visitor, node: ^ast.Node) -> ^ast.Visitor {
    if node == nil {
        return nil
    }

    score := cast(^int)visitor.data
    #partial switch kind in node.derived {
    case ^ast.Proc_Lit:
        return nil
    case ^ast.If_Stmt, ^ast.For_Stmt, ^ast.Range_Stmt, ^ast.Unroll_Range_Stmt:
        score^ += 1
    case ^ast.Switch_Stmt, ^ast.Case_Clause, ^ast.Ternary_If_Expr, ^ast.Or_Else_Expr:
        score^ += 1
    case ^ast.Binary_Expr:
        if kind.op.text == "&&" || kind.op.text == "||" {
            score^ += 1
        }
    }
    return visitor
}

//   Count the declared parameters of a procedure type.
count_params :: proc(proc_type: ^ast.Proc_Type) -> int {
    if proc_type == nil || proc_type.params == nil {
        return 0
    }
    count := 0
    for field in proc_type.params.list {
        count += max(len(field.names), 1)
    }
    return count
}
