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

<p align="center">
<img src="./screen.gif" >
</p>

## Building from Source

You must have Odin and Julia installed on your system to build from source, and both
must be available on PATH.

Clone the git repository as per usual practices and run the make script below.

```bash
git clone https://github.com/derekshoneycutt/EuclidApp.git
```

### Linux / MacOS

Use `./make.sh` to build. You can also use `./make.sh --run` to immediately run.
include by default.

### Windows

On Windows, use `./make.ps1` to build or `./make.ps1 --run` to build and run.

#### Windows requires a few more additions before this will work

- `MSVC Toolchain` : Odin will require MSVC tools installed on the system.
- `gendef` : used in the PowerShell script to bridge the fact that Julia is not built with
  the same toolchain as Odin uses to build binaries. `gendef` can be installed via e.g.
  Strawberry Perl or MSYS2.
- `tar` : Shipped with most modern Windows versions since Windows 10. Earlier versions
  should install it, though compatibility may suffer for earlier Windows altogether.

### Julia Packages

The first run will start up a little bit faster if you pre-install packages in your Julia
environment. Otherwise, the first run will pull and install these, which may take a minute.

- `Colors`
- `LinearAlgebra`

For example:
```bash
julia
# type `]` to enter Package manager
(@1.12) pkg> add Colors
```

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

I had some thoughts about making a C application for it, but I hardly like programming in
C much more than assembly (I **do** like programming in assembly **sometimes**). As I was
doing another project exploring 76 different programming languages, I encountered Odin and
enjoyed working with it. On a whim, I was playing with a basic kinematic system in Odin
when it occurred to me it would be a great basis for this Euclid project.

Ultimately, having a strong solid application base with manual memory management and
potential for optimizations at a relatively low level combined with an intentionally fast,
JIT compiled, GC managed language on the individual animation level has its own advantages.
I probably would not actually choose this without the unique history of this project, but
it is actually quite an enjoyable programming experience between the two. They are different
languages, but both offer language-level tools for the kind of maths used in this project
that just make it an enjoyable experience!

### Q: Are there any more options with the make scripts?

The make scripts (both `make.sh` and `make.ps1`) has several helpful parameters if the
simple stuff above is not enough.

```text
Usage: ./make.sh [options]
    OR ./make.ps1 [options]

Options:
  --run, -r       Run bin/euclid after all other requests.
  --build, -b     Build the project.
  --vet, -v       Build with validation flags.
  --no-build, -n  Skip any build (overrides --build and --vet).
  --help, -h      Show this help text.

Notes:
  - If no options are provided, the default is to build.
  - Short options can be combined, e.g. -rv or -bnh.
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
