# Euclid Collections File Format

## Status and Scope

This guide specifies the document format used to exchange Euclid collections.
The file extension is `.euclid`. The proposed media type is
`application/vnd.euclid.collections`; this value is a placeholder pending
registration.

The document defines record syntax, collection schema version 1, compatibility,
and reader and writer requirements. A collection is a named container. Each
entry references exactly one animation, and entries may contain child entries.

## Design Rationale (Non-Normative)

The format is machine-first but human-edit-capable. With a text editor, a person
can rename a collection or entry, rewrite notes, delete an entry, or reorder
siblings. These changes operate on a whole record or literal block. The format is
edit-capable, not authoring-friendly: hand-authored documents must keep scopes
balanced, maintain unique document-local IDs, and avoid delimiter collisions.

The format is a **JSONL-derived stream format**, not JSONL. It has exactly three
extensions over JSONL:

1. A required header record identifies the format and declares versions and
   required capabilities.
2. `begin` and `end` records represent hierarchy in document order.
3. Literal blocks carry raw text in either delimiter or byte-counted form.

Record isolation is the leading design argument. Each record is an independent
parse unit, so a reader can identify malformed or unsupported content and apply
`failure_scope`, `requires`, `optional`, and `preserve` without making every
record in the document one all-or-nothing parse unit. A single JSON document
would lose that isolation: one malformed value invalidates the whole document,
and partial understanding has no natural record boundary.

| Alternative | Strength | Reason not selected |
| --- | --- | --- |
| YAML | Readable; block scalars represent multi-line text. | The reference implementation has no YAML parser, and a correct one is a substantial dependency. Implicit typing, indentation-dependent meaning, and anchors complicate predictable validation and hand editing. |
| TOML | Literal strings can represent notes. | The reference implementation has no TOML parser. A deeply nested entry tree would require increasingly long table headers, and sibling order across depths does not fit naturally into the document's ordered records. |
| Single JSON document | Strict parsing is available; duplicate keys can be rejected. | Notes require escaping, nested structure makes hand edits brace-sensitive, and one parse offers no record-level isolation. |
| Plain JSONL | Record isolation and standard tooling. | It has no raw multi-line text or hierarchy without additional conventions. |

Two literal-block forms serve different uses. Delimiters make file blocks easy to
edit by hand. Byte counts suit machine streams. Both forms use exactly one
framing LF after the payload; for byte-counted blocks, that LF makes an incorrect
count fail at a known boundary. Readers accept both forms, while file writers
prefer delimiters.

The preservation tiers borrow the safe-to-copy distinction from PNG chunking,
adapted to semantic record content.

The record syntax is shared so a future peer-sharing protocol can use the same
record representation, but the protocol is a separate standard with its own
behavior. This guide defines no protocol behavior. The accepted cost is that
standard JSONL tools such as `jq` cannot read the complete file because literal
block lines are not JSON records.

Euclid's scenario and evidence tooling already uses bounded JSON Lines, providing
project precedent for line-oriented records with explicit limits.

## 1. Conformance Language

**MUST**, **MUST NOT**, **SHOULD**, **SHOULD NOT**, and **MAY** express
requirements, prohibitions, recommendations, and permitted choices.

Sections 2.1 through 2.4 form the **Record Syntax**. Other Euclid standards MAY
reference the Record Syntax and restrict which permitted forms they send. They
MUST NOT redefine it.

The Record Syntax is incrementally processable. A reader can recognize a record
or block when its final required byte arrives, without lookahead beyond the
current line or declared block length.

Content identity is defined over parsed content, never serialized bytes. Any
future digest, signature, or equality check MUST operate on parsed content.

## 2. Record Syntax

### 2.1 Encoding and Record Boundaries

- Record lines and delimiter-form block payloads MUST be valid UTF-8. A document
  MUST NOT begin with a byte-order mark.
- Line endings MUST use LF (`0x0A`), not CRLF. Raw carriage returns are
  prohibited outside byte-counted block payloads. An escaped `\r` in a JSON
  string does not affect record framing.
- Byte-counted block payloads are opaque to the Record Syntax. Their record
  types govern payload encoding and content.
- Every document MUST end with LF.
- Outside literal blocks, each nonempty line MUST contain one complete JSON
  object. JSON arrays and scalar values are not records.
- Empty lines outside literal blocks MAY separate records and have no meaning.
  Whitespace-only lines MUST be rejected.
- JSON records MAY contain ordinary JSON whitespace but MUST NOT span lines.
- JSON comments, duplicate object keys, and non-JSON values such as `NaN` are
  invalid.
