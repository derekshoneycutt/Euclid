# Font Rasterization Contract

## Ownership

HarfBuzz owns shaping and OpenType MATH values. Euclid preserves those canonical
glyph IDs, advances, offsets, line geometry, and construction measurements. The
font preparation worker uses FreeType only to produce grayscale coverage and
bitmap bearings. The display thread remains the owner of atlas publication and
GPU textures.

## Linux and macOS Policy

The production Linux and macOS raster policy is FreeType light hinting with
`FT_LOAD_TARGET_LIGHT | FT_LOAD_NO_BITMAP` and `FT_RENDER_MODE_NORMAL`. Required
seed rasters and demand-paged rasters use the same policy. Policy is part of
`Font_Raster_Identity`; stale or mismatched requests cannot publish into the
active cache. The native adapter intentionally exposes no unhinted or font-native
hinting mode.

FreeType uses the directly declared `FreeType2_jll` 2.14.3+1 dependency and its
matching artifact headers on Linux and macOS. The repository-owned C adapter hides
FreeType layouts and uses operation-local allocation callbacks. The source bytes
outlive the face, and borrowed glyph-slot pixels are copied before another load or
close.

## Bounded Native Memory

One face is limited to 16 MiB of FreeType allocations, including per-allocation
callback bookkeeping. The wrapper and caller-owned font bytes are outside that
limit. A full glyph walk at 32 px and at the maximum 256 px raster size measured
peaks of 1,388,716 bytes for JuliaMono and 1,358,207 bytes for NewCM. The cap
therefore leaves more than eleven times the measured peak for variation in
FreeType state and face contents. A limit failure rejects preparation; it never
publishes a blank resident glyph.

The memory regression test reopens each bundled face independently, walks every
glyph at both sizes, and asserts the native peak remains under the cap. Prepared
atlas pixels and logical RGBA reservations are separate Euclid-owned budgets and
are not included in these native figures.

## Platform Status

The adapter, pinned runtime linkage, memory tests, and runtime SBOM provenance are
implemented and verified on Linux x86_64 and Apple Silicon macOS. macOS builds
link the pinned JLL dylib and embed its runtime directories as Mach-O rpaths,
including when system HarfBuzz is selected. The application bundle and native
test executables use the same adapter and raster policy; no Homebrew FreeType
installation is required. Source-built bundles depend on the local Julia
artifacts, rather than embedding a relocatable FreeType runtime.

Windows remains unsupported by the FreeType adapter. Intel and universal macOS
builds are not supported by the application toolchain.