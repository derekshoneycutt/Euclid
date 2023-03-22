# Euclid

This first began as a project entirely about trying to code out the propositions in Euclid's Elements using the Julia language and GLMakie. That remains entirely true for what this is, but after some frustration with my initial round, I began to pull the code out into a new version. This one is pretty comprehensive, with the intent to make sure that definitions and all can be demonstrated in the diagrams.

This uses the Thomas L Heath translation, which remains the standard translation for Euclid to this day.

---

Navigating with interest to Euclid, look no further than the `ElementsBook1` directory. Begin with `Defintions`, then consider the `Postulates` and `CommonNotions`. Additional work needed to explain  These will arm with the knowledge to begin attacking the `Propositions`. Subsequent books will follow this same pattern. Within each of these, the primary points of interest are the Jupyter notebooks `000-xxx.ipynb`, which contain demonstrations of the concepts being worked out. Under each folder, there is also a `gifs` and `src` folder containing generated gifs (also reproduced in the Jupyter notebooks) and the source code underlying the drawing methods.

There is also additional code in the `Core` directory, containing essential code for drawing the diagrams. `Euclid.jl` is the central file that can include all of this at once, including the definitions and code from propositions, and the Jupyter notebooks rely on this.

If the code does not run due to Julia packages missing, run the `AddPackages.jl` file on the system. This will install all prerequisites and ensure that the code runs well.