- JSON member order has no semantic meaning. Physical record order does.

This is a JSONL-derived stream format: literal blocks contain non-JSON lines.

### 2.2 Common Record Framing

The first physical line is the document header described in Section 3. Other
records use these reserved members:

| Member | Meaning |
| --- | --- |
| `type` | The record's nonempty semantic type name. |
| `id` | A document-local identity where required by the record type. |
| `begin` | Boolean; `true` opens a scope. |
| `end` | Closing record naming the innermost open scope's ID. |
| `block_end` | Nonempty literal-block terminator string. |
| `block_bytes` | Nonnegative integer literal-block payload length in bytes. |
| `optional` | Boolean; `true` permits omission of the record or scope. |
| `failure_scope` | The scope of content omitted when a reader cannot interpret a record. |
| `preserve` | Preservation requirement for the record's content. |

A normal record MUST have `type`. A closing record instead has only `end`. If
`begin` or `optional` is present, its value MUST be an actual JSON Boolean.
Omitted or `false` `begin` means the record is self-contained and does not close
the surrounding scope.

A record containing `block_end` or `block_bytes` is a block descriptor. It MUST
contain exactly one of those members. A record MUST NOT combine `begin:true` with
either block member. A block descriptor does not open a structural scope.

Unknown record types MUST obey these framing rules. Extensions MUST NOT introduce
unannounced raw sections.

### 2.3 Optional Scopes and Hierarchy

```text
{"type":"entry","id":"parent","animation_id":"550e8400-e29b-41d4-a716-446655440000","begin":true}
{"type":"entry","id":"child","animation_id":"550e8400-e29b-41d4-a716-446655440001"}
{"end":"parent"}
```

- A record with `begin:true` MUST have a nonempty string `id`.
- Scope IDs MUST be unique throughout the document. Collection and entry IDs,
  including IDs on self-contained records, MUST also be unique throughout the
  document.
- IDs are case-sensitive, compared without Unicode normalization, and need not
  be UUIDs. Short human-editable strings are suitable.
- An opening record becomes the innermost scope until its closing record.
- A closing record MUST contain only `end`, whose nonempty string value MUST
  exactly match the innermost open scope's ID.
- Closing an outer scope while an inner scope remains open is invalid.
- An unmatched close or end-of-file with an open scope is invalid.
- Direct child entry records belong to their enclosing collection or entry.
  Their physical order defines sibling order. Metadata records do not occupy
  entry positions.
- The parser MUST determine structure from scopes, not indentation.

An entry that contains children remains an ordinary animation entry. It is not a
group or folder record.

### 2.4 Literal Blocks

A block descriptor introduces literal content immediately after its terminating
LF. Delimiter and byte-counted blocks share one rule: exactly one framing LF
follows the payload. That LF is not part of the payload.

| Form | Descriptor member | Bytes after the descriptor's LF |
| --- | --- | --- |
| Delimiter | `block_end` | payload, framing LF, terminator, LF |
| Byte-counted | `block_bytes` | exactly N payload bytes, framing LF |

Readers MUST accept both forms wherever the Record Syntax applies. Writers of
documents under this standard SHOULD use the delimiter form. A standard that
references the Record Syntax MAY restrict its messages to the byte-counted form.
A document is valid regardless of which form each block uses.

JSON-looking lines, apparent closing records, and apparent block descriptors
inside either block form are literal content. Blocks do not nest. After the
block, the reader returns to record mode. End-of-file before a block is complete
is an error, including for a block whose record type is unknown and optional.

#### Delimiter Form

```text
{"type":"notes","mime":"text/plain","block_end":"::end-notes-1::"}
Start with the segment AB.

Compare AB = AC = BC.
::end-notes-1::
```

The decoded `block_end` string MUST be nonempty and MUST NOT contain LF or CR.
It is matched case-sensitively against an entire subsequent line, excluding that
line's LF, without trimming whitespace or Unicode normalization. The first exact
terminator line ends the block.

The LF immediately before the terminator line is framing, not payload. The
payload consists of the bytes after the descriptor's LF and before that framing
LF. A block MUST contain at least that framing LF before its terminator. Writers
MUST append one framing LF after the exact payload, then the terminator and its
LF. Readers MUST NOT trim or normalize payload whitespace.

For payload `Hello` with no trailing newline, the framing LF begins the
terminator's line. For payload `Hello` followed by one trailing LF, an additional
framing LF precedes the terminator. An empty payload consists of the framing LF
alone before the terminator.

