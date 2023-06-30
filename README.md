# Euclid

This first began as a project entirely about trying to code out the propositions in Euclid's Elements using the Julia language and GLMakie. That remains entirely true for what this is, but after some frustration with my initial round, I began to pull the code out into a new version. This one is pretty comprehensive, with the intent to make sure that definitions and all can be demonstrated in the diagrams.

This uses the Thomas L Heath translation, which remains the standard translation for Euclid to this day.


See [https://derekshoneycutt.github.io/Euclid/index.html](https://derekshoneycutt.github.io/Euclid/index.html) for the presented version of Euclid's Elements.

---

## Euclid's Elements

1. [Book I](ElementsBook1/)

---

## Building The Project

This uses the a Julia module, Euclid.jl, which is published on GitHub. Although no intentions are to publish it wider, it is required to build here and can be used itself further. This was mostly done to separate build concerns during development, but it also cleans up the repositories and lets this one focus on the Jupyter notebooks and an initial presentation.

```bash
julia AddPackages.jl
```

Alternatively, in a Julia console, but understand you need additional pre-requisites as well:

```julia
using Pkg
Pkg.add(url="https://github.com/derekshoneycutt/Euclid.jl.git")
```
