# Wiki Composition

## Purpose

Euclid assembles one Wiki from independently owned sections. The manifest
declares ownership and navigation; producers render managed pages; the
compositor validates the combined output before any managed file is written.

Canonical authored Guides live under `docs/wiki/Guides/`. Generated pages are
CI artifacts rather than tracked repository files. Local and CI generation
assembles the complete publishable Wiki in ignored `bin/wiki/`; GitHub Actions
uploads that structured directory for review and publishes it to the GitHub Wiki
from protected `main` builds.

## Ownership Model

`tools/code_wiki.toml` assigns every generated path to exactly one owner:

- `code_wiki` owns `Code/`;
- `wiki_compositor` owns shared `Home.md`, `_Sidebar.md`, the reserved Content
  landing page, and the generated Guide index;
- `guide_authors` owns canonical authored Guide files, which are not compositor outputs.

Managed path claims may be a single Markdown file or a directory namespace.
Claims must not overlap.
A producer cannot emit an unowned path or a path owned by another producer.

Generated repository paths are ignored selectively. The ignore rules do not
cover authored Guide sources, the manifest, generator implementation, tests,
or workflow configuration.

## Producer Contract

A Wiki producer must:

1. Read only its declared canonical sources.
1. Return deterministic `WikiOutput` records containing `owner`,
   repository-relative Wiki `path`, and complete Markdown `content`.
1. Avoid writing directly beneath `docs/wiki/`.
1. Keep every output inside the owner's `managed_output_paths` claim.
1. Add its records to the complete generation batch before `write_wiki_outputs` is called.

`write_wiki_outputs` validates safe paths, unique paths, and exact manifest
ownership for the entire batch before its first filesystem write.
`validate_managed_outputs` then rejects missing or stale pages inside each
declared stale boundary.

`make wiki` replaces `bin/wiki/` with a validated artifact whose repository
source links are pinned to the generating commit. `make check-wiki` generates
into a temporary directory and compares every path and byte with `bin/wiki/`
without modifying the retained artifact.

Shared navigation is composed from all manifest sections regardless of which
producer owns their content. A new section therefore participates in Home and
sidebar navigation through manifest metadata rather than Code extractor changes.

## Content Catalogue Extension

A future Content catalogue producer should statically extract a small
normalized record for each entry. Useful fields include:

- module name and source path;
- stable animation key or UUID expression when statically available;
- registered display name and parent/category relationship;
- lifecycle functions present;
- links to animation source and related authored content.

The producer must not execute animation modules during extraction. Behavioral
execution remains the responsibility of the animation test harness.

To activate the producer:

1. Change the Content section owner and source policy in `tools/code_wiki.toml`.
1. Expand its managed path and stale boundary from the placeholder landing page
  to `Content/`.
1. Append the producer's `WikiOutput` records to the generation batch.
1. Add focused extraction, ownership, link, stale-page, and determinism tests.

The Code extractor and its package, symbol, and bridge models remain unchanged.
The only shared contract is the owned `WikiOutput` batch consumed by the
compositor.

## Authored Guides

The compositor generates only `Guides/Home.md`. Files such as this Guide are
authored directly under `docs/wiki/Guides/` and must never be rewritten,
deleted, or treated as generated Code output. The artifact builder copies each
manifest-declared Guide unchanged into `bin/wiki/Guides/`.

## CI Publication

The Wiki workflow generates and checks `bin/wiki/` for pull requests and
relevant pushes, then uploads it as a review artifact. Publication runs only
for `main` pushes after artifact validation.

The publisher checks out the separate GitHub Wiki Git repository and
synchronizes only manifest claims. GitHub Wiki pages use a flat namespace, so
structured artifact paths are published as unique names such as
`Code-Bridge.md`, and local Markdown links are rewritten to rendered Wiki
routes. Directory claims such as `Code/` replace their corresponding flat
namespace so stale generated pages disappear. Exact-file claims and unrelated
Wiki paths are preserved. The job commits only when the Wiki checkout changes.

The workflow uses the repository `GITHUB_TOKEN` with job-scoped `contents:
write` permission. If repository policy does not permit Wiki Git pushes with
that token, replace the checkout credential with a narrowly scoped fine-grained
token or GitHub App token that can write this repository's Wiki.

Before the first automated publication, enable the repository Wiki and create
its initial Home page once through GitHub so the separate `<repository>.wiki.git`
repository exists for checkout.
