# Euclid

This is a basic project to create an application that animates Euclid's Elements.

This is done in Odin for the primary application, with bindings to Julia to drive the
animations. Raylib is used for rendering.

Simply use `./make.sh` to build. You can also use `./make.sh --run` to immediately run.
You must have Odin and Julia installed on your system.

<p align="center">
<img src="./screen.gif" >
</p>

## Questions?

### Q: Why?

Because Euclid is *fun*, and rendering fun drawings of Elements is *fun*. It is also quite
educational and works out the brain a bit. You should try such things sometimes.

### Q: Why 2 languages?

Because saying "Odin-Julia Bridge" is *fun*.

This whole thing began using Julia with Makie to draw Euclid's Elements via Jupyter
notebooks. Ultimately, it became quite clear that what I was looking for was not a great
fit to that model, and I froze on it a bit.

I had some thoughts about making a C application for it, but I hardly like programming in
C much more than assembly (I **do** like programming in assembly **sometimes**). As I was
doing another project exploring 76 different programming languages, I encountered Odin and
enjoyed working with it. On a whim,I was playing with a basic kinematic system in Odin
when it occurred to me it would be a great basis for this Euclid project.

Ultimately, having a strong solid application base with manual memory management and
potential for optimizations at a relatively low level combined with an intentionally fast,
JIT compiled, GC managed language on the individual animation level has its own advantages.
I probably would not actually choose this without the unique history of this project, but
it is actually quite an enjoyable programming experience between the two. They are different
languages, but both offer language-level tools for the kind of maths used in this project
that just make it an enjoyable experience!

### Q: What's the utility?

Well, it is educational!

It's also seriously just *fun*.
