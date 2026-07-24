# Coding Standards

This document is the coding source of truth for this repository.

## Table Of Contents

1. [Purpose](#purpose)
1. [Fast Compliance Checklist](#fast-compliance-checklist)
1. [Global Rules](#global-rules)
1. [Verification Gate](#verification-gate)
1. [Odin-Julia Boundary Rules](#odin-julia-boundary-rules)
1. [Odin Rules (Required)](#odin-rules-required)
1. [Julia Rules (Required)](#julia-rules-required)
1. [Documentation Rules](#documentation-rules)
1. [Error Handling, Performance, Safety](#error-handling-performance-safety)
1. [Standard Updates](#standard-updates)

## Purpose

Keep standards short, enforceable, and hard to misread by humans or AI.

Normative language:

- MUST = required.
- SHOULD = strong default; justify exceptions.
- MAY = optional.

Precedence if rules conflict:

1. This file.
1. `ArchitectureSummary.md` for architectural boundaries.
1. Official Julia style guidance.
1. Odin style conventions.

## Fast Compliance Checklist

Before marking work complete, verify all items below:

- Build + vet + tests run with `julia make.jl -vt`.
- No hidden per-frame allocation growth in host-side hot paths.
- Odin and Julia bridge changes are symmetric and documented.
- Ownership is explicit: who allocates, mutates, and frees.
- Functions stay within size/complexity limits or include justification.
- No Odin/Julia header formatting violations around `)` placement.
- Comments/docs explain intent and side effects, not obvious syntax.

## Global Rules

### Readability and Determinism

- Prefer clear, deterministic behavior over cleverness.
- Keep module boundaries explicit and predictable.
- Avoid mutable global variables.
- Prefer structs over long tuples and over long parameter lists when inputs
  form one coherent data shape.

### Line Length

- 90 chars: warning threshold.
- 100 chars: discouraged.
- 120 chars: hard upper bound except unavoidable cases.

### Function Size and Complexity

- Maximum 30 executable lines per function/procedure.
- If a function exceeds 20 lines, include review justification.
- Each function/procedure must have one clear responsibility.
- If parameter count exceeds 5, reevaluate and group related inputs.
- Cyclomatic complexity should remain below 10; MUST remain below 15 unless exception granted, and that MUST be documented.
- Do not split into trivial wrappers only to satisfy line-count rules.

## Verification Gate

- Required command: `julia make.jl -vt`.
- `julia make.jl -v` alone is insufficient.
- `julia make.jl -t` alone is insufficient.

## Odin-Julia Boundary Rules

### Bridge Contract

- Treat the bridge as a strict API contract.
- New bridge capabilities must be added symmetrically:
  - Odin exported function.
  - Julia wrapper function.
  - Input/output and side-effect documentation.
- Bridge APIs should use explicit action-oriented names.

### Ownership and Failure Semantics

- Boundary APIs must document:
  - allocator/owner,
  - mutator,
  - lifecycle manager.
- Mutating operations must be clearly named.
- Boundary errors must be surfaced predictably.
- Do not hide failures behind silent fallbacks unless explicitly documented.

## Odin Rules (Required)

### Naming

- Imports: `snake_case`.
- Types and enum values: `Ada_Case`.
- Procedures and locals: `snake_case`.
- Constants: `SCREAMING_SNAKE_CASE`.

### Formatting

- 4-space indentation; no tabs.
- Opening braces stay on end-of-line.
- Keep wrapped calls compact and readable.
- A line containing only `)` in parameter lists is disallowed.
- In Odin proc headers, a line must not begin with `)`.
- The closing `)` must remain on the same line as the final parameter.
- If header wrapping would isolate `)`, `->`, or `{`, reflow the signature.

### Design and Initialization

- Prefer type inference when clear.
- Prefer struct initializers over piecemeal field assignment.
- Prefer `val := Some_Type { ... }` over `val: Some_Type = { ... }`.
- Global variables are a code smell; avoid them.

### Comments and Function Placement

- Public/cross-file functions should appear near the top of a file.
- Public/cross-file functions need useful doc comments:
  - purpose,
  - key params/returns,
  - side effects/usage notes.
- Local helper functions should include concise summary comments when
  non-obvious.

### Resource Management

- Use `defer` when multiple exits require guaranteed cleanup.
- Avoid `defer` in trivial single-exit paths when linear flow is clearer.

## Julia Rules (Required)

### Formatting and Structure

- 4-space indentation.
- Keep wrapped calls compact and readable.
- In function calls, avoid placing `)` on its own line.
- Prefer functions over top-level script logic.
- Avoid non-const globals; prefer explicit state paths.

### Naming and API Semantics

- Modules and types: `CamelCase`.
- Functions: lowercase (project runtime defaults to `snake_case`).
- Mutating functions must end with `!`.
- Avoid cryptic abbreviations.

### Type and Dispatch Style

- Avoid overly specific type constraints unless semantically required.
- Prefer generic behavior based on required operations when appropriate.
- Avoid unnecessary static parameters.
- Avoid type piracy except tightly controlled, justified cases.

### View Text Rule

- `get_view_text` output should be plain Unicode text with renderer wrapping.
- Do not manually pre-wrap ordinary view text unless fixed-width or semantic
  layout demands it.

### Function/Control Flow Guidance

- Use Julia Base-style argument ordering where practical.
- Constructors must return instances of declared type.
- Avoid trivial wrappers like `x -> f(x)` when `f` can be passed directly.
- Prefer preventing avoidable errors over broad `try/catch` usage.

### Animation-Script Exception

- Animation definition files may keep longer phase-oriented `loop` functions
  when that improves readability of animation state flow.
- This exception is narrow and does not waive general clarity requirements.

## Documentation Rules

- Every markdown file must have exactly one H1.
- Heading levels must be sequential.
- Use direct, technical, non-hedging language.
- Use fenced code blocks with language tags when practical.
- Keep list formatting consistent.
- Use ordered lists for procedures, unordered lists for constraints.
- Use inline code for paths, commands, and identifiers.
- Use repository-relative internal links.

## Error Handling, Performance, Safety

### Error Handling

- Fail fast at module boundaries on invalid state.
- Error messages must include debugging context.
- Do not swallow exceptions/errors without explicit justification.

### Performance and Allocation

- Optimize with evidence, not guesswork.
- Keep host-side per-frame paths allocation-aware.
- Avoid hidden allocation churn in hot loops.
- Follow the allocation policy in `ArchitectureSummary.md`.

### Safety

- Do not expose unsafe low-level operations as default APIs.
- Validate external/input data at boundaries.
- Keep interop assumptions explicit and documented.

## Standard Updates

- Changes to this document must preserve clarity and enforceability.
- A standards change should include:
  - the rule,
  - rationale,
  - scope,
  - enforcement guidance.
