# Coding Standards

## Table Of Contents

1. [Authority and Scope](#authority-and-scope)
1. [Purpose](#purpose)
1. [Project-Wide Principles](#project-wide-principles)
1. [Function Size and Complexity Limits](#function-size-and-complexity-limits)
1. [Compile and Static Checks](#compile-and-static-checks)
1. [Language Boundary Standards (Odin <-> Julia)](#language-boundary-standards-odin---julia)
1. [Odin Standards](#odin-standards)
1. [Julia Standards](#julia-standards)
1. [Documentation and Markdown Standards](#documentation-and-markdown-standards)
1. [Comments and API Documentation](#comments-and-api-documentation)
1. [Error Handling and Logging](#error-handling-and-logging)
1. [Performance and Allocation Standards](#performance-and-allocation-standards)
1. [Security and Safety Standards](#security-and-safety-standards)
1. [Standard Evolution](#standard-evolution)

## Authority and Scope

This document is the source of truth for coding and documentation style expectations.

1. Use this document for how to write code.
1. Use [ArchitectureSummary.md](ArchitectureSummary.md) for why boundaries exist.
1. Use [AnimationStyle.md](AnimationStyle.md) for how animations should visually appear.

## Purpose

This document defines coding and documentation standards for this mixed Odin and Julia project.

These standards are normative.

- MUST indicates a hard requirement.
- SHOULD indicates a strong recommendation with limited exceptions.
- MAY indicates an optional practice.

If standards conflict, precedence is:

1. This document.
1. Official Julia style guide.
1. Odin naming and style conventions.

## Project-Wide Principles

- Code MUST optimize for readability, maintainability, and correctness first.
- Public behavior MUST be explicit at module boundaries.
- Internal implementation details SHOULD stay internal.
- Functions SHOULD be small enough to read in one pass.
- Avoid cleverness that obscures intent.
- Prefer deterministic behavior for math/animation logic.
- Prefer structs over long tuples for returned data.
- Prefer structs over very long parameter lists when the inputs form a coherent
  data shape.
- Always avoid mutable global variables. Global constants are okay.

## Line Length Policy

This policy applies to source and markdown files.

- 90 characters is the soft warning barrier.
- Exceeding 100 characters is discouraged and should be refactored/reflowed when practical.
- 120 characters is the hard upper barrier and is only acceptable for clearly inescapable cases,
  such as long string literals, long URLs, or other visibly unavoidable content.
- If a line exceeds 120 characters, keep it rare, intentional, and easy to identify in review.

## Function Size and Complexity Limits

These limits are mandatory and apply to Odin procedures and Julia functions.

1. Maximum 30 lines of executable code per function/procedure.
1. If a function/procedure exceeds 20 lines, it requires explicit review justification.
1. Each function/procedure MUST have one clear responsibility.
1. If parameter count exceeds 5, re-evaluate design and group inputs when appropriate.
1. Cyclomatic complexity SHOULD remain below 10.
1. Do not split into trivial wrappers only to satisfy line limits.
1. Prefer return structs over long tuples when a function returns related data.
1. Prefer grouped structs over very long parameter lists unless a language-specific
  calling pattern is materially clearer.

## Compile and Static Checks

Odin code MUST compile cleanly with strict checks enabled, and Julia code MUST pass basic
syntax validations.

These checks are performed with the `--vet` or `-v` parameter passed to `make.py`.

The following commands are run with vet for quick static/complexity analysis using lizard.
If lizard is not available, they will be skipped. Use `--fail-lizard` or `-f` to fail when
lizard gives negative results.

- Python make script:

```bash
lizard .
```

- Odin:

```bash
find ./src -type f -name '*.odin' -print0 | xargs -0 lizard -l cpp
```

- Julia:

```bash
find ./src/julia -type f -name '*.jl' -print0 | xargs -0 lizard
```

## Language Boundary Standards (Odin <-> Julia)

### julialib

- Types in `src/julialib` are vendor-specific mirrors of `julia.h` types and SHOULD remain aligned
  with upstream `julia.h` definitions.
- Do not rename, reshape, or reinterpret `src/julialib` vendor-mapped types unless an upstream
  `julia.h` change requires it and the boundary update is documented.

### Interface Design

- The Odin-Julia bridge MUST be treated as a strict API contract.
- New bridge capabilities MUST be added symmetrically:
  - Odin exported function.
  - Julia wrapper function.
  - Documentation for input/output and side effects.
- Bridge names SHOULD be explicit and action-oriented.
- Unsafe behavior MUST be obvious in naming and comments.

### Ownership and Mutation

- Ownership MUST be documented at the boundary:
  - Which side allocates.
  - Which side mutates.
  - Which side frees or manages lifecycle.
- Mutating operations MUST be clearly named and documented.
- Boundary APIs SHOULD avoid ambiguous hidden state transitions.

### Errors and Failure Modes

- Boundary calls MUST report errors in a predictable way.
- Exceptions and runtime errors MUST be translated into actionable logs/messages.
- Do not hide failures behind silent fallbacks unless explicitly documented.

## Odin Standards

These standards incorporate the Odin naming and style convention guidance.

### Odin Naming

- Import names MUST use snake_case and SHOULD be a single word when practical.
- Types MUST use Ada_Case.
- Enum values MUST use Ada_Case.
- Procedures MUST use snake_case.
- Local variables MUST use snake_case.
- Constants MUST use SCREAMING_SNAKE_CASE.

### Formatting and Layout

- Indentation MUST use 4 spaces per level.
- Tabs MUST NOT be used for indentation.
- Alignment MUST use spaces.
- Standalone closing-brace lines are acceptable.
- A line containing only `)` MUST NOT appear in parameter lists.
- If an Odin proc header would otherwise isolate `)`, `->`, or `{`, reflow the
  surrounding code, extract a helper, or use a single-line form so the delimiter is
  not alone.
- Opening braces MUST be at end-of-line.
- Variable declarations MUST follow idiomatic spacing:
  - val: int
  - val := 5
- Prefer val := Some_Type { ... } over val: Some_Type = { ... }.
- Global variables are always a code smell.
- Functions that are used outside of the current file should be placed at the top of the
  file and decorated with documentation comments including a summary as well as
  parameter and return descriptions and any important usage notes. These comments should
  explain more than simply restating function names/parameters.
- Functions that are just local utilities should have at least a summary doc comment.
  These comments should explain more than simply restating function names.
  Include any important usage notes.
  
### Type Inference and Initialization

- Prefer type inference where clarity is preserved.
- Explicit type annotations SHOULD be used when they improve readability or are required.
- Use struct initializers when possible instead of piecemeal assignment.
- Global constants of literal (e.g. `MY_CONSTANT :: 2.3`) SHOULD avoid strict typing.
  Typing at use-site (e.g. `my_value: f32 = MY_CONSTANT` or `f32(MY_CONSTANT)`)  is
  preferred where required. Structs frequently stand in exception, requiring type at
  constant definition (e.g. `BACKGROUND_COLOR :: rl.Color{36, 5, 16, 255}`).

### Control Flow and Resource Management

- Do not overuse defer.
- Use defer when multiple exits exist and cleanup must always run.
- Avoid defer for trivial single-exit code paths where linear control flow is clearer.

## Julia Standards

These standards incorporate the Julia official style guide.

### Formatting and Structure

- Indentation MUST use 4 spaces per level.
- Prefer functions over top-level script logic.
- Functions SHOULD accept explicit arguments instead of relying on globals.
- Non-const global variables are always a code smell. Prefer using the Odin-Julia Bridge
  metadata storage for anything that needs to live across call barriers.
- Functions used outside of the given file that have not been defined anywhere else as well
  SHOULD include thorough doc comments with a summary, parameter and return information,
  and possibly any important usage notes. These should be more than simply restating the
  names of functions/parameters.
- Although individual animation scripts do not require as much maintainence consideration
  as the rest of the code, they should still appear basically clean and readable, with
  appropriate indentation and easily read and determined names.

### Julia View Text Strings

This pertains to the "view texts" that are returned to the Odin code for animations. These
"view texts" are rendered on the bottom text area of the application window.

- Julia view text MUST be written as plain unicode text that assumes automatic
  wrapping by the renderer.
- Do not pre-wrap Julia view text manually unless a fixed-width or semantic
  layout is required.
- Pre-wrapping ordinary Julia view text is a code smell.

### Type and Dispatch Style

- Avoid overly specific argument typing unless required for correctness or method disambiguation.
- Prefer generic code that relies on required operations (duck typing) when appropriate.
- Handle input conversion diversity in the caller when a function truly requires a specific type.
- Avoid unnecessary static parameters.
- Be explicit when type constraints are semantically required.

### Julia Naming

- Modules and types MUST use CamelCase style consistent with Julia conventions.
- Functions MUST be lowercase; combine words without underscores when readable.
- Use underscores only when they significantly improve readability or indicate combined concepts.
- Mutating functions MUST end with !.
- Names SHOULD be concise but not cryptic; avoid abbreviations that reduce clarity.

### Function Design

- Follow Julia Base-style argument ordering when applicable:
  1. Function argument.
  1. IO stream.
  1. Input being mutated.
  1. Type.
  1. Input not being mutated.
  1. Key.
  1. Value.
  1. Remaining arguments.
  1. Varargs.
  1. Keyword arguments.
- Constructors MUST return instances of their declared type.
- Avoid confusion between instance-based and Type-based APIs.
- Julia may follow its established argument-order flow even when that means a longer
  parameter list, but grouped structs are still preferred when the inputs represent a
  coherent data bundle.
- Julia animation code MAY use a repeated state-machine style with longer functions
  when that is the established pattern for the animation and the code still follows
  the rest of the Julia standards.
- This exception is narrow and applies to animation state transitions, lifecycle
  coordination, and other repetitive animation control flow, not to general utility
  functions.

### Safety and API Boundaries

- Prefer exported methods over direct field access for module interfaces.
- Avoid exposing unsafe operations at interface level.
- Unsafe functions MUST be clearly named and documented.
- Avoid overloading behavior of base container types in surprising ways.
- Avoid type piracy except in tightly controlled, justified cases.

### Control Flow and Expression Style

- Do not overuse try-catch.
- Prefer preventing errors to catching avoidable ones.
- Do not parenthesize if/while conditions unnecessarily.
- Do not overuse argument splatting (...).
- Do not write trivial anonymous wrappers like x -> f(x) when f can be passed directly.
- Prefer isa and <: for type checks over broad == checks, except concrete-type equality cases.

### Generic Numeric Code

- Avoid float literals in generic numeric code when integer or rational literals preserve type behavior better.

## Documentation and Markdown Standards

These standards apply to all project markdown files, design notes, and technical docs.

### Document Structure

- Every markdown document MUST have exactly one H1.
- Heading levels MUST be sequential (do not skip levels).
- Sections SHOULD be organized from high-level to detailed.
- Large documents SHOULD include a short purpose section near the top.
- A linked Table of Contents at the very top MAY be included, SHOULD be included for large multi-part documents.

### Writing Style

- Use clear, direct language.
- Prefer short paragraphs and actionable guidance.
- Avoid vague wording like maybe, probably, or should be fine.
- Requirements SHOULD use MUST, SHOULD, MAY consistently.
- Keep tone technical and neutral.

### Formatting Rules

- Use fenced code blocks with a language tag whenever possible.
- Keep list formatting consistent within a section.
- Use ordered lists for step-by-step procedures.
- Use unordered lists for unordered constraints/checklists.
- Apply the repository line-length policy (90 warning, 100 discouraged, 120 exception-only).
- Use 1. numbering style for ordered lists in source markdown.
- For nested lists, indent child items by four spaces under the parent item.
- Surround lists with blank lines when adjacent to paragraphs or code fences.
- Do not use hard tab characters in markdown files.

### Code and Inline Literals

- Use fenced code blocks instead of indentation-based code blocks.
- Include language info strings when practical.
- Use inline code for commands, paths, identifiers, and literal statuses.

### Tables and Templates

- Use pipe tables with consistent spacing around columns.
- Keep headers concise and meaningful.
- Template placeholders SHOULD use bracket placeholders like [placeholder].
- Avoid pseudo-tag placeholders in angle brackets in markdown templates.

### Links and References

- Internal references SHOULD use repository-relative paths.
- External references SHOULD include stable canonical URLs.
- Do not include dead links; update or remove stale references.

### Examples and Snippets

- Examples SHOULD be minimal and realistic.
- Include at least one good example for non-obvious standards.
- If a bad pattern is shown, clearly label it as disallowed.

### Change Notes

- Standards changes MUST include rationale in commit or PR description.
- Behavior-changing standards SHOULD include migration guidance for existing code.

## Comments and API Documentation

### General

- Comments MUST explain why, not restate obvious what.
- Remove stale comments when code behavior changes.
- Keep comments close to the code they describe.

### Odin

- Use brief module and function comments for non-obvious logic.
- Avoid comment noise in straightforward control flow.

### Julia

- Public functions and types SHOULD include docstrings.
- Docstrings SHOULD describe purpose, key arguments, return behavior, and side effects.
- Mutating behavior MUST be explicitly called out in docstrings.

## Error Handling and Logging

- Fail fast on invalid state at module boundaries.
- Error messages MUST include enough context to debug quickly.
- Logs SHOULD be structured around operation, input context, and failure reason.
- Do not swallow exceptions/errors without comment and justification.

## Performance and Allocation Standards

- Optimize only after identifying bottlenecks.
- Keep hot paths allocation-aware.
- Avoid hidden allocation churn in per-frame logic.
- Document non-obvious performance tradeoffs.

## Security and Safety Standards

- Avoid exposing unsafe low-level operations as default APIs.
- Validate external/input data at boundaries.
- Keep native interop assumptions explicit and documented.

## Standard Evolution

- This document is a living standard.
- Updates MUST preserve clarity and enforceability.
- When introducing a new rule, include:
  - The rule.
  - Rationale.
  - Scope.
  - Expected enforcement method.
