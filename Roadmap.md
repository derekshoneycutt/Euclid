# Roadmap

This is a basic idea, and a work in progress. This will increasingly have ideas I have in
mind and some concept of when I want to look at doing them. Some things need to be put off
for later and not done immediately, but to really do what I want to do with this project,
there are some things that do need to start early.

## v1

Core Content (>163 animations; 98 complete):

- [ ] Euclid Elements, Book 1 "the intro core, pythagorus" (85 animations; 38 complete)
  - [X] Definitions (31 animations)
  - [X] Postulates (5 animations)
  - [X] Common Notions (1 animation)
  - [ ] Propositions (48 animations)
    - [X] 1
    - [ ] 2-10
    - [ ] 11-20
    - [ ] 21-30
    - [ ] 31-40
    - [ ] 41-48
- [ ] Commentaries and Alternatives (>10 animations; 2 complete)
  - [ ] Proclus commentaries (>6 animations)
    - [X] Isosceles Triangle
    - [X] Scalene Triangle
    - [ ] Prop 2: C is on AB
    - [ ] Prop 2: Figure 1 (point A, line BC rising above;
     equilateral ABD drawn below BC, circle drawn on BC, BC=AB=AD=BD, finished)
    - [ ] Prop 2: Figure 2 (Same start fig1 but AB < BC)
    - [ ] Prop 2: Figure 3 (Same start fig1 but AB > BC)
    - [ ] Prop 3: (7 figures, animations tbd)
    - [ ] Prop 4: (1 figure, animations tbd)
    - [ ] Prop 5: (2 figures, animations tbd)
    - [ ] Prop 6: (2 figures, animations tbd)
    - [ ] Prop 7: (2 figures, animations tbd)
    - [ ] Prop 8: (3 figures, animations tbd)
    - [ ] Prop 9: (5 figures, animations tbd)
    - [ ] Prop 10: (1 figures, animations tbd)
    - [ ] Prop 11: (2 figures, animations tbd)
    - [ ] Prop 12: (? figures, animations tbd)
    - [ ] Prop 14: (2 figures, animations tbd)
    - [ ] Prop 15: (3 figures, animations tbd)
    - [ ] Prop 16: (2 figures, animations tbd)
    - [ ] More? (TBD)
  - [ ] Pythagorean Alternatives (3+ animations)
    - [ ] Schopenhauer's (basically a single square and
     2 rotated squares based on the internal crosses in the square: <|X|>)
    - [ ] Bhaskara II's proof
    - [ ] Xuan Tu
    - [ ] Others? -- TBD --
- [X] Hilbert, Chapter 1 (54 animations; all complete)
  - [X] Section 1 (null animations)
  - [X] Section 2 (9 animations)
  - [X] Section 3 (6 animations)
  - [X] Section 4 (10 animations)
  - [X] Section 5 (2 animations)
  - [X] Section 6 (8 animations)
  - [X] Section 7 (17 animations)
  - [X] Section 8 (2 animations)
- [ ] Algebraic groups (14+ animations; 7 complete)
  - [ ] Definitions (14 animations)
    - [X] $\mathbb{Z}_2$(irregular polygon reflecting about a line; special case of$C_n$)
      - [X] Closure
      - [X] Identity
      - [X] Inverse
    - [X] $C_n$(cyclic group of order$n$; writing a circle in unit dividing $2\pi$)
      - [X] Associativity
      - [X] Commutative (Abelian)
    - [ ] $D_n$(dihedral, symmetry of shape with$n$ sides)
      - [ ] Non-Abelian
    - [ ] $(\mathbb{R}^2, +)$ (translation group -- moving shapes)
    - [ ] $SO(2)$ Group (special orthogonal group of 2D rotations --
     polygon rotating around another point)
    - [ ] $SE(2)$ Group (translation + rotations;
     orientation-preserving rigid motion; can match same-handedness but not reflected)
    - [ ] $O(2)$ Group (orthogonal group including reflection and
     infinite rotation fixed about center of polygon)
    - [ ] $E(2)$ Group (euclidean symmetry group of 2D plane --
     polygons translating/rotating/reflecting around another point)
  - [ ] Demonstrations ? Idk maybe. keep going back and forth lololololol

General features:

- [X] Windows, MacOS, Linux support
- [X] Julia make script with static analysis report and testing options
- [X] Primitives
  - [X] Point
  - [X] Line
  - [X] Circle
  - [X] Filled Circle
  - [X] Polygons (Triangle, Square, Pentagon)
  - [ ] Cardioids & Limacons
  - [X] Label
  - [X] Pen
  - [X] Compass
  - [ ] Roulette tool