Writers MUST choose a terminator that does not occur as a whole line in the
payload, including its final segment completed by the appended framing LF. A
readable prefix plus a counter is sufficient if collision checking is performed.
Terminators need not be globally unique; matching occurs only in the current
block. There is no delimiter escape syntax.

#### Byte-Counted Form

```text
{"type":"notes","mime":"text/plain","block_bytes":27}
Start with the segment AB.

```

The 27 payload bytes are `Start with the segment AB.` followed by its own LF. The
next LF is the framing LF, shown as the empty line.

- `block_bytes` MUST be a JSON integer of zero or greater, without a fraction or
  exponent. Readers MUST validate it without overflow or lossy conversion and
  MUST check it against applicable limits before reading or allocating payload
  storage.
- A reader consumes exactly the declared number of bytes without scanning them,
  then MUST read exactly one LF. Any other byte or end-of-file is a framing
  error reported at the descriptor's line. The reader MUST NOT search for a
  later synchronization point.
- The payload MAY contain any bytes, including CR, NUL, and invalid UTF-8,
  unless its record type restricts them.
- An unknown optional byte-counted block MAY be skipped by length without
  examining its payload. The framing LF is still required.

The required framing LF makes an incorrect count fail at a known boundary
instead of silently desynchronizing later records.

## 3. Required Header

The first physical line MUST be the document header. Leading empty lines are
invalid. The header MUST occur exactly once and MUST NOT open a scope or literal
block.

```json
{"format":"euclid-collections","framing_version":1,"schema_version":1,"requires":[],"created-on":"2026-11-01T18:00:00Z"}
```

| Field | Requirement | Meaning |
| --- | --- | --- |
| `format` | Required string, exactly `euclid-collections` | Identifies the document family. |
| `framing_version` | Required positive integer | Identifies record, scope, and literal-block framing rules. |
| `schema_version` | Required positive integer | Identifies the semantic schema used by the writer. |
| `requires` | Required array of unique capability-name strings; MAY be empty | Declares capabilities required to interpret the document. |
| `minimum_reader_schema_version` | Optional positive integer | Declares the oldest schema reader that can interpret the document under the compatibility rules. |
| `created-on` | Optional RFC 3339 timestamp string | Time this document was generated. |

Capability names are case-sensitive. A reader MUST reject a document containing
an unknown `requires` name and MUST report that name. Schema version 1 defines
`entry_hierarchy`, which is required when any entry is nested inside another
entry. A document with nested entries MUST include `entry_hierarchy` in
`requires`.

`minimum_reader_schema_version` MUST NOT exceed `schema_version`. If omitted,
its effective value is `schema_version`; compatibility is not inferred.

`created-on` MUST include a timezone. Writers SHOULD emit UTC with `Z`. It is not
the creation time of every contained collection, an ordering instruction, or
proof of provenance. A missing timestamp is valid.

Unknown informational header fields MAY be ignored. Future mandatory
capabilities MUST NOT be introduced solely through an unknown header field that
older readers would ignore.

## 4. Collection Schema, Version 1

### 4.1 Collection

`type:"collection"` records occur only at document root. They require a
document-local `id` and a nonempty string `name`. A collection is a named
container, not an animation, and MUST NOT carry an animation reference.
`begin:true` opens its entries. Without it, the record represents an empty
collection. Collections MUST NOT nest.

A document MUST contain at least one collection record. Multiple collections
retain their physical root-record order.

### 4.2 Entry

`type:"entry"` records occur directly inside a collection or another entry. They
require a document-local `id` and exactly one animation reference:

- `animation_id`: a stable animation UUID string. An entry without it is
  invalid; entries do not represent groups or folders.

An entry MAY also contain:

- `name`: a nonempty authored display-name override.
- `begin:true`: opens the entry's notes and child entries.

Any entry may be a parent, a child, or standalone. Children are themselves
entries and therefore also reference animations. An animation MUST NOT occur
more than once anywhere within one collection's entry tree.

Nested entries require the `entry_hierarchy` capability in the header's
`requires` array. The capability defines nested entries as children of the
enclosing entry; their physical order defines sibling order.

Document-local IDs are structural identities, not permission to overwrite local
records. Animation UUIDs identify referenced content, not entry placement.

### 4.3 Notes

`type:"notes"` records occur directly inside an open entry. They require:

- `mime`: a string whose value is `text/latex` or `text/plain`.
- Exactly one block descriptor, using `block_end` or `block_bytes`.

The notes payload MUST be valid UTF-8 text. At most one notes record is permitted
per entry. Absence means no notes; an empty block means explicitly empty notes.

