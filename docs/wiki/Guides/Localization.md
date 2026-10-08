# Localization And Editions

This guide is for people authoring localized content and programmers extending its
consumers. It explains what to edit, what must stay stable, and how to verify a change.
For database schema, package admission, worker ownership, and retirement mechanics,
use [SQLite Architecture](Sqlite3.md). For rendered prose and mathematics, use
[LaTeX Support](LaTeXSupport.md).

## Table Of Contents

1. [What The System Does Today](#what-the-system-does-today)
1. [Keep These Concepts Separate](#keep-these-concepts-separate)
1. [Source Map](#source-map)
1. [Writing Shell Messages](#writing-shell-messages)
1. [Naming And Adding Content](#naming-and-adding-content)
1. [Declaring Editions](#declaring-editions)
1. [Preparing Another Locale](#preparing-another-locale)
1. [Using Messages From Odin](#using-messages-from-odin)
1. [Reading Specifications From Julia](#reading-specifications-from-julia)
1. [Extending The System](#extending-the-system)
1. [Verification And Review](#verification-and-review)

## What The System Does Today

The shipped application uses en-US shell messages and catalogue names, plus three
ordinary edition declarations: original EuclidApp content, edited Heath, and edited
Townsend. Native consumers resolve messages, names, and initial animation
specifications from one admitted packaged content generation.

This is not yet a locale-selection or edition-switching product. There is no
production selector, switching setter, selection-change delivery scheduler, or
multilingual search policy. The Ancient Greek edition used in tests proves language
independence; it is not shipped content.

Edition metadata does not supply a translated document or automatically choose a
different text producer. Animations still publish their own canonical View content.
Do not promise translated presentation merely because a locale or edition record
can be admitted.

## Keep These Concepts Separate

| Concept | Meaning | Must not be used as |
| --- | --- | --- |
| Animation identity | Permanent UUID and source namespace of a subject | A translated label or edition identifier |
| Application locale | Locale used for shell messages and catalogue names | A requirement that all displayed source texts use that language |
| Edition | Stable ID, unique name, text language, and provenance description | A new animation implementation or lifecycle |
| Availability | An edition offered for a subject under an application locale | An implicit fallback chain |
| Selected specification | Immutable selection facts belonging to one callback | Provenance retroactively attached to old presentation bytes |
| Published presentation | Exact MIME value last published by the author | Automatically regenerated text when metadata changes |

A renamed or translated catalogue label keeps its UUID. Original and adapted
content use the same edition contract. An English shell may accompany an edition
whose text language is Greek. Selection revision is independent of content/runtime
generations: unchanged selection survives ticks, reset, and reload without a new
revision.

## Source Map

Paths below are repository-relative. Edit authored sources, not generated SQLite,
asset archives, extracted caches, or generated wiki pages.

| Source | Contributor responsibility |
| --- | --- |
| `src/content/localization/ui_messages.jl` | Stable shell-message declarations, developer context, typed arguments, and en-US templates |
| `src/content/localization/catalog_names.jl` | Explicit locale-scoped names keyed by namespace and UUID |
| `src/content/localization/editions.jl` | Edition identity, unique name, text language, and provenance |
| `src/content/localization/edition_assignments.jl` | Explicit en-US default edition assignments by UUID |
| `src/content/localization/manifest.jl` | Assembly of locale, translation, subject, and availability records |
| `src/content/animation_catalog_data.jl` | Catalogue UUIDs, topology, ordering, and implementation paths |
| Adjacent `*_content.jl` files | Canonical authored View content and semantic search text/aliases |
| `src/julia/localized_content.jl` | Typed declaration contracts and complete manifest validation |
| `src/core/content/messages.odin` | Native message IDs, required keys/signatures, and bounded formatter |
| `src/view/messages/messages.odin` | Display-owned static cache and caller-storage formatting helpers |
| `src/core/content/specification.odin` | Bounded native selection values and revision rules |
| `src/julia/bridge/content_specification.jl` | Read-only callback query and symmetric copy-out ABI |

The [SQLite module map](Sqlite3.md#module-map) identifies corpus, builder, runtime,
and packaging owners when a change extends beyond authoring.

## Writing Shell Messages

### Change Wording Without Changing Identity

For an existing message, edit its authored template and improve developer context
when needed. Keep its native ID, key, argument names, and argument kinds stable.
Context should explain where the text appears, whether it is visible or accessible,
and what substituted values mean.

For example, the existing search correction message uses:

```text
Use suggested search: {query}
```

A translation may move or repeat `{query}`, but must retain the exact set of declared
placeholder names. Do not translate `query` itself or omit it. Supply a complete
phrase rather than asking the consumer to concatenate translated fragments.

### Respect The Frozen Formatter

Templates support literal UTF-8 and `{identifier}` substitutions only. There is no
expression evaluation, plural syntax, brace escaping, locale-aware number formatter,
or automatic fallback. Placeholder names use `[a-z][a-z0-9_]{0,31}`.

The authored template bound is 128 UTF-8 bytes, not 128 characters. Text arguments
are bounded to 512 bytes; formatted output is bounded to 536 bytes. Integers and
one-decimal floats follow their existing native signatures and precision.
See [Native Shell Messages](Sqlite3.md#native-shell-messages) for supported value
kinds, failure statuses, transactional output, and ownership.

Use valid UTF-8 without NUL. Do not fit a translation by truncating it or silently
dropping a placeholder. If an accurate phrase cannot fit, discuss a deliberate bound
change with the programmer responsible for all affected storage and tests.

Shell messages are not TeX documents. Terminal streams, user input, diagnostics,
stable widget/focus IDs, and authored presentation prose are outside this projection.

### Add A New Message With A Programmer

Adding prose is not sufficient to add a production message. Coordinate:

1. A new stable native ID and semantic key, with useful developer context.
1. The Julia source declaration, typed argument list, and every locale's translation.
1. The Odin enum, required ID/key list, shipped count, and native signature.
1. The actual visible and accessibility consumers, including retained notices.
1. Baseline, signature, formatting, capacity, and consumer-wiring tests.

Native signature lookup currently represents one argument per message, and the
expander has bounded argument tracking. A declaration containing several arguments
does not automatically make the native consumer support them. Extend that contract
symmetrically instead of working around admission.

## Naming And Adding Content

For a name-only change, edit the explicit locale-scoped catalogue name and coordinate
the corresponding descriptor/search expectations. Names feed Library search and
hierarchy paths; tests intentionally detect changes to those bytes.
Keep namespace, UUID, parent identity, and implementation path unchanged unless the
task actually changes content identity or topology. Sibling names must be unambiguous
within each locale; equal labels under different parents are permitted.

For a new animation or grouping entry:

1. Add a permanent UUID, descriptor, parent/order, and safe implementation path.
1. Provide an explicit catalogue name for every admitted application locale.
1. Add an explicit default edition assignment with defensible provenance.
1. Provide the ordinary implementation and adjacent content sidecar.
1. Return canonical View content and bounded semantic search text/aliases from the
   sidecar; keep search prose useful for discovery rather than copying TeX markup.
1. Verify manifest subjects, names, availability, and search coverage as a complete
   unit, including relevant fixed counts and capacities.

The manifest derives subjects from descriptors and adds the reserved null subject.
Do not add null to the Library tree. Terminal has an explicit catalogue/default
binding but no path-backed semantic prose. Grouping entries with implementations
need sidecars just like leaves.

Follow the [Animation Program Contract](AnimationsStyle.md#animation-program-contract)
for initialization, callback dispatch, UUID agreement, and ordinary publication.
Follow [LaTeX recommended usage](LaTeXSupport.md#recommended-usage) for one canonical
MIME value and its exact-source failure behavior.

## Declaring Editions

An edition declaration contains:

- `edition_id`: stable identity, at most 64 UTF-8 bytes;
- `unique_name`: globally unique human-readable name, at most 256 bytes;
- `text_language_tag`: independent text-language metadata, at most 35 bytes;
- `description`: provenance and meaningful editorial context, at most 1,024 bytes.

Do not invent attribution from a filename or assign an adapted edition merely because
the subject resembles its source. Explain the source and editorial treatment accurately.
Original authored content is an ordinary edition, not a missing-edition fallback.

Availability records bind namespace, subject UUID, application locale, edition ID,
and default status. Each subject/locale pair requires exactly one default; additional
non-default availability records must not duplicate an existing binding. References
to unknown subjects, locales, or editions fail admission.

The current en-US assembly turns explicit UUID assignments into default availability.
To author additional availability, extend that assembly deliberately rather than
adding an unused edition and assuming it is selectable. There is no selector today.
Similarly, declaring a second edition does not install its document producer.

See [Authored Editions And Sidecar Coverage](Sqlite3.md#authored-editions-and-sidecar-coverage)
for uniform admission and the relationship to the existing search projection.

## Preparing Another Locale

Another locale is a coordinated content/code extension, not a one-file translation.
The manifest requires:

- a unique admitted locale tag, with exactly one default locale overall;
- one translation of every shell message in every admitted locale;
- one name for every catalogue node in every admitted locale;
- exactly one default edition for every subject in every admitted locale.

There is no partial-locale publication or fallback to en-US for missing records.
Current source assembly is explicitly en-US, and search export has its own default
projection contract. Review that assembly, native admission, consumers, and search
policy before shipping another locale. Do not claim multilingual search from adding
translations alone.

Byte limits, font coverage, accessible naming, and layout need separate verification.
Language metadata alone does not prove readable glyphs, shaping, bidirectional layout,
or appropriate search tokenization. Consult [LaTeX Character Support](LaTeXSupport.md#character-support)
and the [SQLite constraints](Sqlite3.md#current-constraints) when planning the change.

## Using Messages From Odin

Display code uses `viewmessages.shell_message` for static text and
`viewmessages.shell_format` for dynamic text. Pass named `Content_Format_Argument`
values with the exact wire kinds; allocate output storage in the caller's appropriate
owner. A count that happens to fit in `u32` still must be `i64` when its signature
requires that kind.

Static helpers return text in the display-owned cache, not SQL column or generation
storage. That cache can be refreshed, so copy text that must survive later refreshes.
Formatted text borrows the supplied output buffer. Consume it immediately or copy it
into the existing retained-note, prepared-draw, semantic, or accessibility owner.
Never retain a stack-backed string for a future frame.

Low-level lookup views borrow a content generation and must not escape its retirement
boundary. Do not call SQL or Julia to obtain labels in frame code. Do not substitute
hard-coded English after lookup failure: use existing explicit status/diagnostic
handling. For details, see [ownership and failure semantics](Sqlite3.md#failure-and-lifecycle-semantics).

## Reading Specifications From Julia

Inside Enter, Tick, or Exit, read:

```julia
specification = OdinJuliaBridge.animation_content_specification(state_ptr)
```

The owned immutable value exposes `application_locale`, `edition_id`, `edition_name`,
`edition_text_language`, `selection_revision`, `animation_identity`,
`content_generation_identity`, and `runtime_generation_identity`.
It contains no borrowed SQL or native-arena pointer. A retained value is only a
historical snapshot, not a way to query the current selection later.

The query is illegal outside a legitimate callback or with another state pointer.
Do not manufacture invocation scope in production, poll it from a background task,
or provide a default specification on failure. Old Exit and rollback Enter see their
own active value; replacement Enter sees pending selection; Tick sees its submission
snapshot. Keep the latest-world callback boundary for reloadable Julia content.
See [Invocation Content Query](JuliaThreadArchitecture.md#invocation-content-query).

All entries must recognize operation `4`,
`ANIMATION_OPERATION_PRESENTATION_SELECTION_CHANGED`, as successful no-op and reject
unknown operations. It is not a zero-duration Tick: no clock/RNG, geometry, particles,
pause, or presentation effects are permitted. No production delivery exists.
Do not use it to introduce edition switching implicitly.

## Extending The System

Put each change in the owning subsystem:

- Julia declarations own authored facts and validation, not runtime SQLite access.
- The builder owns schema, SQL insertion/indexing, reproducibility, and corpus policy.
- The content worker owns immutable runtime connections and complete admission.
- Native generations own bounded records and packed text.
- Display consumers own visible state and retained copies.
- The Julia host owns callback execution; the bridge transfers checked copied values.

Admission and reload publish all projections together. Never accept a catalogue while
discarding invalid messages or editions. A failed candidate must preserve the active
dataset; retired storage stays alive until publication and lifecycle work no longer
need it. Use the [SQLite lifecycle contract](Sqlite3.md#failure-and-lifecycle-semantics)
rather than creating a second registry or connection path.

Changing a bound, signature, schema, or ABI requires updating every corresponding
declaration, native record, validator, transport, consumer, and boundary test.
Do not add hidden frame-time growth, unbounded translation maps, fabricated allocator
contexts, or another text producer as a shortcut. Future switching and delivery need
explicit policy and evidence for paused behavior, revision changes, and publication;
the existing representational capacity is not that policy.

## Verification And Review

Choose evidence for the changed surface:

| Change | Evidence to update or run |
| --- | --- |
| Message wording/signature | Julia manifest tests; native formatter baselines, precision, errors, and bounds; packaged consumer and retained-text tests |
| Names/new entries/sidecars | Catalogue/corpus identity and coverage tests; native admission; Library search and focus scenarios |
| Editions/locales/defaults | Manifest duplicate/missing/unknown-reference tests; native admission and language-independence fixtures; actual rendered/accessibility review |
| Native lifetime/reload | Complete-candidate retirement tests; initial specification/reset/reload acceptance and both rollback scenarios |
| Query/ABI/notification | Native lifecycle/Tick identity and revision tests; Julia layout/scope tests; headless no-op/RNG/state comparisons |
| Documentation | Wiki generation and deterministic link/artifact verification |

Run documented complete language suites when developing; the driver does not accept
additional file or test-name selectors:

```sh
julia tools/make.jl unit julia
julia tools/make.jl unit odin
```

Changed content/package inputs require asset regeneration and admission. Do not edit
generated databases. Run asset-producing operations sequentially:

```sh
julia tools/make.jl assets
julia tools/make.jl harness
julia tools/make.jl scenario content-specification-acceptance
julia tools/make.jl scenario library-search
julia tools/make.jl scenario keyboard-focus-acceptance
julia tools/make.jl scenario mime-presentation-acceptance
```

For substantive implementation/content changes, finish with the canonical gate.
For this guide or other authored-guide changes, regenerate and verify the wiki:

```sh
cmake --build --preset default --target check
julia tools/make.jl wiki
julia tools/make.jl check-wiki
```

Unit tests and screenshots alone do not establish a complete acceptance claim.
Scenario evidence needs a passed manifest, complete required trace, no bad frees,
and orderly shutdown. Record intentional wording/search changes honestly rather
than updating equivalence baselines to conceal an unintended regression.
