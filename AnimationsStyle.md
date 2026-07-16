# Animations Style

This document captures the shared style conventions for Julia animations in
`src/julia/`, especially the Hilbert and Euclid content that uses the pen,
point, line, and plane primitives.

This is kind of a preliminary approach to the style language for the animations. As further
points arise with further animation work, this is expected to mature.

## Core Goals

- Keep motion readable.
- Make geometric relationships obvious.
- Use color to separate roles, not to decorate randomly.
- Prefer a small number of clear phases over busy simultaneous motion.

## Inspiration

Oliver Byrne's translation of Euclid's first 6 books is a good source of inspiration for
how to present geometry with clear color and layout choices, but he is only a reference
point. He is not a definitive style authority for this project; we are not trying to reproduce
his work, and in fact are using the Heath translation in text.

## Standard Palette

Use these colors as the main animation palette unless a script has a specific,
documented reason to deviate:

- `steelblue`
- `palevioletred1`
- `khaki3`
- `grey60`
- `plum1`: the standard color for point labels.

These four colors are the shared working palette. They are reused across lines,
circles, planes, and points based on the number of objects on screen and how
those objects interact.

`plum1` stays the default for labels.

## Color Relationships

- Shapes that appear at the same time and have a direct geometric relationship
  SHOULD not share the same color.
- Intersecting or paired shapes SHOULD use different colors when the distinction
  helps the reader understand the construction.
- Choose among the four colors to balance the whole scene, not to lock a color
  to a fixed object type.
- Use `khaki3` and `grey60` the same way you use `steelblue` and
  `palevioletred1`: as part of the shared palette, assigned by relationship and
  composition.
- For order/between demonstrations that use drag passes, the drag color SHOULD
  match the center or emphasized point of that statement. Do not use an
  unrelated shared highlight color when a specific point is the focus.

## Motion Conventions

- Start with pen descent when the animation is about drawing.
- Use `animate_pen_arcmove` for travel between distinct construction points.
- Use `animate_draw_point` when the point itself is being established.
- Use `animate_draw_line` when the line itself is being established.
- Use `animate_pen_tilt_and_drag` for surface or plane highlighting passes.
- End with pen rise and a short hold when the finished figure should remain on
  screen for a moment.
- Pen rise SHOULD begin from the final meaningful draw endpoint (or final
  emphasized point), not from an earlier anchor point.

## Plane and Surface Treatment

- The app already provides a persistent drawing surface; do not simulate a full
  plane by drawing a large fake fill stroke unless the plane stroke itself is
  the geometric point being demonstrated.
- If a plane is conceptually important, label it (`α`, `β`, etc.) early and
  keep the label clearly away from the active construction cluster.
- Surface/plane drag strokes should be reserved for intentional emphasis passes,
  not as a default substitute for the existing surface.
- For square or plane primitives, use the vertex order documented in
  [ArchitectureSummary.md](ArchitectureSummary.md) so the face actually renders.

## Point Labels

- Use `plum1` for point labels by default.
- Keep labels offset enough that a visible gap remains between the label glyphs
  and the point marker; “barely offset” is a failure, not a preference.
- Keep labels clearly separated from both the point marker and nearby lines;
  avoid placements that visually sit on top of points or strokes.
- When placing a label, check the actual rendered composition, not just the raw
  coordinate offset. A small diagonal offset can still overlap once projected
  and rasterized.
- If a label is even partially touching the point marker in the rendered frame,
  move it farther. Do not accept point-label contact as good enough.
- The current renderer draws labels from the glyph origin at the supplied point;
  it does not center the glyph on that anchor. Treat this as a hard renderer
  fact and compensate with larger offsets than intuition suggests, especially
  for labels placed above a point.
- Labels should appear only after the related point has been established, unless
  the animation intentionally needs earlier annotation.
- For primed names in text/output, prefer ASCII apostrophe (`A'`) unless a
  specific UI path is confirmed to support Unicode prime consistently.
- Decorated labels (prime/hat/bar) should read as one symbol with the base
  letter: the decoration must be visually attached to the letter, not floating
  as an independent mark.

## Reset Behavior

- Reset phases should restore hidden or partially built geometry to a known
  start state.
- Keep the final composition visible briefly before resetting when the ending
  is meant to be read by the viewer.
- Avoid abrupt resets immediately after the last visible motion.

## Practical Review Check

Before adding a new animation, ask:

1. What is the main geometric idea?
1. Which object should visually dominate?
1. Are any same-time shapes accidentally sharing a color?
1. Does the motion sequence read as construction instead of teleportation?