Notes MAY also contain `notes_on_top`, an actual JSON Boolean. If omitted, its
value is `false`.

Notes attach to the enclosing entry, not the most recently encountered sibling.
Their position among the entry's child records does not change child ordering or
imply presentation order.

## 5. Compatibility and Unknown Content

A reader MUST support the declared `framing_version`. An unsupported framing
version is an error even if a schema compatibility field claims compatibility.

A reader implementing schema version R may accept a document written to schema
version S only when:

1. It supports the document's framing version.
2. For S at or below R, it implements that schema's semantics or an explicit
   migration.
3. For S above R, `minimum_reader_schema_version` is explicitly present and is
   at or below R.
4. It encounters no unsupported required content or invalid known content.

A newer writer claiming compatibility MUST retain the older interpretation of
known records and fields. Additions that alter required meaning MUST raise the
minimum reader version. A compatibility declaration does not replace validation.

### 5.1 Unknown Records and Scopes

- Omitted or `false` `optional` means required.
- An unknown required record MUST be handled according to its `failure_scope`.
- An unknown record marked `optional:true` MAY be skipped.
- A skipped record's literal block, if any, MUST still be consumed and its
  framing validated. A byte-counted block is consumed by length; a delimiter
  block by its terminator.
- An unknown optional open scope MAY be skipped as a whole, including contained
  records and blocks, while validating nesting and delimiters.
- Descendants of a skipped scope MUST NOT be promoted into its parent.
- Required descendants inside a skipped optional scope do not force
  interpretation; the optional scope declares that the entire unit may be
  omitted.
- Known records marked optional MUST still be validated when interpreted.
  Optionality does not excuse malformed input.

Unknown members of known records MAY be ignored only as compatible supplemental
metadata. Future features requiring meaningful interpretation MUST use a
required record or raise the minimum reader version rather than hide required
meaning in an ignorable member.

Readers MUST report skipped content and compatibility-related omissions.
Successful structural traversal does not establish a faithful import.

### 5.2 Failure Scope

`failure_scope` is a reserved string member on non-header records. Its allowed
values are:

| Value | Meaning when a reader cannot interpret the record |
| --- | --- |
| `document` | Reject the entire document. This is the default when `failure_scope` is omitted. |
| `entry` | Omit the nearest enclosing entry and its descendants. If the record is itself an entry, omit that entry and its descendants. This value is invalid when no such entry exists. |
| `record` | Omit this record. If it opens a scope, omit the records in that scope through its matching end as part of the same record unit. |

`failure_scope` applies to well-formed content a reader cannot interpret. Invalid
JSON, invalid framing, mismatched scopes, and other syntax errors MUST reject the
entire document; a failure scope cannot repair malformed structure. Omitted
content MUST NOT be promoted to a different parent under this rule.

### 5.3 Preservation

`preserve` is a reserved string member on non-header records. Its allowed values
are:

| Value | Requirement |
| --- | --- |
| `always` | Implementations MUST preserve the record's semantic content, including its block and scope, even when related content changes. |
| `unmodified` | Implementations MUST preserve the record's semantic content while it remains unmodified. |
| `never` | Implementations have no preservation obligation. This is the default when `preserve` is omitted. |

Preservation concerns semantic content, not identical serialized bytes. An
implementation that cannot meet an applicable preservation requirement MUST
report the loss before completing an operation that discards that content.

### 5.4 Type Namespaces

Bare type names are reserved for this standard. Extension record types MUST use
the owner-qualified form `x.owner.name`, with nonempty owner and name components.
An extension MUST NOT define or use a bare type name.

Importing and then exporting is not necessarily a lossless round trip for
unrecognized content. Implementations MUST preserve content marked `always` or
applicable `unmodified`, or make its omission visible before completing a lossy
operation. Comments, indentation, and JSON member order are not preserved
formatting promises.

## 6. Import and Export Requirements

Readers MUST validate the complete document before committing imported
collections. A rejected or malformed document MUST NOT leave partially imported
collections.

A valid entry whose animation reference is unavailable MUST be omitted. The
remaining available entries in its collection remain eligible for import. Names
MUST NOT resolve an unavailable reference to a different animation, and no
placeholder entry is created. The omitted entry's notes and custom name are
omitted with it.

Children of an omitted entry MUST be promoted to the nearest included ancestor.
They take the omitted entry's sibling position, in their original order. If no
ancestor is included, they become top-level entries of the collection. This
promotion applies only to unavailable animation references. Descendants of a
skipped unknown scope MUST NOT be promoted.

