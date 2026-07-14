# Euclid

This is a basic project to create an application that animates Euclid's Elements.

This is done in Odin for the primary application, with bindings to Julia to drive the
animations. Raylib is used for rendering.

1. [Building from Source](#building-from-source)
1. [Questions?](#questions)
    1. [Q: Why?](#q-why)
    1. [Q: What's the utility?](#q-whats-the-utility)
    1. [Q: What is the "Scratchpad"?](#q-what-is-the-scratchpad)
    1. [Q: Wait, Save Gif?](#q-wait-save-gif)
    1. [Q: Any Performance Hacks for Users?](#q-any-performance-hacks-for-users)
    1. [Q: Why 2 languages?](#q-why-2-languages)
    1. [Q: Are there any more options with the make scripts?](#q-are-there-any-more-options-with-the-make-scripts)
    1. [Q: Where should I start if I want in the code?](#q-where-should-i-start-if-i-want-in-the-code)
    1. [Q: What's This About Hot-Reload?](#q-whats-this-about-hot-reload)

<p align="center">
<img src="./screen.gif" >
</p>

## Building from Source

You must have Odin and Julia installed on your system to build from source, and both
must be available on PATH.

Clone the git repository as per usual practices and run the make script below.

```bash
git clone https://github.com/derekshoneycutt/EuclidApp.git
cd EuclidApp
julia make.jl
# To run immediately: julia make.jl -r
```

### Dependencies at Build Time

There are dependencies in the make julia script, namely JET.jl and CodeComplexity.jl.
These can both be added via the standard julia package manager. These are especially
important for the vet functionality that ensures code meets appropriate standards via
static analysis.

```julia
using Pkg
Pkg.add("JET")
pkg.add("CodeComplexity")
```

You should also have `lizard` installed for the static analysis of Odin code.

You should also have `scc` installed for broad code statistics of the codebase.

#### Windows requires a few more additions before this will work

- `MSVC Toolchain` : Odin will require MSVC tools installed on the system.
- `gendef` : used in the script to bridge the fact that Julia is not built with
  the same toolchain as Odin uses to build binaries. `gendef` can be installed via e.g.
  Strawberry Perl or MSYS2.

## Questions?

### Q: Why?

Because Euclid is *fun*, and rendering fun drawings of Elements is *fun*. It is also quite
educational and works out the brain a bit. You should try such things sometimes.

### Q: What's the utility?

Well, it is educational!

It's also seriously just *fun*.

### Q: What is the "Scratchpad"?

Before continuing, the point of the Scratchpad is indeed to make the application even more
*fun*. Once again, the point is to be *fun*. Nonetheless, it is a bit technical, including
computer code. Reader beware. Caution to the wind, this does also provide some educational
benefit for the tinkerers out there, I think, which is a beneficial addition.

The code of this project is designed with a core engine coded in Odin, but all of the
animations are executed as Julia scripts. Julia is a fast, JIT compiled language in this
use. Julia users will also be familiar with the REPL, where they can enter in Julia code
essentially line-by-line and see how it works in a live environment. The Scratchpad in this
project is like this. It provides an emptied drawing surface and a line input for Julia
code input. `2+2` will show `4` in the output directly above, for example. In fact, via
using Julia's `REPL` package directly, even scope issues should follow similar Julia REPL
standards for those already familiar.

The `state_ptr` variable is always available from the Scratchpad. This is the first
parameter that is sent to all OdinJuliaBridge functions, and it holds a value of type
`Ptr{Nothing}`, pointing back to the Odin state structure in memory.

`:help` will show most of the important information for how to use the Scratchpad in
practice. Importantly, starting a line with `?` will attempt to do a focused documentation
query.

- Following `?` with a variable name that contains a value of some struct type, a list of
  properties of that struct type will be listed.
- Following `?` with a module name (e.g. `?OdinJuliaBridge`) will attempt to list all
  unique function names available in the name module.
- Following `?` with a function name (e.g. `?OdinJuliaBrige.create_new_point`) will
  attempt to display the documentation comment for that function and all parameter variants.

Not so secretly, this can be a helpful way to navigate the OdinJuliaBridge most of all,
even if not using the Scratchpad for any other purpose. Kind of like man pages.

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

### Q: Any Performance Hacks for Users?

There are a few!

At the top right of the screen, you can go into the Settings panel. Here, you can reduce
the maximum number of dust particles that are allowed on the drawing surface, which can
improve performance. You can also turn the FPS display on/off, as well as turn FPS
limiting on/off. Turning the FPS limit on/off may have no real effect if vsync is on (the
default). Additionally, you can toggle SIMD use for use in isometric projection, which
is on by default. The SIMD has little effect either way on most modern computers, to be
honest.

Additionally, there are some startup options that can affect application performance.

```text
Usage: ./euclid [options]

Options:
  --vsync              Enable VSYNC. (default)
  --no-vsync           Disable VSYNC.
  --antialiasing       Enable anti-aliasing. (default)
  --no-antialiasing    Disable anti-aliasing.
  --help               Show this help text.
```

### Q: Why 2 languages?

Because saying "Odin-Julia Bridge" is *fun*.

This whole thing began using Julia with Makie to draw Euclid's Elements inside Jupyter
notebooks. Ultimately, it became quite clear that what I was looking for was not a great
fit to that model, and I froze on it a bit.

I had some thoughts about making a C application for this project, but I was not very
excited about it at any given moment. Julia has lagged a bit in getting a stand-alone
executable route, so it seemed unlikely to go purely Julia for quite a while. This has been
changing as Julia community continues pursuing their one language paradigm, but alas, here
I am. As I was doing another project exploring 76 different programming languages, I
encountered Odin and enjoyed working with it. On a whim, I was playing with a basic
kinematic system in Odin when it occurred to me it would be a great basis for this
Euclid project.

Ultimately, having a strong solid application base with manual memory management and
potential for optimizations at a relatively low level combined with an intentionally fast,
JIT compiled, GC managed language on the individual animation level has its own advantages.
I probably would not actually choose this without the unique history of this project, but
it is actually quite an enjoyable programming experience between the two. They are different
languages, but both offer language-level tools for the kind of maths used in this project
that just make it an enjoyable experience!

### Q: Are there any more options with the make scripts?

The make script (both `make.jl`) has several helpful parameters if the simple stuff above
is not enough.

```text
Usage: ./make.jl [options]

Options:
    --build, -b         Build the project.
    --assets, -a        Build assets.pkg.
    --run, -r           Run bin/euclid after all other requests.
    --vet, -v           Build with validation flags.
    --no-build, -n      Skip any build (overrides --build and --vet).
    --no-assets, -x     Skip assets.pkg build (overrides --assets).
    --                  Pass all remaining args directly to bin/euclid (only with --run).
    --help, -h          Show this help text.

Notes:
    - If no options are provided, the default is --build --assets.
    - That is, --build and --assets are essentially non-altering flags, included for visibility.
    - Short options can be combined, e.g. -rva or -bnx.
```

### Q: Where Should I Start If I Want In The Code?

I have added an initial architecture summary and coding standards that can be your guides.

- [Architecture Summary](ArchitectureSummary.md): describes the several modules, boundaries,
  etc., and how they fit together. Includes important code files to start with.
- [Coding Standards](CodingStandards.md): describes how any new code should be written

The project was initially quite messy, without a standard and with all the artifacts of
exploring and learning a new-to-me language, as well as me not really being a traditional
animation programmer in any sense of the restriction. I am more an application or backend
engineer by trade. Additionally, some of the code was initially prototyped for a very
different purpose. The result is some code not quite being as nice to the code standard.
Nonetheless, the goal is to follow it moving forward, and probably fix up the bits that
remain a bit off as I go.

### Q: What's This About Hot-Reload?

The project is structured to hot-reload all Julia code if the assets package is updated.
You can simply call the make script specifying to build only the assets package. Then
copy the built package next to the running instance. If you run from the `bin` folder of
a compilation, this will automatically replace the assets package there.

```bash
julia make.jl -na
```

EuclidApp will automatically notice the updated package file, unpack it, and reload all
the Julia code, restarting the current animation according to the new code. If the current
animation cannot be found, will simply start the first animation in the tree. This can be
helpful for simple animation updates.