- [X] Basic, layered particle system
  - [X] Dust
  - [X] Embers
  - [X] Flickers
- [X] Comprehensive Odin-Julia Bridge interface between the two languages
- [X] Basic state-machine supported julia animations structure
- [X] Initial library of standard animations for drawing primitives
- [X] Restart and Pause functionality
- [X] GIF Saving
- [X] Initial Settings panel
- [X] Initial basic SIMD and performance tweaks
- [X] UUID animation handles
- [X] Improved UI layout system
- [X] Improved hybrid immediate mode, block-based view text rendering
- [X] Scratchpad REPL
  - [X] Basic setup and availability
  - [X] Basic help feature
  - [X] Basic input tab completion support, including unicode characters & function names
  - [X] Basic clipboard support
  - [X] Initial primitive drawing animation hooks
  - [X] LaTeX output
  - [X] Improved Scratchpad console-like REPL
- [X] Standard group-focused transformation animations for complex shapes
  - [X] Translation
  - [X] Rotation
  - [X] Reflection
  - [X] Basic group transformation animation hooks for REPL
- [X] View text more advanced layout engine
- [X] Continued view text support for colors, shape fill, etc.
- [X] Basic LaTeX type rendering support
  - [X] LaTeX to unicode base
  - [X] Superscript
  - [X] Subscript
  - [X] Fractions
  - [X] Dynamic sized brackets
  - [X] Matrices
  - [X] Sums, Products, Integrals
- [X] Naive spatial-aware shape drawing
- [X] Improved pen clipping through 3D polygons
- [X] Drawing Sounds (Initial procedural)

Final tasks:

- [X] Final optimizations
  - [X] Dedicated Julia thread for Julia module isolation
  - [X] Basic worker threadpool optimizations
  - [X] Julia sysimage compilation and support
  - [X] Shader-based particle drawing
- [X] Generated Code Wiki
- [ ] Semantic trace and deterministic animation test harness (default off)
  - [X] JSONL event tracing with runtime, animation, geometry, tool, and particle schemas
  - [X] Deterministic checkpoint snapshots and stable run/step identity
  - [X] Headless harness with stable-UUID scenario selection and Julia assertions
  - [ ] Running-app end-to-end harness
- [ ] Runtime hardening
  - [ ] Julia/Odin boundary ownership and lifecycle audit
  - [ ] Bridge ABI validation and malformed-input tests
  - [ ] Shutdown, reload, cancellation, and failure-path coverage
  - [ ] Performance budgets
- [ ] Release validation
  - [ ] Rendering and animation regression test suite
  - [ ] Complete standard integration and e2e test suite
  - [ ] User-facing error and recovery review
  - [ ] Dependency, license, and runtime-closure audit
- [ ] Surface cleanup
  - [ ] Freeze and document supported Julia APIs
  - [ ] Remove dead APIs, debug paths, compatibility code, and unused assets
- [ ] Final editing and review (2-3 weeks)
  - [ ] Animation and content editing
  - [ ] Principal code review against documented architecture and standards
  - [ ] Resolve review findings
- [ ] Package construction
  - [ ] Linux
  - [ ] Windows
  - [ ] MacOS
  - [ ] CI Builds

## v2

Content (24+ animations):

- Euclid Elements, Book 2 "the algebra book" (16 animations)
  - Definitions (2 animations)
  - Propositions (14 animations)
    - 1-5
    - 6-10
    - 11-14
- Group theory (8+ animations)
  - Klein 4 Group
  - Frieze groups
  - $Sim(2)$(same as$E(2)$ but with scaling as well)
  - $Aff(2)$ ($Sim(2)$ with shearing added)
  - Circle group $S^1$ (point of a circle rotating around said circle)
  - $\mathbb{R}/\mathbb{Z}$ (coil going up, animating on each full circle)
  - Free group $F_2$ from figure-8 (walking a cayley tree)
  - $(\pi_1(R_n)\cong F_n)$Free group$F_n$via the rose$R_n$(draw roses of size$n_a$;
   where for $m$passes$n_a$varies constantly +1 for each$a\in \{1, ..., m\}$,
   line disintegrating as drawing with new effect)
- Possibly Roulettes? (tusi couples, trochoids, cyclocloids,)
- Logic, Tarski, etc.?

Core Features:

- More primitives (gnomons, strings--small connectors, logic)
- Update clipping for better 3D feelings on things past pen w/ 1 plane
- Limited lifetime line/arc segments--disintegrate after drawing
- More LaTeX support
- Improved Scratchpad REPL tab completion (preview of options, etc.)
- Improved Scratchpad highlight and clipboard support
- Scratchpad animation recorder w/ playback (e.g. start_recording! ... end_recording!
 ... replay_recording!)
