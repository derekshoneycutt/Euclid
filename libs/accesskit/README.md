# AccessKit C Provider

This directory pins the repository-owned AccessKit C 0.23.1 desktop provider.
Euclid does not fall back to a system AccessKit installation.

Retained release payloads:

- Linux x86_64 GNU shared library
- macOS arm64 and x86_64 shared libraries
- Windows x86_64 MSVC DLL and import library

Each target directory owns a schema-versioned `manifest.toml` containing the
release identity, tagged header hash, selected MIT license hash, required notices,
crate versions, native dependency closure, artifact roles, and artifact hashes.
`tools/build_config.jl` validates the active manifest before returning linker or
runtime paths.

The original release bundle is not checked in. It is identified by SHA-256
`35b7ca8a6f1e038b5da35e1e9e5a0adaed9bfcf21e1496d29598fbbadcc7043f` and is
available from the upstream 0.23.1 release page.

Run the host C/Odin ABI and ownership probe with:

```sh
julia tools/make.jl accesskit-abi
```

The probe compiles the tagged header, checks enum values and target-sensitive
layouts, links the retained payload, and creates, queries, and frees one node.
Run it natively on every retained target before enabling that platform adapter.

To update the provider:

1. download the new upstream release into `.build/accesskit-audit/`;
2. verify its published bundle hash before extraction;
3. inspect target formats, exports, and native dependency closure;
4. replace the tagged header, notices, and retained target payloads;
5. update every manifest and the narrow Odin declarations together;
6. run `julia tools/make.jl accesskit-abi` on Linux, macOS, and Windows;
7. run the complete repository gate on each supported build platform.