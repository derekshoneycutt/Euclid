# Apple Silicon Shadercross Build Tools

This arm64 payload is build-only. Euclid packages generated shaders, never these
tools, into application assets. Intel and universal macOS are unsupported.
Application builds validate this inventory and do not compile or initialize any
shadercross source checkout.

## Source and compatibility

- SDL_shadercross upstream:
  <https://github.com/libsdl-org/SDL_shadercross/commit/1ff05bec573988a98ef9e0260b4da44f512b8367>.
  All three platform providers share this commit, recorded independently of Git
  in [source-pin.toml](../../source-pin.toml).
- arm64 only, deployment target macOS 11.0. The payload was built with Apple
  Clang and the Xcode SDK versions recorded in [manifest.toml](manifest.toml).
  Execution is verified on the production host, not on every historical macOS.
- `shadercross` statically links SDL3 3.4.16, SDL_shadercross, and SPIRV-Cross.
  Its build-only SDL configuration disables graphics/audio backends and does not
  change the application's SDL dependency.
- `libdxcompiler.dylib` and `libdxil.dylib` are bundled. Library references use
  `@loader_path`, with no Homebrew or build-directory runtime dependency.
  Remaining dependencies are Apple's system libraries/frameworks.
- `spirv-val` and `spirv-dis` use the same pinned SPIRV-Tools sources as Windows
  and Linux.
- All Mach-O binaries have ad-hoc code signatures, not Developer ID signatures
  or notarization. License files, component/source dependency pins, sizes, and
  SHA-256 hashes are recorded in the manifest and checked before use.
- `EUCLID_SHADERCROSS` remains an explicit development compiler override.
  Validator/disassembler overrides remain available through the shader builder API.

## Maintenance production

Use the `shadercross-macos-provider` CMake target from a configured preset on an
Apple Silicon Mac. It requires Xcode command-line tools, CMake, Ninja, Julia, Git,
curl, tar, and Python 3 for upstream code generation. It installs no host packages.

The [build recipe](../../../../tools/shadercross_macos_provider.sh) obtains a
checksum-verified SDL3 release archive, builds the tool closure, normalizes library
references, strips local symbols, and ad-hoc signs the tools.
[Packaging](../../../../tools/shadercross_macos_package.jl) publishes this inventory,
licenses, and provenance. Work files stay under `.build/shadercross-macos-provider`.

The [source resolver](../../../../tools/shadercross_provider_source.sh) creates a
maintenance-only recursive clone under `.build/shadercross-source`, or accepts an
existing checkout via `EUCLID_SHADERCROSS_SOURCE`. It verifies all eight source
commits and rejects tracked changes. This is never called by application builds.
When updating the upstream pin, update the resolver and all platform payloads,
manifests, and source note together. SDK/toolchain changes may change output bytes;
byte-for-byte rebuilds are not guaranteed.

Before accepting new binaries, run Julia unit tests and asset generation, then
compile all eight production shaders from a relocated payload without DYLD
overrides. Validate SPIR-V and ABI/reflection contracts, MSL reproducibility,
architecture, deployment targets, signatures, and the system-only dependency
closure. Compare generated SPIR-V, MSL, and reflection with the previous provider.
