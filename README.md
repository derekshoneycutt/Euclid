# Euclid

This first began as a project entirely about trying to code out the propositions in Euclid's Elements using the Julia language and GLMakie. That remains entirely true for what this is, but after some frustration with my initial round, I began to pull the code out into a new version. This one is pretty comprehensive, with the intent to make sure that definitions and all can be demonstrated in the diagrams.

This uses the Thomas L Heath translation, which remains the standard translation for Euclid to this day.

---

This project can be used as a Julia module. Although I have no intention of publishing it as an official package, it can be brought into any other project by adding it directly from the git repository.

```julia
using Pkg
Pkg.add(url="https://github.com/derekshoneycutt/Euclid.git")

# ...

using Euclid
```

---

## Euclid's Elements

1. [Book I](ElementsBook1/)
