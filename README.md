# Euclid

This is a basic project to create an application that animates Euclid's Elements.

This is done in Odin for the primary application, with bindings to Julia to drive the
animations. Raylib is used for rendering.

1. [Building from Source](#building-from-source)
1. [Questions?](#questions)
    1. [Q: Why?](#q-why)
    1. [Q: What's the utility?](#q-whats-the-utility)
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
julia /make.jl
# To run immediately: julia make.jl -r
```

### Dependencies at Build Time

There are dependencies in the make julia script, namely JET.jl and CodeComplexity.jl.
These can both be added via the standard julia package manager. These are especially
important for the vet functionality that ensures code meets appropriate standards via
static analysis.

```julia
] add JET
] add CodeComplexity

#OR

using Pkg
Pkg.add("JET")
pkg.add("CodeComplexity")
```

You should also have `lizard` installed for the static analysis of Odin code.

#### Windows requires a few more additions before this will work

- `MSVC Toolchain` : Odin will require MSVC tools installed on the system.
- `gendef` : used in the python script to bridge the fact that Julia is not built with
  the same toolchain as Odin uses to build binaries. `gendef` can be installed via e.g.
  Strawberry Perl or MSYS2.

## Questions?

### Q: Why?

Because Euclid is *fun*, and rendering fun drawings of Elements is *fun*. It is also quite
educational and works out the brain a bit. You should try such things sometimes.

### Q: What's the utility?

Well, it is educational!

It's also seriously just *fun*.

### Q: Why 2 languages?

Because saying "Odin-Julia Bridge" is *fun*.

This whole thing began using Julia with Makie to draw Euclid's Elements via Jupyter
notebooks. Ultimately, it became quite clear that what I was looking for was not a great
fit to that model, and I froze on it a bit.

I had some thoughts about making a C application for it, but I was not very excited about
it at any given moment. As I was doing another project exploring 76 different programming
languages, I encountered Odin and enjoyed working with it. On a whim, I was playing with a
basic kinematic system in Odin when it occurred to me it would be a great basis for this
Euclid project.

Ultimately, having a strong solid application base with manual memory management and
potential for optimizations at a relatively low level combined with an intentionally fast,
JIT compiled, GC managed language on the individual animation level has its own advantages.
I probably would not actually choose this without the unique history of this project, but
it is actually quite an enjoyable programming experience between the two. They are different
languages, but both offer language-level tools for the kind of maths used in this project
that just make it an enjoyable experience!

### Q: Are there any more options with the make scripts?

The make script (both `make.py`) has several helpful parameters if the simple stuff above
is not enough.

```text
Usage: ./make.py [options]

Options:
    --build, -b         Build the project.
    --assets, -a        Build assets.pkg.
    --run, -r           Run bin/euclid after all other requests.
    --vet, -v           Build with validation flags.
    --fail-lizard, -f   With --vet, fail if any lizard analysis exits non-zero.
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
./make.py -na
```

EuclidApp will automatically notice the updated package file, unpack it, and reload all
the Julia code, restarting the current animation according to the new code. If the current
animation cannot be found, will simply start the first animation in the tree. This can be
helpful for simple animation updates.