- Highlight drawn shape from clicking label in view text area
- Additional REPL drawing methods
- REPL-focused exercise suggestions
- Persisting Scratchpads (runtime-only, as children in the trees of Scratchpad
 that can be navigated away from and returned to with persisted internal state;
  exit cleans REPL state and removes from tree)
- Declarative animations support
- Animation slider
- Transformations
  - Scaling
  - Shearing
- Window sizing and portrait mode
- Revisit sounds? Maybe
- Alternative tree for connected view vs book view

## Brainstorming

### v3

- Euclid Elements, Book 3 "about circles"
  - Definitions
  - Propositions (37)
- More group theory
  - $U(1)$ (show points on a polygon all at different distance from center,
   spinning individually around individual circles, one at a time, dynamically)
  - $\mathbb{C}^{\times}$ (literally drawing a spiral)
  - $\mathbb{Z}^2$ (pen dragging, drawing out a grid of points regularly spaced)
  - $T$ (pac-man wrap around the surface, drawing line at an irrational
   angle like sqrt(2) and will cover it all)
  - Wallpaper groups (repeating drawings)
  - $PSL(2, R)$ (Polygon can be transformed by never crosses below a boundary)
  - $PGL(2, C)$ (animated advanced transformation; changes center and
   radius because transformation preserves circles)
- Complex numbers support handling
- More primitives (ellipses/conic sections, spirals)
- Scaled Cartesian coordinate system
- Interactive mode animations w/ per-animation settings

### v4

- Euclid Elements, Book 4 "regular polygons related to circles"
  - Definitions
  - Propositions (16)
- Intro rings
- Scaled polynomial section drawing

### v5

- Euclid Elements, Book 5 "proportion and magnitude"
  - Definitions
  - Propositions (25)
- Hilbert chap 3 (Theory of Proportion, Pascal's theorem)
- Fields

## References

Roulette can be a good basis for all cardioids, limacons, nephroids, ellipses, more

Mechanically, every standard roulette can be animated using three primary components:

1. A Base Circle ($C_{1}$): Center $(x_1, y_1)$, radius $R$, fixed in place.
1. A Rolling Circle ($C_{2}$): Center $(x_2, y_2)$, radius $r$, which rotates
 around the base circle.
1. A Tracing Arm ($d$): A physical extension from the center of $C_{2}$ holding
 the pen at distance $d$.

The Universal Formula

Let $\theta$ be the angle of the rolling circle's center relative to the base circle's
 center. The coordinates of the pen $(x, y)$ are given by:

$$\begin{aligned}x&=(R\pm r)\cos (\theta )+d\cos \left(\theta \pm
\frac{R}{r}\theta \right)\\
 y&=(R\pm r)\sin (\theta )+d\sin \left(\theta \pm \frac{R}{r}\theta \right)\end{aligned}$$

Use $+$ for Epitrochoids (Circle rolling on the outside of the base circle).

Use $-$ for Hypotrochoids (Circle rolling on the inside of the base circle).

By exposing just three variables ($R$, $r$, and $d$) we automatically get support
for curves:

Target | Curve | Direction | Base Radius ($R$) | Rolling Radius ($r$) | Pen Distance ($d$) | Visual Mechanical Behavior
--- | --- | --- | --- | --- | --- | ---
Cardioid | Outside | ($+$) | $R$ | $r = R$ | $d = r$ | Pen sits exactly on the rolling circle's rim.
Limaçon (Inner Loop) | Outside | ($+$) | $R$ | $r = R$ | $d > r$ | Pen extends past the rolling circle's rim.
Limaçon (Dimpled) | Outside | ($+$) | $R$ | $r = R$ | $d < r$ | Pen sits inside the rolling circle's rim.
Nephroid | Outside | ($+$) | $R$ | $r = \frac{1}{2}R$ | $d = r$ | Two inward kidney-like cusps.
Ellipse | Inside | ($-$) | $R$ | $r = \frac{1}{2}R$ | $d \neq r$ | Known as a Tusi Couple. A rolling circle half the size of the base circle collapses planetary motion into perfect lines/ellipses!

-----------

Schopenhauer uses a diagram like this, very roughly. It includes a square with the
diagonals crossing. The top triangle made by this diagonal is shaded. On either side
right/left, additional triangles the same size as the inner ones extend outward, creating
diagonal squares with the triangles mirrored inside the initial square.

```text
  /\----/\
 / |\##/| \
/  | \/ |  \
\  | /\ |  /
 \ |/  \| /
  \/____\/
```
