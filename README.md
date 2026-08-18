# Euclid

This is a basic project to create an application that animates Euclid's Elements.

This is primarily a Julia-focused application, utilizing the interactive nature of the
langauge for animations and a REPL-like Scratchpad. Featuring the
[JuliaMono](https://juliamono.netlify.app/) font, available under the OFL/SIL license.

The code and documentation of this project is CC0 licensed.

The core application is coded in Odin, with Raylib used for rendering.

1. [Building from Source](#building-from-source)
1. [Documentation](#documentation)
1. [Questions?](#questions)
    1. [Q: Why?](#q-why)
    1. [Q: What's the utility?](#q-whats-the-utility)
    1. [Q: What about AI?](#q-what-about-ai)
    1. [Q: What is the "Scratchpad"?](#q-what-is-the-scratchpad)
    1. [Q: Wait, Save Gif?](#q-wait-save-gif)
    1. [Q: You support LaTeX?](#q-you-support-latex)
    1. [Q: Any performance hacks for users?](#q-any-performance-hacks-for-users)
    1. [Q: Why 2 languages?](#q-why-2-languages)
    1. [Q: Are there any more options with the make scripts?](#q-are-there-any-more-options-with-the-make-scripts)
    1. [Q: Where should I start if I want in the code?](#q-where-should-i-start-if-i-want-in-the-code)
    1. [Q: What's this about hot-reload?](#q-whats-this-about-hot-reload)
    1. [Q: What is all this output in the make vet output?](#q-what-is-all-this-output-in-the-make-vet-output)

<p align="center">
<img src="./screen.gif" >
</p>

## Building from Source

You must have Odin and Julia installed on your system to build from source, and both
must be available on PATH.

Clone the git repository, then build. Both the conventional `make` entry point
(on Linux/macOS) and the PowerShell entry point (on Windows) run `configure`
automatically the first time to verify the toolchain and install the required
Julia packages. Then they build via `make.jl`.

### Linux / macOS (shell + Makefile)

```bash
git clone https://github.com/derekshoneycutt/Euclid.git
cd Euclid
make            # configure (first run) + build
make run        # build and run the application
```

### Windows (PowerShell + make.ps1)

Windows does not ship a standard `make`, so the same shortcuts are provided by
`make.ps1`:

```powershell
git clone https://github.com/derekshoneycutt/Euclid.git
cd Euclid
.\make.ps1            # configure (first run) + build
.\make.ps1 run        # build and run the application
```

### Driving the scripts directly

Prefer to call the scripts yourself? That works the same everywhere:

```bash
./configure           # Linux / macOS; .\configure in Windows PowerShell
julia tools/make.jl
# To run immediately: julia tools/make.jl -r
```

### Build targets

The `Makefile` (Linux/macOS) and `make.ps1` (Windows) are thin, conventional
wrappers over the same commands — all real logic lives in `configure` and
`make.jl`. Both run `configure` once (tracked by a `.configure-done` sentinel)
before any build target, so the first bare build just works after cloning. The
targets are identical across both entry points:

| Linux / macOS | Windows | What it runs |
| --- | --- | --- |
| `make` / `make build` | `.\make.ps1` | `configure` (once), then `julia tools/make.jl` |
| `make run` | `.\make.ps1 run` | `julia tools/make.jl --run` |
| `make test` / `make check` | `.\make.ps1 test` / `.\make.ps1 check` | `julia tools/make.jl --vet --test` (the verification baseline) |
| `make vet` | `.\make.ps1 vet` | `julia tools/make.jl --vet` |
| `make sysimage` | `.\make.ps1 sysimage` | `julia tools/make.jl --sysimage` |
| `make harness` | `.\make.ps1 harness` | `julia tools/make.jl --harness` |
| `make wiki` | `.\make.ps1 wiki` | `julia tools/make.jl --wiki` |
| `make check-wiki` | `.\make.ps1 check-wiki` | `julia tools/make.jl --check-wiki` |
| `make configure` | `.\make.ps1 configure` | re-run `configure` |
| `make clean` | `.\make.ps1 clean` | `julia tools/make.jl --clean` (also clears the configure sentinel) |
| `make help` | `.\make.ps1 help` | `julia tools/make.jl --help` |

### The configure script

The `configure` script is a polyglot (POSIX sh and PowerShell) that works on
Linux, macOS, and Windows. It checks that `odin` and `julia` are on PATH, runs
`Pkg.instantiate()` for the application environment (`src/julia`), and installs
the Julia static-analysis packages (JET, JuliaSyntax, CodeComplexity) used by the
vet tooling into the default Julia environment if they are missing.

### Windows requires a few more additions before this will work

- `MSVC Toolchain` : Odin will require MSVC tools installed on the system.
- `gendef` : used in the script to bridge the fact that Julia is not built with
  the same toolchain as Odin uses to build binaries. `gendef` can be installed via e.g.
  Strawberry Perl or MSYS2.

On Windows, `configure` also verifies that the MSVC environment (or `cl.exe`) and
`gendef` are available.

## Documentation

- [Euclid Wiki](https://github.com/derekshoneycutt/Euclid/wiki):
 published project documentation.
- [Code Reference](https://github.com/derekshoneycutt/Euclid/wiki/Code/Home):
 generated Odin and
  Julia APIs.
- [Guides](docs/wiki/Guides/ArchitectureSummary.md):
 canonical authored architecture, coding, animation, and syntax documentation.

Generate the complete publishable Wiki artifact locally with `julia tools/make.jl -w`.
The artifact is written to ignored `bin/wiki/`. Run `julia tools/make.jl -W` to compare it
against a fresh generation without modifying the retained artifact.

## Questions?

### Q: Why?

Because Euclid is *fun*, and rendering fun drawings of Elements is *fun*. It is also quite
educational and works out the brain a bit. You should try such things sometimes.

### Q: What's the utility?

Well, it is educational!

It's also seriously just *fun*.

### Q: What about AI?

First, my general policy on it is this: I will not accept code in this project that cannot
be thoroughly explained and followed up on by a human coder. I do read and work on every
line of code in this project myself, regardless of where that code has come from--be it
the old depths of stack overflow, my brain, someone else's brain, some AI tool or another,
or some other tool.

This is not going to be as strong as some would wish. For a project being released into
the public domain, I just do not have the energy for a stronger stance in this project.
The concerns are ethical and especially political. In that realm, this project is
inherently hostile to copyright by its own licensing. The remaining concerns largely boil
down to the sustainability. I feel absolutely no need to give AI any benefit of the doubt
that it is actually sustainable enough to be worth its relatively low quality output.
Otherwise, these concerns are difficult to address with a simple public domain geometry
software project. A public domain project is really not the place for many of these
ethical and political discussions. I will not be fighting that in this project. This will
not be a project that is concerned with any stronger stance than demanding a human take
full responsibility.

I do see this as an educational project. I am certainly expanding my understanding of
geometry as I explore it, and I am learning a lot about graphics programming. Sometimes my
code sucks, and even AI will gladly point it out the second someone points a code review
agent at it. Sometimes I see AI's suggested code and want to find the closest, highest
bridge to save my eyes via a nice long fall. My recommendation for the vibecoders is to go
try and program an OS with a basic text file editor to run in a VM using nothing but ASM,
and no AI. Something difficult that you will get some taste from. Then whatever, man. Just
read the code and fix the stupid shit.

### Q: What is the "Scratchpad"?

Before continuing, the point of the Scratchpad is indeed to make the application even more
*fun*. Once again, the point is to be *fun*. Nonetheless, it is a bit technical, including
computer code. Reader beware. Caution to the wind, this does also provide some educational
benefit for the tinkerers out there, I think, which is a beneficial addition.

The code of this project is designed with a core engine coded in Odin, but all of the
animations are executed as Julia scripts. Julia is a fast, JIT compiled language in this
use. Julia users will also be familiar with the REPL, where they can enter in Julia code
essentially line-by-line and see how it works in a live environment. The Scratchpad in
this project is like this. It provides an emptied drawing surface and a line input for
Julia code input. `2+2` will show `4` in the output directly above, for example. In fact,
via using Julia's `REPL` package directly, even scope issues should follow similar Julia
REPL standards for those already familiar.

`:help` will show most of the important information for how to use the Scratchpad in
practice. Importantly, starting a line with `?` will attempt to do a focused documentation
query.

A quick cheatsheet for drawing the standard Euclidean matters:

- `point!([x, y, z])` e.g. `point!([0.5f0, 0.5f0, 0f0])`
  : Animates drawing a single point.
- `line!([x1, y1, z1], [x2, y2, z2])` e.g.
  `line!([0.1f0, 0.1f0, 0f0], [0.1f0, 0.9f0, 0f0])`
  : Animates drawing a line from [x1, y1, z1] to [x2, y2, z2].
- `circle!([x, y, z], r)` e.g. `circle!([0.5f0, 0.5f0, 0f0], 0.25f0)`
  : Animates drawing a circle centered at [x, y, z], with a radius of r.

For additional help:

- Following `?` with a variable name that contains a value of some struct type, a list of
  properties of that struct type will be listed.
- Following `?` with a module name (e.g. `?OdinJuliaBridge`) will attempt to list all
  unique function names available in the name module.
- Following `?` with a function name (e.g. `?OdinJuliaBrige.create_new_point`) will
  attempt to display the documentation comment for that function and all parameter
  variants.

Not so secretly, this can be a helpful way to navigate the OdinJuliaBridge most of all,
even if not using the Scratchpad for any other purpose. Kind of like man pages.

#### Some details about using the Scratchpad

The `state_ptr` variable is *always* available from the Scratchpad. This is the first
parameter that is sent to all `OdinJuliaBridge` functions, and it holds a value of type
`Ptr{Cvoid}`, pointing back to the Odin state structure in memory.

Coordinate reminders:

- Use normalized surface coordinates: `x, y ∈ [0.0, 1.0]`.
- Treat `z = 0.0` as the draw surface; positive `z` is up (pen lift/travel).
- Follow a right-hand orientation for 3D thinking: on screen, +X trends up-right and +Y
  trends up-left on the surface; set your right thumb to +X and index to +Y, and your
  middle finger gives +Z (up/elevation). See
  [Right hand rule](https://en.wikipedia.org/wiki/Right-hand_rule)
  with the knowledge that we are always x pointed up-right, y pointed up-left in our
  projections for this project.

This is meant for prototype drawing, as opposed to dedicated animations. However, fast
one-off animations are possible via the frame loop hooks that are included. See the list
of helpers in `:help`. If you bracket the beginning and end of an animation with
`OdinJuliaBridge.notify_animation_cycle_boundary(state_ptr)`, you can even use the Save
Gif feature to save a gif of your one-off animations. You will be responsible for managing
the state machine of such animations. You can use REPL variables or the OdinJuliaBridge
metadata storage functions used by most static animations.

### Q: Wait, Save Gif?

Yup, you can save an animation to a gif file! This is available via the camera icon in the
top right of the window. This requires that an animation notify when it begins and ends,
meaning the top animation for many sections will not be allowed to be saved. Most other
animations can be saved to a gif file, directly from your viewpoint. Click the camera icon
to enter the Gif Export view, and click Save Gif. The request will be logged, pending the
start of the next animation. When the next animation starts, notifying the animation cycle
boundary, the gif is initiated, and frames are saved into the gif buffer. When the
animation ends, again notfying the animation cycle boundary, the gif buffer is then saved
to a file.

If animation is paused in the middle of a gif save, the paused time is not included in the
animation. It is all skipped and the gif proceeds as if it was never paused. If the
animation is reset, the gif is canceled.

I have some thoughts about other potential export formats that could be done from the
camera tab, but for today, it is just gifs. The current code was ported from several
pieces of C code walking through saving a gif, and something like ffmpeg could probably
significantly improve on even that, as well as adding other formats. Such are
considerations for the future.

### Q: You support LaTeX?

Yes. Somehow, I ended up writing a little mini-LaTeX math renderer in this project. It was
kind of a pain in the ass for half a week, and it does not yet support everything one
might hope to find in a more thorough LaTeX rendering engine. This is basically a work in
progress. The code is kind of a mess, I know it. No shame... well, there's a little bit of
shame about it, but we're just gonna sit in that and learn.

Check out [LaTeX Support](docs/wiki/Guides/LaTeXSupport.md) for exactly what we do support
today.

The fun thing is that the REPL will render LaTeX if the output is fully a LaTeX MIME type.
For example, LaTeXStrings gives the `L"..."` syntax, which will render a LaTeX string as
much as is supported. `LaTeXStrings` is automatically included in the REPL, so you can use
this to play with what is supported.

Currently, only math mode is supported. Maybe I'll add more? Hmm...

### Q: Any performance hacks for users?

There are a few!

At the top right of the screen, you can go into the Settings panel. Here, you can reduce
the maximum number of dust particles that are allowed on the drawing surface, which can
improve performance. You can also turn the FPS display on/off, enable or disable drawing
sound, and turn FPS limiting on/off. Turning the FPS limit on/off may have no real effect
if vsync is on (the default). Additionally, you can toggle SIMD use for use in isometric
projection, which is on by default. The SIMD has little effect either way on most modern
computers, to be honest, especially given LLVM may make this optimization in either case.
The single biggest performance tweak is the default-enabled GPU Dust Instancing, which
will draw the dust particles with the GPU and O(1) on the CPU to instance the data.

The optional sysimage with `make.jl` bakes stable Julia runtime modules and representative
LaTeX/Scratchpad compiler workloads into a platform-specific shared library beside the
executable. Build and run it with `julia tools/make.jl -sr`. Ordinary build or asset
commands remove an existing sysimage to prevent stale baked code from being used.

Additionally, there are some startup options that can affect application performance.

```text
Usage: ./euclid [options]

Options:
  -v, --vsync              Enable VSYNC. (default)
  -V, --no-vsync           Disable VSYNC.
  -a, --antialiasing       Enable anti-aliasing. (default)
  -A, --no-antialiasing    Disable anti-aliasing.
  --dust-particle-max=N    Set maximum dust particles, 0-8192. (default: 8192)
  -f, --limit-fps          Limit rendering to 60 FPS. (default)
  -F, --no-limit-fps       Disable the 60 FPS limit.
  -s, --simd               Enable SIMD projection when available. (default)
  -S, --no-simd            Disable SIMD projection.
  -g, --gpu-dust-instancing Enable GPU dust instancing when available. (default)
  -G, --no-gpu-dust-instancing Disable GPU dust instancing.
  --semantic-trace         Enable semantic trace output.
  --semantic-trace-output=PATH  Write semantic trace JSONL to PATH.
  --semantic-trace-events=LIST   Limit trace categories (runtime,animation,geometry,tools,particles,view).
  --semantic-trace-strict  Fail the run when trace overflow or serialization fails.
  -h, --help               Show this help text.

Short options can be combined, for example: -vasg or -VAFSG
```

### Q: Why 2 languages?

Because saying "Odin-Julia Bridge" is *fun*.

This whole thing began using Julia with Makie to draw Euclid's Elements inside Jupyter
notebooks. Ultimately, it became quite clear that what I was looking for was not a great
fit to that model, and I froze on it a bit.

I had some thoughts about making a C application for this project, but I was not very
excited about it at any given moment. Julia has lagged a bit in getting a stand-alone
executable route, so it seemed unlikely to go purely Julia for quite a while. This has
been changing as Julia community continues pursuing their one language paradigm, but alas,
here I am. As I was doing another project exploring 76 different programming languages, I
encountered Odin and enjoyed working with it. On a whim, I was playing with a basic
kinematic system in Odin when it occurred to me it would be a great basis for this
Euclid project.

Ultimately, having a strong solid application base with manual memory management and
potential for optimizations at a relatively low level combined with an intentionally fast,
JIT compiled, GC managed language on the individual animation level has its own
advantages. I probably would not actually choose this without the unique history of this
project, but it is actually quite an enjoyable programming experience between the two.
They are different languages, but both offer language-level tools for the kind of maths
used in this project that just make it an enjoyable experience!

### Q: Are there any more options with the make scripts?

The build driver (`tools/make.jl`, normally reached through `make` or `make.ps1`)
has several helpful parameters if the simple stuff above is not enough.

```text
Usage: ./make.jl [options]

Options:
    --build, -b         Build the project. (default)
    --no-build, -B      Skip any build, including vet builds.
    --assets, -a        Build assets.pkg. (default)
    --no-assets, -A     Skip assets.pkg build.
    --sysimage, -s      Build a custom Julia sysimage beside the application.
    --harness, -H       Build and run the headless semantic trace harness.
    --clean, -c         Delete generated build artifacts.
    --run, -r           Run bin/euclid after all other requests.
    --test, -t          Run project tests for the phased testing plan.
    --vet, -v           Build with validation flags.
    --wiki, -w          Generate the publishable Wiki artifact in bin/wiki.
    --check-wiki, -W    Compare bin/wiki with a fresh generation without modifying it.
    --                  Pass all remaining args directly to bin/euclid (only with --run).
    --help, -h          Show this help text.

Notes:
    - If no options are provided, the default is --build --assets.
    - Lowercase -b/-a enables build/assets; uppercase -B/-A disables them.
    - Short options can be combined, e.g. -rvas or -Ba.
```

The harness target is intended for semantic trace and deterministic scenario work. Its
underlying executable accepts a smaller control surface:

```text
Usage: euclid_harness --asset-root=PATH --animation-id=UUID --steps=N --trace-output=PATH [--scenario=NAME]
```

`julia tools/make.jl -H` builds and runs the default harness scenario and writes the
resulting trace to `bin/semantic-trace-harness.jsonl`.

### Q: Where should I start if I want in the code?

I have added an initial architecture summary and coding standards that can be your guides.

- [Architecture Summary](docs/wiki/Guides/ArchitectureSummary.md): describes the several
  modules, boundaries, etc., and how they fit together. Includes important code files to
  start with.
- [Coding Standards](docs/wiki/Guides/CodingStandards.md): describes how any new code
  should be written

The project was initially quite messy, without a standard and with all the artifacts of
exploring and learning a new-to-me language, as well as me not really being a traditional
animation programmer in any sense of the restriction. I am more an application or backend
engineer by trade. Additionally, some of the code was initially prototyped for a very
different purpose. The result is some code not quite being as nice to the code standard.
Nonetheless, the goal is to follow it moving forward, and probably fix up the bits that
remain a bit off as I go.

### Q: What's this about hot-reload?

The project is structured to hot-reload all Julia code if the assets package is updated.
You can simply call the make script specifying to build only the assets package. Then
copy the built package next to the running instance. If you run from the `bin` folder of
a compilation, this will automatically replace the assets package there.

```bash
julia tools/make.jl -Ba
```

Euclid will automatically notice the updated package file, unpack it, and reload all
the Julia code, restarting the current animation according to the new code. If the current
animation cannot be found, will simply start the first animation in the tree. This can be
helpful for simple animation updates.

Animation content remains dynamically loaded when using a sysimage. Changes to baked core
modules such as the bridge wrappers, LaTeX compiler, geometry helpers, animation helpers,
or Scratchpad require rebuilding the sysimage and restarting Euclid.

### Q: What is all this output in the make vet output?

Great question! A lot of this only makes any sense if you are really into the software
engineering stuff. We perform several checks in the vet mode to try and improve code
quality and performance.

**FIRST**: There are dependencies in the make script for the vet mode,
namely JET.jl, JuliaSyntax.jl, and CodeComplexity.jl. The `./configure` script
installs these into the default Julia environment automatically (see
[Building from Source](#building-from-source)). To add them manually instead:

```julia
using Pkg
Pkg.add("JET")
Pkg.add("JuliaSyntax")
Pkg.add("CodeComplexity")
```

Odin static analysis is performed by a purpose-built analyzer in `tools/vet`
that is compiled automatically during vet mode; no external Odin linter is
required.

Repository-wide statistics (line counts, complexity, COCOMO, and an LLM
regeneration-cost estimate) are computed by a first-party `repo-metrics`
analysis built into the vet script. No external code counter (such as `scc`)
is required; everything is derived from the same Julia and Odin token streams
the rest of the vet pipeline already parses.

```bash
julia tools/make.jl -v
```

#### Report Output

Vet mode writes a full report to `bin/vet-report.md` on every run. Console output stays
summary-first and points to that report for full detail.

Report section statuses use these meanings:

- `Pass`: check completed without findings requiring warning/fail status.
- `Warn`: check completed with warning-only findings or partial analysis gaps.
- `Fail`: blocking findings were detected.
- `Skipped`: check was intentionally not run for the current context.
- `Missing`: required external tool was not available.

The report includes sections for the Odin vet build, Odin compiler dependencies,
Julia syntax, Julia parser metadata, Julia CodeComplexity, Julia JET, Odin static
analysis, Odin allocations, and repository metrics (`repo-metrics`).

#### Odin

First, Odin is run with a set of vet flags that enforces style throughout the Odin code,
treating warnings as errors, etc. Thankfully, we can skip the tabs they require in their
own repository in the Odin code.

Additionally, vet mode compiles and runs the Odin static analyzer in
`tools/vet`, which uses `core:odin/parser` to measure every Odin procedure
against the coding standards: NLOC, cyclomatic complexity, and parameter count.
Complexity at or above 15 is a blocking violation unless the procedure carries an
inline `#vet forgives(cyclomatic_complexity)` exception; complexity 11-14 warns.
NLOC and parameter count remain review signals. The analyzer also traces
allocation call sites (`new`, `make`, `append`, and known allocating helpers) and
classifies each by allocator source: a site with no explicit allocator is a
blocking violation, and an explicit default-heap allocator (`context.allocator`)
warns. Documented exceptions use `#vet forgives(implicit_allocator)` or
`#vet forgives(heap_allocator)` with an explanatory comment. Sites are reported
prominently in the `odin-allocations` report section with basic statistics
printed on every vet run.

The `repo-metrics` section (see below) provides additional repository-wide
statistics.

#### Julia

For Julia, the first thing that happens is that the make script loads the entire Julia
source into AST to check for any obvious syntax errors. This catches many simple typos
before it gets any further.

Additionally, we use `CodeComplexity.jl` and `JET.jl` which allows us to perform both
complexity checks and some static analysis on the code, preventing some pretty obvious
errors before they are run.

The `repo-metrics` section (see below) provides additional repository-wide
statistics.

#### repo-metrics

The `repo-metrics` section computes repository-wide statistics with the project's
own toolchain, replacing the external `scc` code counter. Because it reuses the
same parse that powers the other checks (JuliaSyntax for Julia, `core:odin/tokenizer`
for Odin), its line and complexity figures are parse-accurate rather than
regex/keyword estimates. It throws no warnings or errors and cannot guarantee code
quality, but it isolates logic hotspots and shows how the code is structured. The
Odin side will typically carry more complexity hotspots simply because it is the
ultimate arbiter of control for the application in many places.

It reports, per language and per top-level directory:

- **Line inventory**: Files, Lines, and the breakdown into Code, Comments, and
  Blank lines. A line counts as *code* when it carries at least one non-comment,
  non-string character; *comment* when it is only comment/string content; *blank*
  when empty.
- **Complexity**: total cyclomatic complexity per bucket, summed from the real
  per-function measures (the Odin static analyzer and CodeComplexity.jl).
- **COCOMO (organic)**: the classic human effort/schedule/staffing estimate,
  including an estimated cost-to-develop in USD.
- **LOCOMO**: an experimental LLM *regeneration*-cost estimate (input/output
  tokens, dollar cost, iteration cycles, generation time, and human review time),
  modeled on the same idea as `scc`'s LOCOMO but fed our parse-accurate
  complexity density. This is a rough ballpark for what it would cost to have an
  LLM retype code it already knows the shape of — not the cost to design it.

A derived **Complexity/Code** ratio is reported for Odin, Julia, and Total. This is
the average number of branch points per line of code. In general, if the Odin code
remains moderately high (0.13-0.18) it is considered pretty good, and we generally
expect the Julia code to remain low-moderate (0.05-0.13). The total being a moderate
0.09-0.13 would be a great expectation. Treat the cross-language gap with some care:
the two engines tokenize branch constructs slightly differently, so the ratio is most
meaningful as a per-language trend over time rather than a precise side-by-side
comparison. For meaningful per-function and per-file signal, the Odin static analyzer
and `CodeComplexity.jl` outputs are more telling than these aggregate ratios.
Nonetheless, the `repo-metrics` outputs can indicate issues with stupid code decisions
we should feel bad about. And make us feel like 100x developers or something.
