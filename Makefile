# Standard Makefile entry point for Euclid.
#
# This is a thin, conventional wrapper around the project's real build system:
# tools/configure.sh (toolchain check + Julia dependency install) and
# tools/make.jl (the actual build/test/vet driver). It exists so that the usual
# `make` / `make test` / `make clean` muscle memory — and tools that expect a
# Makefile — just work. All real logic lives under tools/.
#
# On Windows, use make.ps1 instead; it performs the same configure steps
# natively in PowerShell.

JULIA ?= julia
MAKEJL := $(JULIA) tools/make.jl

# Sentinel marking that `configure` has completed successfully at least once.
# Configure installs Julia dependencies, so we re-run it only when missing.
CONFIGURE_STAMP := .configure-done

.PHONY: all build run test vet check sysimage harness wiki check-wiki clean \
        configure help

# Default: configure (once), then build.
all: build

# Run the configure script and record completion so it is not re-run needlessly.
$(CONFIGURE_STAMP):
	sh tools/configure.sh
	@touch $(CONFIGURE_STAMP)

# Explicit configure target (forces a re-run).
configure:
	sh tools/configure.sh
	@touch $(CONFIGURE_STAMP)

# Build the project (the default `make`). Runs configure first if needed.
build: $(CONFIGURE_STAMP)
	$(MAKEJL)

# Build and run the application.
run: $(CONFIGURE_STAMP)
	$(MAKEJL) --run

# Build with validation flags, then run the full test plan.
test: $(CONFIGURE_STAMP)
	$(MAKEJL) --vet --test

# Alias for the combined vet+test verification baseline.
check: test

# Build, then run repository analysis through the verification gate.
vet: $(CONFIGURE_STAMP)
	$(MAKEJL) --vet

# Build a custom Julia sysimage beside the application.
sysimage: $(CONFIGURE_STAMP)
	$(MAKEJL) --sysimage

# Build and run the headless semantic trace harness.
harness: $(CONFIGURE_STAMP)
	$(MAKEJL) --harness

# Generate the publishable Wiki artifact in bin/wiki.
wiki: $(CONFIGURE_STAMP)
	$(MAKEJL) --wiki

# Compare bin/wiki with a fresh generation without modifying it.
check-wiki: $(CONFIGURE_STAMP)
	$(MAKEJL) --check-wiki

# Delete generated build artifacts and the configure stamp.
clean:
	$(MAKEJL) --clean
	@rm -f $(CONFIGURE_STAMP)

# Show the underlying make.jl help.
help:
	$(MAKEJL) --help
