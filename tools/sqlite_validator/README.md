# SQLite Validation Runner

This Euclid-owned tool implements the analyzer's
[SQLite protocol version 1](../analysis/README.md#sqlite-runner-protocol-version-1).
It imports `src/sqlite` and the repository's native SQLite bindings; it never
uses the host SQLite CLI or another SQLite distribution. The tool implements
validation; Euclid's production settings separately enable the typed cases and
require dedicated-source coverage.

```sh
julia tools/make.jl sqlite-runner
julia tools/make.jl sqlite-runner-test
julia tools/make.jl sqlite-adoption-test
```

`sqlite-runner` builds or reuses the strict Odin executable under
`.build/sqlite-validator/` and publishes/prints its stable absolute executable path.
The cache hashes the
runner, substrate, bindings, build helper, compiler version, platform, SQLite
artifact identity and archive digest, and linker/compiler flags. Cache hits verify
the binary's SHA-256 before reuse. SQLite linkage uses `sqlite3_artifact` and
`sqlite3_tool_linker_flags` from `tools/build_config.jl`.

`sqlite-runner-test` exercises the native runner, cache repair and provider
identity, then launches analyzer/native protocol integration tests with
`--project=tools/analysis`. Tests include timeout isolation and independent
case continuation. The analyzer remains responsible for case timeouts; the
runner does not silently truncate SQL execution.

`sqlite-adoption-test` runs the production cases against every discovered
first-party SQL source and verifies the blocking rules, coverage and adapter
reporting. The cases live in [`sqlite_cases.jl`](../sqlite_cases.jl), not in the
analyzer. Normal Euclid `check`, `vet`, `test` and CMake gates prepare the runner
through [`analysis_bootstrap.jl`](../analysis_bootstrap.jl) before invoking
production validation. Stats, help and custom consumer settings do not implicitly
build this provider. Direct analyzer callers must prepare it explicitly.
Normal verification keeps the code-statistics table adjacent to COCOMO/LOCOMO
estimates. Successful SQLite case/provider and inventory details stay in analysis
reports; failed or incomplete native validation remains visible in diagnostics.

Each process consumes one JSON request from stdin and emits one JSON result on
stdout. Invalid protocol input exits nonzero with a bounded stderr diagnostic;
SQL validation failures return structured JSON and exit zero. Allocations are
process-local and survive through result serialization. A fresh `:memory:`
connection belongs exclusively to that process; every native statement is
explicitly finalized, transaction state is checked before cleanup rollback,
and connection close is checked.

Limits are 8 MiB request, 256 steps, 1 MiB UTF-8 SQL per step, 32,766 binding
slots, and 2 MiB response. Individual diagnostic messages are bounded to 2 KiB
without cutting a UTF-8 code point. IDs are at most 1,024 bytes; source IDs at
most 2,048 bytes. Source digests are SHA-256 of exact UTF-8 bytes. Parameter
coordinates are one-based, half-open UTF-8 byte ranges.

Supported declared capabilities are `fts5` and `spellfix1`. Declaring `fts5` admits
both its `fts5` and `fts5vocab` virtual-table modules; neither is admitted without
that requirement. The result records
the actual SQLite source ID, version, and available supported capabilities.
Spellfix is registered only when declared; virtual table creation admits only
declared supported modules. Loadable extensions are omitted by Euclid's
provider, disabled through connection configuration, and denied by the SQL
authorizer. The authorizer rejects ATTACH/DETACH, VACUUM INTO's attachment,
extension/file helper functions, unsafe directory PRAGMAs, writable schema,
and file-backed temporary storage. Ordinary production builder PRAGMAs retain
their SQLite semantics. This is constrained execution of trusted repository SQL,
not a general hostile-SQL sandbox.
