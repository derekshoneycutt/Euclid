# Tool Rendering

## Material Target

The pen and compass are polished but used bare titanium alloy, tinted by the
established tool color. Their highlights communicate strength and polish without
hiding geometric color or creating a separate glowing rim.

## Ownership

- `src/view/elements.odin` owns shared tool geometry, draw order, light conversion,
  and bounded occluder selection.
- `src/view/elements_encoded_tools.odin` emits ordered frame-local tool records.
- `src/view/native/sdl_stroke_pipeline.odin` owns SDL_GPU pipeline admission, packed
  uniform upload, draw recording, and resource release.
- `src/view/shaders/stroke3d.vert.hlsl` forwards batched vertex color data.
- `src/view/shaders/stroke3d.frag.hlsl` owns coverage, reconstructed normals, shadows,
  linear-light shading, and the titanium response.

Scene geometry remains frame-local. The render state does not retain tool
occluders or allocate per frame.

## Geometry Contract

Straight pen and compass rods use conservative screen-space capsule coverage.
The fragment shader clips that coverage analytically, reconstructing cylindrical
body normals and hemispherical endpoint normals.

The compass hinge uses one continuous 48-segment triangle strip. Vertex color
encodes the interpolated view-space tangent and signed side coordinate. The
texture-coordinate channel carries centerline view depth and normalized arc
position. A uniform carries the actual source color. The fragment shader
reconstructs a tube frame orthogonal to the tangent, which keeps lighting
directional around the loop.

The arc receives both compass legs in fixed slots. Leg 1 owns the arc start and
leg 2 owns the arc end. Each leg supplies projected capsule endpoints, endpoint
view depths, radius, and a view-space tangent. Canonical view depth increases
toward the camera.

Away from the owned endpoints, projected arc/leg crossings compare interpolated
surface depths. The arc remains opaque when it is in front, reveals the already
drawn leg when it is behind, and uses a brush-scaled transition near equal depth.
Near an owned endpoint, a brush-scaled attachment mask overrides clipping and
blends the two tube normals into a welded union without false seam darkening.

Semantic active-end circles remain a separate unshaded layer. They are not
physical caps.

If the stroke pipeline is unavailable, the encoder emits equivalent bounded 2D
geometry through the native draw pipeline. The fallback remains draw-order based and
does not provide depth-aware crossings or welded attachment shading.

## Shader Resource Contract

Canonical shader source is HLSL. `tools/shaders.jl` compiles both stages to SPIR-V
offline with SDL_shadercross, validates the binaries with SPIR-V Tools, reflects their
interfaces, and rejects descriptor-set, resource-count, vertex-layout, uniform-layout,
or cross-stage mismatches. Only generated SPIR-V, reflection JSON, and their hashed ABI
manifest enter `assets.pkg`; source HLSL and shader compilers are not runtime assets.
SDL_shadercross is a recursive submodule at `tools/shadercross`; the asset build
configures it under `.build/shadercross` and builds only the CLI target with one job.
An explicit `EUCLID_SHADERCROSS` path overrides the bundled provider for development.

The display-thread SDL runtime admits the stroke pipeline and fixed buffers as one
transaction. Every failed admission leaves the pipeline unpublished and releases any
loaded handle. Shutdown releases by handle rather than publication state, so partial
state is safe and cleanup is idempotent. Workers never load, use, or release GPU
resources.

The fallback is an intentional availability policy, not partial shader operation. A
failed pipeline admission disables the entire lit path for that session while
preserving ordered native geometry.

## Lighting Contract

World light is transformed into the orthonormal isometric view basis before
upload. All diffuse, shadow, and material arithmetic occurs in linear light:

1. Decode the source color from sRGB.
2. Apply diffuse form, tube shaping, and bounded contextual darkening.
3. Add the two-lobe titanium reflection with Schlick Fresnel.
4. Clamp once and encode to sRGB for output.

The application uses one material definition:

- roughness: `0.34`;
- normal-incidence Fresnel: `0.48`;
- source-color specular tint: `0.45`;
- maximum contextual darkening: `0.30`.

The narrow lobe represents polish. The weaker broad lobe represents ordinary
surface wear. Both lobes use derivative stabilization.

## Shadow Contract

Compass self-shadow and pen/compass interaction use at most two projected capsule
occluders. Cache draw order determines caster and receiver. Expanded screen-space
bounds reject distant pairs before uniform upload. Shadow and contact terms are
composed additively and capped by the material shadow limit.

This is an intentional screen-space approximation. It supports the reconstructed
stroke surface without claiming full world-space ray accuracy.

## Verification

`src/view/elements_test.odin` covers expanded bounds, fixed context capacity,
cache-order depth gating, world-to-view basis projection, canonical view-depth
ordering, arc parameter endpoints, attachment scaling, and stable leg slots.
`src/view/native/draw_encoder_test.odin` covers ordered custom commands and fixed
stroke ABI behavior.
`tools/test/shader_tests.jl` covers the offline shader commands, reflected interfaces,
fixed CPU/GPU ABI, missing-tool behavior, and artifact provenance. The complete
repository gate is the CMake `check` target.

## Decision Record

- Rounded capsule endpoints: accepted.
- Derivative edge and specular stabilization: accepted.
- Compass self-shadow and pen/compass interaction shadows: accepted.
- Continuous 48-segment hinge strip: accepted after restoring view-space tangent
  normals and two-sided strip submission.
- Depth-aware incidental arc/leg crossings and welded endpoint unions: accepted.
- Exact linear-light shading: accepted; the temporary encoded-space branch was
  removed.
- Material: polished, used bare titanium alloy matching the tool color.
- Deferred: active marker integration and a world-space analytic shadow model.
