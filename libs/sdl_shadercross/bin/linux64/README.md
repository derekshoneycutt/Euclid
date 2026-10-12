# Linux Shadercross Build Tools

This pinned x86-64 payload is build-only. Euclid packages generated shaders, never
these tools, into application assets. Ordinary Linux builds use only this payload.

## Compatibility and ownership

- Ubuntu 22.04 baseline: glibc 2.35 or newer and libstdc++ providing
  GLIBCXX_3.4.29 or newer. Musl and other architectures are unsupported.
- `shadercross` statically links SDL3 3.4.16 and SPIRV-Cross. The CLI's SDL build
  disables graphics/audio backends; this does not change the application's SDL.
- `libdxcompiler.so` and `libdxil.so` are bundled. Every ELF uses `$ORIGIN` for
  local library lookup, independent of the working directory.
- `spirv-val` and `spirv-dis` use the same pinned SPIRV-Tools sources as Windows.
- System dependencies are the baseline C/C++ runtime, libgcc, and libm.
- [manifest.toml](manifest.toml) records source pins, licenses, artifact sizes and
  hashes, static components, rootfs identity, and build-package inventory.
  The build driver validates the complete tool/license inventory before use and
  reports missing or corrupt files rather than rebuilding or finding PATH tools.
- `EUCLID_SHADERCROSS` remains an explicit development compiler override.
  Validator/disassembler overrides remain available through the shader builder API.

## Maintenance production

This is an explicit maintenance task, not a prerequisite of application builds.
It needs an x86-64 Linux host with Bash, Git, curl, tar, sha256sum, bubblewrap, and
unprivileged user namespaces. It requires no Docker daemon or host package changes.

The default source input is a maintenance-only clone under
`.build/shadercross-source`, automatically initialized at the pinned upstream commit.
Alternatively, clone that commit and initialize its recursive dependencies in a
separate directory, then set `EUCLID_SHADERCROSS_SOURCE` to that checkout. The
recipe checks all eight source pins and refuses tracked modifications.

Run the `shadercross-linux-provider` CMake target from a configured preset.
It builds single-job inside a checksum-verified Ubuntu 22.04.5 rootfs under
`.build/shadercross-linux-provider`, then publishes binaries, licenses, hashes,
and package provenance here. The isolated rootfs installs build dependencies;
no packages are installed on the host.

The recipes are
[provider setup](../../../../tools/shadercross_linux_provider.sh),
[isolated build](../../../../tools/shadercross_linux_build/build.sh), and
[packaging](../../../../tools/shadercross_linux_package.jl).
Ubuntu package updates can change output bytes; source and base-image identities
are pinned, installed package versions are recorded, but byte-for-byte rebuilds
are not guaranteed.

After an update, run Julia unit tests and the complete CMake `check` gate.
Also compile all production shaders in the baseline rootfs from a relocated
payload, validate their SPIR-V and ABI/reflection contracts, and compare them
with ordinary host-generated shaders before accepting the refreshed binaries.
The shadercross submodule has been removed; all platforms use binary providers.