Every imported collection MUST become a brand-new local collection with newly
generated local collection and entry identities. Import MUST NOT merge into,
replace, update, or synchronize with existing collections. Document-local IDs
are used only while parsing and MUST NOT match existing local data. Importing
the same document again creates another set of new collections. Names are display
data, not identities; equal names do not change this requirement.

Implementations MUST enforce and explicitly report their limits on document
size, record size, nesting depth, record count, and text size. They MUST NOT rely
on unbounded growth, truncate content, or guess new boundaries after a malformed
block. Unknown optional blocks count toward input limits.

Errors SHOULD identify the line, affected record or scope, and violated rule.
Writers SHOULD use compact one-line JSON, readable IDs, and depth-first entry
order. They MUST escape JSON strings correctly and preserve literal text exactly
under the encoding rules. Export of text containing carriage returns requires an
explicit normalization policy; writers MUST NOT silently claim byte-exact
preservation after normalization.

Documents carry organization, references, and authored data. They MUST NOT cause
execution of Julia, shell commands, or other embedded code when read.

## 7. Complete Example

The UUIDs below are illustrative references, not claims about installed
animations.

```text
{"format":"euclid-collections","framing_version":1,"schema_version":1,"requires":[],"created-on":"2026-11-01T18:00:00Z"}
{"type":"collection","id":"constructions","name":"Constructions","begin":true}
{"type":"entry","id":"first","animation_id":"550e8400-e29b-41d4-a716-446655440000"}
{"type":"entry","id":"second","name":"Compare these constructions","animation_id":"550e8400-e29b-41d4-a716-446655440001","begin":true}
{"type":"notes","mime":"text/latex","notes_on_top":false,"block_end":"::end-second-notes::"}
Start with the segment \(AB\).

Compare \(AB = AC = BC\) with the following example.
::end-second-notes::
{"type":"entry","id":"comparison","animation_id":"550e8400-e29b-41d4-a716-446655440002"}
{"end":"second"}
{"end":"constructions"}
```

The `comparison` entry is a child of `second`. A document containing nested
entries declares the capability explicitly:

```text
{"format":"euclid-collections","framing_version":1,"schema_version":1,"requires":["entry_hierarchy"]}
{"type":"collection","id":"study","name":"Study","begin":true}
{"type":"entry","id":"parent","animation_id":"550e8400-e29b-41d4-a716-446655440003","begin":true}
{"type":"entry","id":"child","animation_id":"550e8400-e29b-41d4-a716-446655440004"}
{"end":"parent"}
{"end":"study"}
```

## 8. Conformance Cases

Conforming readers and writers should be tested against at least these cases:

- Flat entries, empty collections, nested entries, and multiple collections.
- Entries without an animation reference, collections with one, and nested
  collections.
- Repeated animation references within one collection's entry tree, at the same
  or different depths.
- Repeated import of one document and import of a collection whose name matches
  an existing collection; both produce separate new collections without merge.
- Entries referencing unavailable animations omitted while other entries remain
  eligible for import, with an accurate omission report.
- Children of omitted entries promoted in place and in order through multiple
  omitted ancestors, including promotion to the collection root.
- Duplicate document-local IDs and mismatched or missing scope endings.
- Literal JSON and apparent structural endings inside notes.
- Empty text, no trailing LF, multiple trailing LFs, and Unicode payloads.
- Collision-free delimiter generation and exact whitespace-sensitive matching.
- Missing block terminators and missing final document LF.
- Byte-counted blocks with zero length; payloads containing LF, CR, NUL,
  JSON-looking lines, and apparent terminators; and counts one byte too short or
  too long, each failing at the descriptor line through the framing-LF check.
- Descriptors carrying both block members; negative, fractional, exponent-form,
  oversized, and overflowing byte counts; and end-of-file inside a counted
  payload.
- The same document encoded with either block form parses to identical content.
- Unknown optional byte-counted blocks skipped by length.
- Every Record Syntax case fed one byte at a time, with results equal to feeding
  the complete document at once.
- CRLF, BOM, multiline JSON, duplicate JSON keys, and invalid reserved-member
  types.
- Unknown optional records, blocks, and nested scopes without child promotion.
- Unknown required content, unknown `requires` names, unsupported framing
  versions, and all `failure_scope` values.
- `preserve` values `always`, `unmodified`, and `never`, including explicit
  reporting when required preservation cannot be maintained.
- Newer compatible schemas, newer incompatible schemas, and older-schema
  migrations.
- Limit enforcement, unavailable references, unsupported required content, and
  no partial commit after a late validation error.
- Explicit disclosure of omissions before a lossy import or subsequent export.
