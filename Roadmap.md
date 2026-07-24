# Roadmap

This is a basic idea, and a work in progress. This will increasingly have ideas I have in
mind and some concept of when I want to look at doing them. Some things need to be put off
for later and not done immediately, but to really do what I want to do with this project,
there are some things that do need to start early.

## v1

Core Content:

- [ ] Euclid Elements, Book 1 "the intro core, pythagorus"
  - [X] Definitions
  - [X] Postulates
  - [X] Common Notions
  - [ ] Propositions
    - [X] 1
    - [ ] 2-10
    - [ ] 11-20
    - [ ] 21-30
    - [ ] 31-40
    - [ ] 41-48
- [ ] Commentaries and Alternatives
  - [ ] Proclus commentaries
    - [X] Isosceles Triangle
    - [X] Scalene Triangle
    - [ ] Prop 2: C is on AB
    - [ ] Prop 2: Figure 1 (point A, line BC rising above; equilateral ABD drawn below BC, circle drawn on BC, BC=AB=AD=BD, finished)
    - [ ] Prop 2: Figure 2 (Same start fig1 but AB < BC)
    - [ ] Prop 2: Figure 3 (Same start fig1 but AB > BC)
    - [ ] More? (TBD)
  - [ ] Pythagorean Alternatives
    - [ ] Schopenhauer's (basically a single square and 2 rotated squares based on the internal crosses in the square: <|X|>)
    - [ ] Bhaskara II's proof
    - [ ] Xuan Tu
    - [ ] Others? -- TBD --
- [X] Hilbert, Chapter 1
  - [X] Section 1
  - [X] Section 2
  - [X] Section 3
  - [X] Section 4
  - [X] Section 5
  - [X] Section 6
  - [X] Section 7
  - [X] Section 8
- [ ] Algebraic groups
  - [ ] Definitions
    - [ ] $\Z_2$ (irregular polygon reflecting about a line; special case of $C_n$)
    - [ ] $C_n$ (cyclic group of order $n$; writing a circle in unit dividing $2\pi$)
      - [ ] Closure
      - [ ] Associativity
      - [ ] Identity
      - [ ] Inverse
      - [ ] Commutative/Abelian
    - [ ] $D_n$ (dihedrals, symmetry of shape with $n$ sides ; non-commutative)
    - [ ] $(\R^2, +)$ (translation group -- moving shapes)
    - [ ] $SO(2)$ Group (special orthogonal group of 2D rotations -- polygon rotating around another point)
    - [ ] $SE(2)$ Group (translation + rotations; orientation-preserving rigid motion; can match same-handedness but not reflected)
    - [ ] $O(2)$ Group (orthogonal group including reflection and infinite rotation fixed about center of polygon)
    - [ ] $E(2)$ Group (euclidean symmetry group of 2D plane -- polygons translating/rotating/reflecting around another point)
  - [ ] Demonstrations
    - [ ] 1-10
    - [ ] 11-20
    - [ ] 21-30
    - [ ] 31-40
    - [ ] 41-48

General features:

- [X] Windows, MacOS, Linux support
- [X] Julia make script with static analysis report and testing options
- [X] Primitives
  - [X] Point
  - [X] Line
  - [X] Circle
  - [X] Filled Circle
  - [X] Polygons (Triangle, Square, Pentagon)
  - [X] Label
  - [X] Pen
  - [X] Compass
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
- [X] Improved hybrid immediate mode, block-based view text rendering
- [X] View text more advanced layout engine
- [ ] Continued view text support for colors, shape fill, etc.
- [ ] Basic LaTeX type rendering support
  - [ ] LaTeX to unicode base
  - [ ] Superscript
  - [ ] Subscript
  - [ ] Fractions
  - [ ] Dynamic sized brackets
  - [ ] Matrices
  - [ ] Sums, Products, Integrals
- [ ] Improved UI layout system
- [ ] Standard group-focused transformation animations for complex shapes
  - [ ] Translation
  - [ ] Rotation
  - [ ] Reflection
- [ ] Scratchpad REPL
  - [X] Basic setup and availability
  - [X] Basic help feature
  - [X] Initial primitive drawing animation hooks
  - [ ] Basic group transformation animation hooks
  - [ ] Basic clipboard support
  - [ ] LaTeX to unicode input tab completion support
- [ ] Drawing Sounds
- [ ] Alternative tree for pedagological view vs book view -- Nice to have --

Final tasks:

- [ ] Complete unit tests
- [ ] Animation editing (2-3 weeks)
- [ ] Final cleanup/tightening
- [ ] Package construction
  - [ ] Linux
  - [ ] Windows
  - [ ] MacOS
- [ ] CI Builds

## v2

After v1 is complete, the following is suggestions to evaluate next.

- Euclid Elements, Book 2 "the algebra book"
  - Definitions
  - Propositions
    - 1-5
    - 6-10
    - 11-14
- Group theory
  - Klein 4 Group
  - Frieze groups
  - $Sim(2)$ (same as $E(2)$ but with scaling as well)
  - $Aff(2)$ ($Sim(2)$ with shearing added)
  - Circle group $S^1$ (point of a circle rotating around said circle)
  - $\R/\Z$ (coil going up, animating on each full circle)
  - Free group $F_2$ from figure-8 (walking a cayley tree)
  - $(\pi_1(R_n)\cong F_n)$ Free group $F_n$ via the rose $R_n$ (draw roses of size $n_a$; where for $m$ passes $n_a$ varies constantly +1 for each $a\in \{1, ..., m\}$, line disintegrating as drawing with new effect)
  - Theorems
- Category theory?
- Tarski's Axioms?
- Birkhoff's Axioms?
- More primitives (gnomons, strings--small connectors, arrows)
- Limited lifetime line/arc segments--disintegrate after drawing
- Improved Scratchpad console-like REPL
- More Scratchpad tab completions
- Improved Scratchpad highlight and clipboard support
- Highlight drawn shape from clicking label in view text area
- Additional REPL drawing methods
- REPL-focused exercise suggestions
- Persisting Scratchpads (runtime-only, as children in the trees of Scratchpad that can be navigated away from and returned to with persisted internal state; exit cleans REPL state and removes from tree)
- Declarative animations support
- Animation slider
- Transformations
  - Scaling
  - Shearing
- Window sizing and portrait mode

## Brainstorming

### v3

- Euclid Elements, Book 3 "about circles"
  - Definitions
  - Propositions (37)
- More group theory
  - $U(1)$ (show points on a polygon all at different distance from center, spinning individually around individual circles, one at a time, dynamically)
  - $\Complex^x$ (literally drawing a spiral)
  - $\Z^2$ (pen dragging, drawing out a grid of points regularly spaced)
  - $T$ (pac-man wrap around the surface, drawing line at an irrational angle like sqrt(2) and will cover it all)
  - Wallpaper groups (repeating drawings)
  - $PSL(2, R)$ (Polygon can be transformed by never crosses below a boundary)
  - $PGL(2, C)$ (animated advanced transformation; changes center and radius because transformation preserves circles)
  - Theorems
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

Schopenhauer uses a diagram like this, very roughly. It includes a square with the diagonals
crossing. The top triangle made by this diagonal is shaded. On either side right/left,
additional triangles the same size as the inner ones extend outward, creating diagonal squares
with the triangles mirrored inside the initial square.

```text
  /\----/\
 / |\##/| \
/  | \/ |  \
\  | /\ |  /
 \ |/  \| /
  \/____\/
```
