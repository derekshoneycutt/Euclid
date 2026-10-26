# Coding Standards

This document and `tools/analysis_settings.jl` are the coding sources of truth
for this repository. This guide defines the reviewable human standard;
`tools/analysis_settings.jl` is the living configuration for its automated
enforcement.

[Memory Architecture](MemoryArchitecture.md) owns the normative memory allocation,
ownership, reuse, and retirement standard. This document delegates those rules
there rather than maintaining a separate memory policy.

## Table Of Contents

1. [Purpose](#purpose)
1. [How To Read This Standard](#how-to-read-this-standard)
1. [Upstream Style Relationship](#upstream-style-relationship)
1. [Fast Compliance Checklist](#fast-compliance-checklist)
1. [Global Rules](#global-rules)
1. [Package Dependency Direction](#package-dependency-direction)
1. [Allocation And Lifetime](#allocation-and-lifetime)
1. [Verification Gate](#verification-gate)
1. [Odin-Julia Boundary Rules](#odin-julia-boundary-rules)
1. [Odin Rules (Required)](#odin-rules-required)
1. [Julia Rules (Required)](#julia-rules-required)
1. [Documentation Rules](#documentation-rules)
1. [Error Handling, Performance, Safety](#error-handling-performance-safety)
1. [Standard Updates](#standard-updates)

## Purpose

This document converts language-community guidance and project experience into
reviewable rules for Euclid. It is intentionally concise, but not at the
expense of rationale, scope, or enforcement.

## How To Read This Standard

Normative language and enforcement labels:

| Term | Meaning |
| --- | --- |
| **MUST** | Required. A violation blocks acceptance unless this document names an exception. |
| **SHOULD** | Strong default. Deviations require a concrete readability or correctness reason. |
| **MAY** | Optional and context-dependent. |
| **Automated** | Checked by the CMake `check` target, compiler flags, tests, or vet analysis. |
| **Review** | Checked during code review because reliable automation is not yet available. |

### Living Automated Policy

`tools/analysis_settings.jl` is the current source of truth for analyzer rule
responses, thresholds, scan configuration, and reviewed exceptions. It layers
Euclid-specific policy over the analysis engine's baseline settings in
`tools/analysis/settings.jl`.

When a standard is automated, this document must agree with the active project
settings. Update both surfaces when changing policy; do not document an
enforcement level, threshold, or exception that the active settings do not
implement.

When guidance conflicts, use this precedence:

1. Safety, correctness, ownership, and ABI requirements.
1. Active automated policy in `tools/analysis_settings.jl`.
1. Repository-specific rules in this document and its delegated
   [memory standard](MemoryArchitecture.md#allocation-and-lifetime-standard).
1. Established local module conventions.
1. Upstream Odin or Julia style guidance.

`ArchitectureSummary.md` is an architectural entry point, not a second
normative coding standard. When implementation rules appear to conflict,
follow this document and the active automated policy.

An exception should state what rule is being relaxed and why the normal form is
worse in that case. It should also explain how correctness or readability
remains protected. Do not add comments merely to excuse weak code; improve the
code first.

## Upstream Style Relationship

This standard incorporates and specializes:

- [Odin examples naming and style conventions](https://github.com/odin-lang/examples/wiki/Naming-and-style-convention)
- [Julia style guide](https://docs.julialang.org/en/v1/manual/style-guide/)

| Area | Upstream default | Euclid policy |
| --- | --- | --- |
| Odin indentation | Tabs for indentation; spaces for alignment. | **Four spaces; tabs forbidden.** |
| Odin vet flags | Includes `-vet-tabs`. | Uses strict flags but omits `-vet-tabs`. |
| Odin naming | Ada types; snake values; screaming constants. | Adopted; bridge names remain symmetric. |
| Odin initialization | Prefer inference and complete initializers. | Preserve inference; put direct compound-literal types on declarations. |
| Julia indentation | Four spaces. | Adopted. |
| Julia naming | Lowercase; `!` for argument mutation. | Adopted; use `snake_case` when needed. |
| Julia typing | Generic unless dispatch requires constraints. | Adopted; ABI wrappers use exact types. |

Repository policy wins where it deliberately differs. In particular, never
introduce tabs into Odin files to match the upstream examples repository. The
Odin build uses `-vet -strict-style`, `-disallow-do`, and
`-warnings-as-errors`. Explicit types remain appropriate where ABI layout or
numeric width is part of the contract.

### Odin Control Bodies

Odin `if`/`else` branches and all `for` forms MUST use braced bodies whose
opening and closing braces occupy different source lines. This includes empty
bodies; a wrapped condition does not excuse same-line body braces. Ordinary
`else if` chaining is allowed, with each actual branch body checked separately.

`do` bodies are forbidden regardless of line breaks. The analyzer rules
`ODIN-SINGLE-LINE-CONTROL-BODY` and `ODIN-DO-CONTROL-BODY` are both configured
as `Fail` in Euclid, independently of the compiler's existing `-disallow-do`
safeguard. Both apply to test and production source. They do not independently
restrict `when`, `switch`, `defer`, standalone blocks, or procedure literals;
covered conditionals and loops nested inside those constructs are still checked.

Existing-source cleanup is deferred when introducing these rules. Existing
violations remain blocking findings, not grandfathered exceptions.

Switch case body code MUST start after the physical line of the terminating
colon, including default cases and ordinary, type, and `#partial` switches.
Wrapped labels are checked against the colon's line, not the `case` keyword's
line. An explicit opening `{` MAY share the colon's line if actual code starts
on a later line; empty cases and empty blocks are allowed. Nested explicit
blocks do not hide inline code: `case X: { return }` is forbidden. Comments
are allowed, and this rule adds no indentation requirement.

`ODIN-CASE-BODY-PLACEMENT` is configured as `Fail` in Euclid and applies to test
and production source. Each offending case points to its first inline actual
statement. Existing-source cleanup is deferred; findings remain blocking.

### Odin Compound-Literal Declarations

A single mutable binding initialized directly by a typed compound literal MUST
put the type on the declaration: use `value: Type = {...}`, not
`value := Type{...}`. This includes empty, positional, and named literals, in
production and test source and at package scope. Transparent initializer
parentheses do not exempt the declaration.

The rule covers structs, aliases and distinct types, imported and anonymous types,
polymorphic instantiations, explicit-length arrays, slices, matrices, bit sets,
maps, and dynamic arrays where those literals are legal. Dynamic literals still
require the compiler's feature opt-in and do not bypass allocation policy.

Preserve ordinary inference for calls, conversions, references, scalar values,
and computed expressions. Constants and multiple-binding declarations are outside
this rule, as are assignments, arguments, returns, field defaults, and literals
nested within other expressions. Address-taking, indexing, and selecting a field
from a literal are expressions, not direct literal initializers.

Inferred-length array types such as `[?]int` MUST remain attached to their literals.
Do not replace inferred lengths with manually counted sizes to satisfy style.
Nested inferred array types are exempt from this style finding without making
invalid types legal. Inferred arrays inside a self-contained type computation
or a struct's field value do not exempt the outer declaration.

```odin
point: Vector2 = {1, 2}
buffer: [4]u8 = {0, 1, 2, 3}
options: Options = {}
values := [?]int{1, 2, 3}
result := calculate()
```

`ODIN-COMPOUND-LITERAL-DECLARATION` is configured as `Fail` in Euclid; the engine
default is enabled `Report`. It is independent of named-field layout and
function-line aggregation. Existing-source cleanup is deferred: existing
violations remain blocking findings, not grandfathered exceptions.

### Odin Named Initializers

Nonempty named-field initializers MUST use multiline layout: initializer code
starts after the opening `{` line, each field starts on its own line one four-space
block deeper, every field ends with a comma, and the closing `}` returns to the
opening line's indentation. Values may wrap with deeper continuation indentation.
Comments, blank lines, and surrounding expressions are allowed. Empty `{}` and
positional literals are exempt.

`ODIN-NAMED-INITIALIZER-LAYOUT` is configured as `Fail`, including in tests.
Euclid also selects `odin_line_count_mode=:aggregate_initializers` for function-length
enforcement. Correctly formatted named initializers of simple values count as one line;
substantive surrounding code on both sides makes the shell two lines. Calls and
operations retain their code-bearing RHS lines, starting after `=`; a wrapped
field label alone adds none. Nested initializers reduce recursively without hiding
computation. Positional struct, array, and slice initializers use the same reduction,
without requiring named-field layout or one element per line; inline matrix rows
remain declarative data. Computed positional elements retain their code-bearing
expression lines. Ordinary source statistics and complexity density do not change.

The analyzer engine defaults remain `Report` layout enforcement and `:physical`
code-bearing-line counting. Euclid deliberately enables both stricter layout and
reduced counting together. Existing-source cleanup is deferred; findings remain
blocking rather than grandfathered.

## Fast Compliance Checklist

Before marking work complete, verify all items below:

- Build + vet + tests run with the CMake `check` target.
- No hidden per-frame allocation growth in host-side hot paths.
- Odin and Julia bridge changes are symmetric and documented.
- Ownership is explicit: who allocates, mutates, and frees.
- Worker scratch is reclaimed at its operation boundary; task results do not
  escape through scratch, and owner helping preserves caller allocations
  ([scratch contract](MemoryArchitecture.md#temporary-storage-and-joined-work)).
- Functions stay within size/complexity limits or include justification.
- Return shapes use one value or, when genuinely clearer, a two-item tuple.
- No Odin or Julia closing parenthesis begins its own continuation line.
- Every named Odin procedure and Julia function has a useful doc comment or docstring.
- Doc comments explain contracts, intent, and side effects rather than narrating syntax.
- Public API names, mutation signals, argument order, and type constraints
  match language conventions.
- Canonical validation occurs at boundaries; internal code does not repeatedly
  normalize bad input.

## Package Dependency Direction

Root package `src/core` is application composition, not a universal model package.
It MUST retain only `Euclid_General_State`, `Euclid_Run_Settings`, and records whose
purpose intrinsically requires complete application state. A type does not belong in
root core merely because `Euclid_General_State` reaches it.

Subsystem and model packages are substrate and MUST NOT import root core. Executable
entry points and behavior in `src/view` and `src/bridge` are coordinators and MAY import
root core. More-specific model packages beneath those coordinators remain substrate and
MUST remain composition-independent. Production consumers MUST import the package that
owns a model directly; root-core forwarding aliases are forbidden.

`tools/analysis_settings.jl` enforces these layers. Substrate-to-composition edges and
cycles among architecture layers are blocking findings.

Raylib and rlgl imports are forbidden. The repository-owned `EUCLID-SDL-BOUNDARY`
analysis extension checks parser-backed Odin dependency records and rejects either
removed backend target.

SDL imports are admitted only at exact native owners. The extension currently admits
only the exact display-owned native color, icon, platform, platform-service, and timing
files, the clipboard adapter, and the display input coordinator. Tests and the
checked-in capability probe are fixtures, not production owners. Add or move an SDL
import only with a corresponding ownership and architecture update.

## Allocation And Lifetime

Follow the normative
[Allocation And Lifetime Standard](MemoryArchitecture.md#allocation-and-lifetime-standard)
in Memory Architecture. That guide owns storage selection, explicit allocators,
reuse and growth, borrower retirement, Julia rooting, and allocation-policy
exceptions, with the application-wide context behind those rules.

## Verification Gate

Before work is complete, run the canonical CMake target:

```sh
cmake --build --preset default --target check
```

The target bootstraps configured Julia dependencies and invokes the full Julia driver
gate. CMake's reserved `test` target and `ctest` run selectable suites; they do not
replace the canonical complete gate.

The `vet` target alone is insufficient because it omits tests. Running tests alone is
insufficient because it omits the build and repository analysis. Do not report the
combined gate as passing when a phase was skipped.

Persistence acceptance MUST use an isolated process-level `--user-db` path, never
the developer's database. Settings scenarios use exact typed `set_setting` and
`assert_setting` key/value payloads; edits route through existing control policy
and cannot mutate startup-only controls. A saved-state predicate is not by itself
proof of a new commit: require a joined save event and independently inspect the
committed rows. Arbitrary SQL remains outside the scenario action vocabulary.
Shutdown MUST drain settings before any subsystem can stop the shared task pool.
Worker-only execution evidence does not establish a quantitative latency budget;
report deferred timing claims explicitly.

| Surface | Enforcement | Expected result |
| --- | --- | --- |
| Odin build/style | Analysis engine's strict analytical Odin build | No warnings or style failures. |
| Odin behavior | `odin test src -all-packages` through the verification gate | All tests pass. |
| Julia behavior | `src/julia/test/runtests.jl` through the verification gate | All tests pass. |
| Julia static analysis | JET entry-point analysis via OdinJuliaAnalysis | No actionable reports. |
| Julia/Odin complexity | Function metric rules with reviewed exceptions | No blocking rows; reviewed warnings only. |
| Analysis report | `.build/reports/analysis.md` | No failures and no unexplained new warning. |
| Documentation structure | Markdown rules and review | Valid headings, links, fences, and line length. |

Run the narrowest relevant test while developing, then run the complete gate
before delivery. A new warning is work to understand, even when the current
report classifies it as nonblocking.

## Global Rules

### Readability and Determinism

- Prefer clear, deterministic behavior over cleverness.
- Keep module boundaries explicit and predictable.
- Avoid mutable global variables.
- Prefer structs over long tuples and over long parameter lists when inputs
  form one coherent data shape.
- Prefer established language and repository idioms over custom mini-frameworks.
- Keep the happy path visually prominent; validate or reject exceptional states
  at boundaries.
- Name values for their domain meaning, not their temporary implementation role.

### Command-Line Short Flags

For paired command-line options, lowercase short flags MUST enable the option
and the corresponding uppercase flag MUST disable it, such as `-a`/`-A`.
Combined short groups are allowed and are applied left to right, so the last
occurrence wins. Unpaired actions such as help or clean remain lowercase.

### Line Length

- 90 chars: warning threshold.
- 100 chars: discouraged.
- 120 chars: hard upper bound except unavoidable cases.

### Closing Parenthesis Placement (Absolute)

In both Odin and Julia, a closing `)` MUST remain on the same physical line as
the final parameter or argument. This applies to procedure/function
declarations, definitions, calls, macro invocations, and any other wrapped
parenthesized construct.

The following continuation-line forms are wholesale forbidden:

- a line containing only `)`;
- a line beginning with `) {`;
- a line beginning with `) -> Return_Type`;
- a line beginning with `) -> Return_Type {`;
- a line beginning with `)::ReturnType` or `) = begin`;
- any equivalent form that moves the closing delimiter away from the final item.

This rule has no style exception for a long return type or header. Reflow
earlier parameters, use a meaningful named return type, or otherwise
restructure the declaration. Do not solve line length by moving `)` or the
tokens that complete its header onto a new line.

Code review MUST reject a violation even when the compiler or formatter accepts it.

### Function Size and Complexity

- A function/procedure SHOULD remain at or below 35 executable lines.
- More than 45 executable lines requires review justification; more than 65
  requires a documented exception and a clear reason decomposition would make
  the code worse.
- Each function/procedure must have one clear responsibility.
- If parameter count exceeds 5, reevaluate and group related inputs.
- Cyclomatic complexity SHOULD remain at or below 10 and MUST remain below 15
  unless a documented exception is granted.
- Do not split into trivial wrappers only to satisfy line-count rules.

The analysis report records executable lines, parameter count, and cyclomatic
complexity for both languages.
Julia complexity above 10 is blocking outside configured content-script exceptions.
Odin complexity at or above 15 is blocking, and 11-14 produces a warning. Executable
line and parameter count remain review signals in both languages. Exceptions are
reviewed entries in `tools/analysis_settings.jl` with drift detection rather than
inline markers.

#### Odin Flat-Switch Exception

Euclid enables the analyzer's opt-in flat-switch policy. An eligible Odin procedure
is exempt from executable-line and cyclomatic-complexity threshold findings when:

- Its body contains exactly one top-level switch, ordinary or type-based, including
  `#partial` forms.
- Each case, including the default, contains zero or one actual simple statement:
  a return, assignment, declaration, or call. Explicit blocks are transparent and
  MUST NOT conceal additional statements. Empty statements and blocks do not count.
- At most six executable source lines occur outside the switch. Procedure headers,
  comments, blank lines, and structural-only lines do not count. Multiline setup
  counts by source lines, not initializer-reduced enforcement lines.
- No nested control flow, additional switch, fallthrough, conditional expression,
  or short-circuit boolean operation occurs in the switch header, labels, cases,
  or surrounding code. Called procedures and nested procedure-literal bodies are
  separate scopes, not inspected as part of this procedure's eligibility.

Case statements are counted structurally: a multiline aggregate return is one
statement, while two statements on one line are still two statements. Existing
formatting rules remain independent, including case-body placement.

The exemption is automatic and is lost as soon as the procedure no longer meets
the shape or outside-line limit. Raw NLOC, cyclomatic complexity, and repository
statistics remain unchanged; reports identify active exemptions. Parameter,
allocation, documentation, naming, and all other rules still apply. This exception
does not justify unrelated responsibility or dispatch refactoring merely to qualify.

The policy is configured through `FunctionMetricSettings` using
`odin_flat_switch_enabled=true` and `odin_flat_switch_max_outside_lines=6`.
It is independent of Odin's aggregate-initializer line-count mode. A named metric
waiver made redundant by the policy MUST be removed rather than bypassing drift
detection.

The analyzer also classifies every allocation call site by allocator source. An
allocation it cannot classify is a **blocking** analysis failure; an implicit or
explicit default-heap allocator (`context.allocator`, `heap.allocator()`) produces
a warning. Dynamic-array mutators (`append`, `reserve`, `resize`) are exempt because
the array carries its allocator from creation. Documented exceptions are
`ReviewedAllocationPolicy` entries in `tools/analysis_settings.jl` with a reason,
such as a process-lifetime singleton created once at startup.

Use this decision path when a function grows:

```mermaid
flowchart TD
    A[Function exceeds a review threshold]
    B{More than one responsibility?}
    C[Extract a meaningful operation or data type]
    D{Control flow can be simplified?}
    E[Use guard clauses, tables, or clearer state transitions]
    F{Domain sequence is clearer intact?}
    G[Document the narrow exception]
    H[Keep the function and verify complexity]

    A --> B
    B -->|Yes| C
    B -->|No| D
    D -->|Yes| E
    D -->|No| F
    F -->|Yes| G --> H
    F -->|No| C
```

### Return Shape

Odin procedures and Julia functions SHOULD return one semantic value. A tuple
return SHOULD contain no more than two items. When three or more values belong
together, define a named struct instead.

| Shape | Policy | Typical use |
| --- | --- | --- |
| One value | Preferred | Entity, collection, status, or named result struct. |
| Two-item tuple | Allowed when the relationship is immediate | `(value, ok)` or `(result, status)`. |
| Three or more tuple items | Strongly discouraged | Replace with a named result struct. |
| Nested tuple used to avoid the limit | Forbidden | Model the result explicitly. |

A collection, optional/union result, or named struct counts as one value. The
concern is positional return arity, not the number of elements inside a
returned collection or variants in one return type.

Prefer a named result struct when any of these conditions apply:

- callers need more than two returned values;
- fields have units, ownership, lifecycle, or validity relationships;
- several call sites destructure the same positional shape;
- the result is likely to gain fields;
- field names would make review safer than positional order;
- success/failure carries payload, diagnostics, or partial-progress metadata.

An exception for more than two positional values requires explicit review
justification. Acceptable reasons are narrow, such as compatibility with an
external ABI or a language-mandated callback shape. Convenience, avoiding a
small struct, or preserving an accidental local pattern is not sufficient.

Do not introduce a reusable abstraction solely to avoid a clear local two-item
tuple. Conversely, do not keep a wide tuple merely because destructuring makes
the call site superficially short.

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
- Every Julia C API call MUST execute on the persistent Julia owner thread.
  Externally reachable worker tasks MUST assert owner identity before calling
  Julia or a helper that calls Julia.
- Cross-thread requests and events MUST use bounded service-owned storage or
  self-contained copied payloads. Their owner, recycler, generation identity,
  and saturation behavior MUST be explicit.
- Worker completion MUST report success or failure with request identity.
  Required lifecycle messages MUST retry with a bounded terminal policy rather
  than being silently dropped.

## Odin Rules (Required)

### Naming

| Construct | Form | Example |
| --- | --- | --- |
| Import name | `snake_case`; prefer one word | `strings`, `sdl`, `font_core` |
| Type | `Ada_Case` | `Scene_Command_Batch` |
| Enum value | `Ada_Case` | `Request_State.Ready` |
| Procedure | `snake_case` | `publish_scene_batch` |
| Parameter/local | `snake_case` | `request_index` |
| Constant | `SCREAMING_SNAKE_CASE` | `MAX_SCENE_COMMANDS` |

Names SHOULD communicate domain role and units where ambiguity is possible:

- Prefer `elapsed_seconds`, `point_index`, and `command_count` over `value`,
  `id`, and `size`.
- Avoid repeating package or type context that is already obvious at the call site.
- Boolean names SHOULD read as predicates: `is_ready`, `has_capacity`, `should_publish`.
- Use established bridge ABI names exactly. Do not improve one side independently.
- Avoid abbreviations unless they are conventional in this codebase or domain,
  such as `abi`, `ui`, `io`, `dt`, or `ptr` at an interop boundary.

### Formatting

| Rule | Required form |
| --- | --- |
| Indentation | Four spaces per level; tabs are forbidden, including alignment. |
| Braces | Opening brace remains on the declaration or control-flow line. |
| Binding spacing | `value: int`, `value := 5`, `NAME :: 5`; use policy-defined spaces around separators and keep composite punctuation adjacent. |
| Wrapping | Indent continuation lines by four spaces; align further only when it aids scanning. |
| Delimiter close | Keep `)` with the final parameter or argument in declarations and calls. |
| Return/brace | Do not isolate `->` or `{` from the header it completes. |
| Blank lines | Separate conceptual blocks, not every statement. |

Odin separator spacing is enforced by four independently configurable rules.
Declaration colons use zero spaces before and one after; equals signs,
inferred declarations (`:=`), and constant declarations (`::`) use one space
on both sides. The `:=` and `::` punctuation remains adjacent. A typed constant
uses the declaration-colon policy for its type separator and the constant
policy for its value separator.

Each side may be configured as an exact nonnegative number of ASCII spaces or
unrestricted horizontal whitespace. A side is exempt when its adjacent token
is separated by a line wrap or comment. The baseline analyzer reports these
findings; Euclid configures all four rules as `Fail`. Existing-source cleanup
is deferred, so existing findings remain blocking rather than receiving
automatic exceptions.

```odin
build_scene_batch :: proc(
    state: ^Euclid_General_State,
    generation: u64) -> (Scene_Command_Batch, bool) {
    batch := Scene_Command_Batch {
        generation = generation,
    }
    return batch, validate_scene_batch(state, &batch)
}
```

Keep wrapped calls compact, but do not compress unrelated arguments onto a line
merely to save vertical space. If a signature repeatedly exceeds the line
limit, reconsider the data shape before inventing unusual alignment.

For Odin, `generation: u64) -> (Scene_Command_Batch, bool) {` demonstrates the
required terminal shape. The final parameter, closing parenthesis, return
declaration, and opening brace remain one continuous header.

### Compiler Cleanliness

Odin production code MUST compile cleanly under:

```text
-vet -strict-style -disallow-do -warnings-as-errors
```

These flags catch unused values, shadowing, discouraged syntax, and other style
defects. The repository intentionally does not use `-vet-tabs`, because that
flag requires tabs while this project requires spaces. Do not suppress a
warning when a clearer declaration or control flow removes it.

### Design and Initialization

- Prefer `value := expression` when the inferred type is clear and is not
  itself a contract.
- Use an explicit type for ABI layout, fixed numeric width, union selection,
  empty/default values, or when it materially improves understanding.
- Prefer `value := Some_Type { ... }` over `value: Some_Type = { ... }`.
- Initialize coherent state in one struct literal rather than declaring and
  assigning fields later.
- Use field names in nontrivial literals. Positional literals are acceptable
  only when their meaning is immediate and stable.
- Avoid mutable globals. Constants and immutable lookup data are acceptable
  when module ownership is clear.

```odin
runtime := Julia_Runtime_Service {
    owner_thread_id = owner_thread_id,
    state           = .Starting,
}
```

Do not repeat a type annotation that inference already proves unless that
annotation documents a meaningful boundary.

### Procedures and Control Flow

- Give each procedure one observable purpose.
- Prefer guard clauses when they remove deep nesting and keep failure paths short.
- Keep state transitions explicit; do not encode lifecycle state in unrelated booleans.
- Prefer a struct when several parameters travel together or share validation/ownership.
- Do not use `do` syntax; the build rejects it with `-disallow-do`.
- Avoid hidden mutation through broadly shared pointers. Pass the narrow owner
  or subsystem needed.
- For an approved two-item tuple, return the primary value first and status
  second unless an established API contract requires another order.
- Replace wider positional returns with an `Ada_Case` result struct and
  descriptive fields.

### Comments and Function Placement

- Public/cross-file functions should appear near the top of a file.
- Every named procedure MUST have a doc comment directly above its declaration,
  including local and file-private helpers.
- Every reusable named type, enum, procedure group, and package-level
  subsystem contract MUST have a doc comment.
- A concise one-sentence comment is sufficient for a simple helper, but omission is not.
- Keep helpers near the owning operation when they are not part of the
  package-facing surface.
- Document invariants, ownership, units, valid ranges, and failure semantics
  that types do not show.
- Do not narrate assignments, loops, or conditionals that are already clear from the code.

```odin
// Return the published scene batch when its generation is current.
resolve_scene_batch :: proc(
  state: ^Euclid_General_State,
  generation: u64) -> (Scene_Command_Batch, bool) {
    // ...
}
```

Use normal Odin documentation comments immediately before the declaration. Do
not separate the comment from its declaration with unrelated constants,
attributes, or implementation notes.

### Resource Management

- Make allocation owner, mutation owner, recycler, and teardown point
  identifiable from the API.
- Use `defer` when multiple exits require the same guaranteed cleanup.
- Avoid `defer` in a simple single-exit path when direct cleanup preserves
  clearer linear flow.
- Pair acquisition and cleanup visibly. Transfer ownership only through a
  documented operation.
- Do not retain temp-allocator memory beyond its reset boundary.
- Use bounded, preallocated storage in steady frame paths unless an approved
  exception applies.

### Compile-Time SQL Sources

- **Review:** Production schemas and named reusable SQLite statements SHOULD live
  in `.sql` files under the owning subsystem's `sql/` directory, embedded through
  named Odin constants using `#load("sql/name.sql", string)`.
- **Review:** Convert loaded constants explicitly with `cstring(CONSTANT)` at
  SQLite call boundaries. This constant conversion does not justify casting
  arbitrary runtime strings without NUL-termination and lifetime guarantees.
- **Review:** Preserve parameter indexes, result-column order, and row ordering as
  contracts with binding and decoding code. Validate changes with the owning
  subsystem's execution tests, not syntax highlighting alone.
- **Review:** SQL files are compile-time source inputs, not runtime assets.
  Build reuse and fingerprint policies MUST include them where compiled outputs
  are cached. Do not introduce generated Odin source for simple embedding.
- **Review:** Tiny transaction mechanics and test-local fixture/mutation SQL may
  remain inline; do not extract every SQL fragment merely for uniformity.

## Julia Rules (Required)

### Formatting and Structure

- 4-space indentation.
- Keep wrapped calls compact and readable.
- In every declaration and call, `)` MUST remain on the final parameter or argument line.
- Keep a Julia return annotation such as `::Result` on that same completed header line.
- Prefer functions over top-level script logic.
- Avoid non-const globals; prefer explicit state paths.
- Do not parenthesize `if` or `while` conditions.
- Use blank lines to separate concepts, not individual statements.
- Keep executable module initialization narrow and obvious. Content
  registration is an explicit project exception, not a general license for
  top-level computation.

```julia
function resolve_entry(
  module_ref::Module,
  symbol::Symbol)::Union{Nothing,Function}
  return isdefined(module_ref, symbol) ? getfield(module_ref, symbol) : nothing
end

entry = resolve_entry(
  runtime_module,
  callback_symbol)
```

### Docstrings

- Every named function MUST have a Julia docstring attached directly to its binding.
- Every module and reusable named type MUST have a docstring.
- A concise one-sentence docstring is sufficient for a simple private helper,
  but omission is not.
- Multiple methods MAY share one canonical function docstring when they
  implement the same semantic contract. A method with distinct constraints,
  side effects, ownership, or failure behavior needs its own documentation.
- Anonymous functions and one-off callback literals do not require independent
  docstrings; document the named operation or value that owns their behavior.
- Generated methods MAY be documented at their generator when the generated
  contract is uniform and the generated bindings remain discoverable.

```julia
"""Return the current callback binding, or `nothing` when the symbol is undefined."""
function resolve_entry(
  module_ref::Module,
  symbol::Symbol)::Union{Nothing,Function}
  return isdefined(module_ref, symbol) ? getfield(module_ref, symbol) : nothing
end
```

Use Julia docstrings, not detached `#` comments, for named API documentation
so `Docs` metadata and the future generated Code reference can discover it.

### Naming and API Semantics

| Construct | Form | Guidance |
| --- | --- | --- |
| Module/type | `CamelCase` | Use full domain words when practical. |
| Function | lowercase | Use `snake_case` when squashed words are hard to read. |
| Mutating function | trailing `!` | Required when an explicit argument is mutated. |
| Constant | `CamelCase` or established local form | Keep related modules internally consistent. |
| Internal name | descriptive name | `_` may signal internal status but does not enforce privacy. |

- Avoid inconsistent abbreviations; concise names are useful only when callers
  can remember them.
- A `!` signals mutation beyond implicit advancement of an `IO` or RNG
  argument. For example, `read(io)` need not end in `!`, while a function that
  also mutates a destination buffer should.
- Provide copying and mutating pairs only when both semantics are useful and
  their cost difference is meaningful.
- Do not use naming to hide side effects. Document host mutation performed
  through bridge calls.

### Type and Dispatch Style

| Prefer | Avoid | Reason |
| --- | --- | --- |
| `f(x)` when operations define the contract | `f(x::Int64)` by habit | Julia specializes generic code. |
| `Integer` or `Number` when semantically required | One concrete numeric type | Preserve valid callers. |
| Conversion at the caller | Silent broad conversion inside a narrow API | Caller chooses rounding/loss policy. |
| Simple `Union` or `nothing` sentinel | Unrelated multi-concept unions | Complex unions hide weak models. |
| A clear abstract container contract | Elaborate unions inside container types | Simpler dispatch and inference. |
| `isa` and `<:` for type relationships | Exact type equality by default | Subtypes remain valid. |

- Add a type constraint when it defines dispatch, rejects an invalid domain, or
  documents an ABI.
- Exact bridge types such as `Cint`, `Cfloat`, and `Ptr{Cvoid}` are contracts,
  not overspecification.
- Avoid a static parameter when the type variable is not needed; use
  `typeof(x)` when that is the actual requirement.
- Decide whether a concept is represented by a type or an instance and use that
  choice consistently.
- Avoid type piracy. A tightly coupled interoperability extension requires
  explicit justification, tests, and ownership documentation.
- Do not overload methods on broad Base container types to customize one
  element type. Define behavior on a project-owned wrapper or project-owned
  function instead.

### Interfaces and Encapsulation

- Prefer exported methods over direct field access outside the type's owning module.
- Treat fields and non-exported functions as implementation details unless
  documented otherwise.
- Expose conceptual operations that can support multiple implementations, not
  storage layout.
- Unsafe operations MUST be checked or include `unsafe` in the public name.
- Do not expose raw pointers through ordinary collection-like syntax that appears safe.
- Constructors named `T(...)` MUST return an instance of `T`.

### Argument Order

Follow Julia Base ordering when applicable:

| Priority | Argument role | Example |
| --- | --- | --- |
| 1 | Function/callback | `map(f, values)` |
| 2 | `IO` stream | `show(io, value)` |
| 3 | Input being mutated | `fill!(destination, value)` |
| 4 | Output type | `parse(Int, text)` |
| 5 | Non-mutated input | Domain inputs after destination/type. |
| 6 | Key/index, then value | Preserve familiar collection order. |
| 7 | Other positional arguments | Stable domain order. |
| 8 | Varargs | Last among positional arguments. |
| 9 | Keyword arguments | Last; use for optional policy, not required identity. |

Bridge wrappers MAY put `state_ptr` first because it is the mutated host
context and an established project convention. Do not reorder one wrapper
independently from related APIs.

### Functions, Macros, and Control Flow

- Pass a named function directly instead of wrapping it as `x -> f(x)`.
- Avoid splatting merely to collect or concatenate values; use direct
  iteration, `collect`, or the appropriate concatenation operation.
- Prevent predictable invalid states instead of using broad `try/catch` as
  ordinary control flow.
- Catch at a boundary only when the boundary can add context, recover,
  translate the error, or preserve host safety.
- Prefer a function over a macro when runtime values are sufficient.
- Treat `eval` inside a macro as a design warning; it couples behavior to top-level scope.
- Use integer literals in generic numeric code when a floating literal would
  force unwanted promotion. Use `oneunit`, `zero`, or similar generic
  constructors when they express the intent.

### Embedded Runtime Rules

- Julia C API calls remain on the persistent owner thread, including exception
  inspection and shutdown.
- Use `Base.invokelatest` only where freshly evaluated Terminal session or reload
  definitions require latest-world dispatch. Do not spread it into ordinary
  static call paths.
- After dynamically including content, inspect its module bindings with
  `Base.invokelatest(getfield, module, name)` and check their existence with
  `Base.invokelatest(isdefined, module, name)`. Invoke freshly loaded functions
  through `Base.invokelatest` as well; guarding only the function call does not
  protect an older-world binding lookup. The Julia application test runner uses
  `--depwarn=error` to reject world-age compatibility warnings.
- Keep bridge calls and their status handling visible. Stop transactional
  emission after failure.
- Do not retain host pointers beyond their documented generation or lifecycle.
- Runtime-loaded scripts must surface parse, load, and evaluation failures with
  useful context.

### View Content Rule

- Keep `get_view_content` as a named producer returning one canonical displayable:
  an ordinary string for `text/plain`, `L"..."` for standalone delimited math, or
  `tex"..."`/`TeXDocument` for an unwrapped document.
- Invoke the producer through `publish_view_content` from lifecycle or
  semantic-change points. Do not register it as a native callback or poll it per frame.
- The selected MIME bytes are authoritative for rendering, copying, hashing, and
  literal failure. Do not maintain a second fallback representation.
- Do not manually pre-wrap ordinary view content unless fixed-width or semantic
  layout demands it.

### Function/Control Flow Guidance

- Keep local conversions close to the boundary that requires them.
- Use `eachindex` or the collection's interface rather than assuming one-based
  contiguous indices.
- Prefer methods that describe behavior over caller access to representation fields.
- Keep return shapes stable. Use a named `CamelCase` struct when several
  outputs form one enduring concept or when a result would otherwise exceed
  two positional values.

### Animation-Script Exception

- Animation definition files may keep longer phase-oriented `loop` functions
  when that improves readability of animation state flow.
- This exception is narrow and does not waive general clarity requirements.

## Documentation Rules

### Markdown Structure

- Every Markdown file must have exactly one H1.
- Heading levels must be sequential.
- Use direct, technical, non-hedging language.
- Use fenced code blocks with language tags when practical.
- Keep list formatting consistent.
- Use ordered lists for procedures and unordered lists for constraints or unordered facts.
- Use inline code for paths, commands, identifiers, flags, and literal values.
- Use repository-relative internal links.
- Keep prose within the 120-character hard line limit.

### High-Value Presentation

Choose the representation that makes comparison or flow easiest to verify:

| Information | Preferred form |
| --- | --- |
| Small set of independent rules | Bullets. |
| Ordered procedure or precedence | Numbered list. |
| Several items with the same attributes | Table. |
| Ownership, state, or message flow | Mermaid diagram plus a short textual contract. |
| Exact accepted/rejected syntax | Small paired code examples. |
| Rationale with exceptions | Short prose immediately after the rule. |

- Do not force prose into a table when cells need multiple paragraphs.
- Do not use a diagram for a sequence that a short numbered list communicates better.
- A diagram supplements the normative text; it does not become the only
  statement of a requirement.
- Prefer one strong example over several nearly identical examples.

### Doc Comments And Docstrings (Required)

Doc comments are mandatory source code, not optional polish. They are the
canonical prose for the future generated Code reference and part of the
declaration's review contract.

| Declaration | Requirement |
| --- | --- |
| Named Odin procedure | Doc comment required, including private helpers. |
| Named Julia function | Docstring required, including private helpers. |
| Package/module | Document its responsibility and boundary. |
| Reusable type or enum | Document meaning, invariants, and ownership where applicable. |
| Bridge declaration/wrapper | Document ABI inputs, outputs, mutation, ownership, and failure. |
| Constant | Document when units, sentinel meaning, limits, or policy are not obvious. |
| Anonymous local callback | No separate docstring; document the named owning operation. |

- Begin with a useful summary of behavior, not the declaration restated in English.
- Record side effects, units, valid ranges, ownership transfer, thread
  affinity, and failure semantics when they are part of the contract.
- Describe parameters and return values when names and types do not make their
  roles obvious.
- Keep documentation attached to the declaration so language tooling and Wiki
  extraction can find it.
- Keep implementation commentary near the invariant or unusual decision it explains.
- Remove stale comments in the same change that makes them stale.
- Do not preserve duplicate prose in several files. Keep one canonical
  explanation and link to it.

## Error Handling, Performance, Safety

### Error Handling

- Validate external input and cross-module contracts at the receiving boundary.
- Fail fast on violated invariants; return a typed status for expected
  operational failure.
- Do not partially publish state. Build or mutate in staging, validate, then
  commit atomically.
- Error messages must identify the operation and include relevant request,
  generation, symbol, path, or index context without exposing secrets.
- Catch an error only to recover, add context, translate across a boundary, or
  preserve host safety.
- Do not swallow exceptions/errors or replace them with empty output without
  explicit justification.
- Cleanup and completion reporting must run on both success and failure paths.

| Failure kind | Preferred response |
| --- | --- |
| Programmer invariant violation | Assert or fail immediately with context. |
| Invalid external/user input | Reject at the boundary with an actionable message. |
| Capacity/backpressure | Return explicit status; apply documented retry/drop policy. |
| Transactional bridge failure | Stop emission, discard staging, retain canonical state. |
| Optional presentation failure | Use a documented complete fallback. |
| Required lifecycle failure | Report identity and follow bounded terminal policy. |

### Performance and Allocation

- Optimize with evidence, not guesswork.
- Prefer algorithm, data-layout, and work-elimination improvements over
  incidental syntax tricks.
- Measure representative workloads before and after a non-obvious optimization.
- Follow the [memory standard](MemoryArchitecture.md#allocation-and-lifetime-standard)
  for storage and allocation policy.
- Keep Julia performance-critical code inside functions and avoid untyped mutable globals.
- Do not make a Julia API artificially concrete for performance; Julia
  specializes generic methods.
- Make performance-motivated complexity local and document the measured reason.

### Safety

- Do not expose unsafe low-level operations as default APIs.
- Compile automation capable of injecting terminal input or Julia work only into
  repository debug/test builds. Production builds must retain a secure-disabled default.
- Validate external/input data at boundaries.
- Keep interop assumptions explicit and documented.
- Keep pointer validity, count/span relationships, ABI widths, and nullability explicit.
- Follow [memory lifetime and retirement rules](MemoryArchitecture.md#initialize-reuse-and-retire)
  for borrowed storage and generation-bound handles.
- Thread-affine Julia, rendering, window, and audio operations must remain on
  their owning threads.
- Prefer bounded failure over unchecked truncation, overflow, or queue growth.

## Standard Updates

- Changes to this document must preserve clarity and enforceability.
- When a change affects automated policy, update `tools/analysis_settings.jl`
  in the same change and verify the resulting analysis behavior.
- Avoid optimizing this document for line count when doing so removes
  rationale, scope, exceptions, or enforcement guidance.
- Use tables and diagrams when they compress repeated structure without hiding nuance.
- Recheck upstream guidance periodically, but do not adopt upstream changes
  that conflict with an intentional repository policy.

A standards change SHOULD identify:

| Field | Question answered |
| --- | --- |
| Rule | What behavior or form is expected? |
| Rationale | What defect or inconsistency does it prevent? |
| Scope | Which languages, modules, or paths does it govern? |
| Exceptions | When is the normal form worse? |
| Enforcement | Is it automated, review-enforced, or both? |
| Migration | Does existing code need immediate or incremental cleanup? |
