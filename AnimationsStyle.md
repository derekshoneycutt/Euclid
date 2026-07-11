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

## Motion Conventions

- Start with pen descent when the animation is about drawing.
- Use `animate_pen_arcmove` for travel between distinct construction points.
- Use `animate_draw_point` when the point itself is being established.
- Use `animate_draw_line` when the line itself is being established.
- Use `animate_pen_tilt_and_drag` for surface or plane highlighting passes.
- End with pen rise and a short hold when the finished figure should remain on
  screen for a moment.

## Plane and Surface Treatment

- Surfaces should usually fade or reveal into the scene rather than appear fully
  visible from the start.
- If a plane is part of the point of the animation, reveal it after the key
  point or intersection is established unless the script explicitly needs a
  different order.
- For square or plane primitives, use the vertex order documented in
  [ArchitectureSummary.md](ArchitectureSummary.md) so the face actually renders.

## Point Labels

- Use `plum1` for point labels by default.
- Keep labels slightly offset from the point they name.
- Labels should appear only after the related point has been established, unless
  the animation intentionally needs earlier annotation.

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
