# Euclid

This first began as a project entirely about trying to code out the propositions in Euclid's Elements using the Julia language and GLMakie. That remains entirely true for what this is, but after some frustration with my initial round, I began to pull the code out into a new version. This one is pretty comprehensive, with the intent to make sure that definitions and all can be demonstrated in the diagrams.

This uses the Thomas L Heath translation, which remains the standard translation for Euclid to this day.

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

---

This is free and unencumbered software released into the public domain.

Anyone is free to copy, modify, publish, use, compile, sell, or
distribute this software, either in source code form or as a compiled
binary, for any purpose, commercial or non-commercial, and by any
means.

In jurisdictions that recognize copyright laws, the author or authors
of this software dedicate any and all copyright interest in the
software to the public domain. We make this dedication for the benefit
of the public at large and to the detriment of our heirs and
successors. We intend this dedication to be an overt act of
relinquishment in perpetuity of all present and future rights to this
software under copyright law.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR
OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
OTHER DEALINGS IN THE SOFTWARE.

For more information, please refer to <http://unlicense.org/>
