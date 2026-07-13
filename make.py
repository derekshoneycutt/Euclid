#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
import platform
import shutil
import subprocess
import sys
import tarfile
import uuid
from datetime import datetime, timezone
from pathlib import Path
from textwrap import dedent


SCRIPT_DIR = Path(__file__).resolve().parent
SRC_DIR = SCRIPT_DIR / "src"
BIN_DIR = SCRIPT_DIR / "bin"
ASSETS_STAGING_DIR = BIN_DIR / ".assets_staging"
ASSETS_ARCHIVE_PATH = BIN_DIR / "assets.pkg"


def is_windows() -> bool:
    return platform.system() == "Windows"


def app_binary_path() -> Path:
    return BIN_DIR / ("euclid.exe" if is_windows() else "euclid")


def require_command(command_name: str, install_hint: str) -> None:
    if shutil.which(command_name) is None:
        raise RuntimeError(
            f"Error: {command_name} is required but not installed or not on PATH.\n"
            f"{install_hint}"
        )


def run_command(
    command: list[str],
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
    capture_output: bool = False) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=str(cwd) if cwd else None,
        env=env,
        text=True,
        capture_output=capture_output,
        check=False,
    )


def run_shell_command(
    command: str,
    cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=str(cwd) if cwd else None,
        shell=True,
        text=True,
        capture_output=True,
        check=False,
    )


def show_help() -> str:
        return dedent(
                """\
                Usage: ./make.py [options]

                Options:
                    --build, -b         Build the project.
                    --assets, -a        Build assets.pkg.
                    --clean, -c         Delete generated build artifacts.
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
                """
        )


def parse_args(argv: list[str]) -> tuple[argparse.Namespace, list[str]]:
    run_args: list[str] = []
    cli_args = argv
    if "--" in argv:
        split_index = argv.index("--")
        cli_args = argv[:split_index]
        run_args = argv[split_index + 1 :]

    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--run", "-r", action="store_true")
    parser.add_argument("--build", "-b", action="store_true")
    parser.add_argument("--assets", "-a", action="store_true")
    parser.add_argument("--clean", "-c", action="store_true")
    parser.add_argument("--vet", "-v", action="store_true")
    parser.add_argument("--fail-lizard", "-f", action="store_true")
    parser.add_argument("--no-build", "-n", action="store_true")
    parser.add_argument("--no-assets", "-x", action="store_true")
    parser.add_argument("--help", "-h", action="store_true")

    args, unknown = parser.parse_known_args(cli_args)
    if unknown:
        raise ValueError("Unsupported parameter provided.")

    if run_args and not args.run:
        raise ValueError("Run arguments after -- are only valid with --run.")

    return args, run_args


def get_vswhere_path() -> Path:
    program_files_x86 = os.environ.get("ProgramFiles(x86)")
    if not program_files_x86:
        raise RuntimeError("Error: ProgramFiles(x86) environment variable is missing.")

    vswhere_path = Path(program_files_x86) / "Microsoft Visual Studio/Installer/vswhere.exe"
    if not vswhere_path.exists():
        raise RuntimeError("Error: Could not locate vswhere.exe. Install Visual Studio Build Tools.")

    return vswhere_path


def resolve_msvc_tool_path(find_glob: str, error_message: str) -> Path:
    vswhere_path = get_vswhere_path()
    result = run_command(
        [
            str(vswhere_path),
            "-latest",
            "-products",
            "*",
            "-requires",
            "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
            "-find",
            find_glob,
        ],
        capture_output=True,
    )

    candidate = result.stdout.strip().splitlines()
    if result.returncode != 0 or not candidate:
        raise RuntimeError(error_message)

    path = Path(candidate[0].strip())
    if not path.exists():
        raise RuntimeError(error_message)

    return path


def new_import_library(
    dll_path: Path,
    def_path: Path,
    out_lib_path: Path,
    dll_name: str,
    lib_exe_path: Path,
    strip_data_markers: bool = False) -> None:
    needs_rebuild = not out_lib_path.exists()
    if not needs_rebuild and dll_path.stat().st_mtime > out_lib_path.stat().st_mtime:
        needs_rebuild = True

    if not needs_rebuild:
        return

    def_path.parent.mkdir(parents=True, exist_ok=True)

    gendef_result = run_command(["gendef", str(dll_path)], cwd=def_path.parent)
    if gendef_result.returncode != 0 or not def_path.exists():
        raise RuntimeError(f"Error: Failed to generate DEF file for {dll_name}")

    if strip_data_markers:
        lines = def_path.read_text(encoding="utf-8", errors="ignore").splitlines()
        normalized = [line.removesuffix(" DATA") for line in lines]
        def_path.write_text("\n".join(normalized) + "\n", encoding="ascii")

    lib_result = run_command(
        [
            str(lib_exe_path),
            f"/def:{def_path}",
            "/machine:x64",
            f"/name:{dll_name}",
            f"/out:{out_lib_path}",
        ],
        cwd=def_path.parent,
    )
    if lib_result.returncode != 0 or not out_lib_path.exists():
        raise RuntimeError(f"Error: Failed to generate import library for {dll_name}")


def parse_ldd_runtime_libs(output: str) -> list[str]:
    libs: list[str] = []
    for raw_line in output.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        lib_name = line.split()[0]
        if lib_name and lib_name != "statically":
            libs.append(lib_name)
    return list(dict.fromkeys(libs))


def parse_otool_runtime_libs(output: str) -> list[str]:
    libs: list[str] = []
    for index, raw_line in enumerate(output.splitlines()):
        if index == 0:
            continue
        line = raw_line.strip()
        if not line:
            continue
        libs.append(line.split()[0])
    return list(dict.fromkeys(libs))


def parse_dumpbin_runtime_libs(output: str) -> list[str]:
    libs: list[str] = []
    in_dependencies = False
    for raw_line in output.splitlines():
        line = raw_line.strip()
        if "Image has the following dependencies" in line:
            in_dependencies = True
            continue
        if not in_dependencies:
            continue
        if not line:
            continue
        if line == "Summary":
            break
        libs.append(line)
    return list(dict.fromkeys(libs))


def collect_linux_runtime_libs(binary_path: Path) -> list[str]:
    if shutil.which("ldd") is None:
        return []

    result = run_command(["ldd", str(binary_path)], capture_output=True)
    return parse_ldd_runtime_libs(result.stdout)


def collect_macos_runtime_libs(binary_path: Path) -> list[str]:
    if shutil.which("otool") is None:
        return []

    result = run_command(["otool", "-L", str(binary_path)], capture_output=True)
    return parse_otool_runtime_libs(result.stdout)


def collect_windows_runtime_libs(binary_path: Path) -> list[str]:
    dumpbin_path = resolve_msvc_tool_path(
        "VC/Tools/MSVC/**/bin/Hostx64/x64/dumpbin.exe",
        "Error: Could not locate MSVC dumpbin.exe. Install the C++ Build Tools workload.",
    )
    result = run_command([str(dumpbin_path), "/dependents", str(binary_path)], capture_output=True)
    if result.returncode != 0:
        return []

    return parse_dumpbin_runtime_libs(result.stdout)


def collect_runtime_libs(binary_path: Path) -> list[str]:
    os_name = platform.system()

    if os_name == "Linux":
        return collect_linux_runtime_libs(binary_path)

    if os_name == "Darwin":
        return collect_macos_runtime_libs(binary_path)

    if os_name == "Windows":
        return collect_windows_runtime_libs(binary_path)

    return []


def collect_julia_packages(julia_project_dir: Path) -> list[tuple[str, str]]:
    if shutil.which("julia") is None:
        return []

    snippet = (
        "using Pkg; "
        "deps = collect(values(Pkg.dependencies())); "
        "direct = filter(d -> d.is_direct_dep, deps); "
        "sort!(direct, by = d -> lowercase(d.name)); "
        "for d in direct; "
        "version = isnothing(d.version) ? \"stdlib\" : string(d.version); "
        "println(d.name, \"|\", version); "
        "end"
    )
    result = run_command(
        ["julia", f"--project={julia_project_dir}", "-e", snippet],
        capture_output=True,
    )
    if result.returncode != 0:
        return []

    packages: list[tuple[str, str]] = []
    seen: set[str] = set()
    for line in result.stdout.splitlines():
        entry = line.strip()
        if not entry or "|" not in entry:
            continue
        name, version = entry.split("|", 1)
        name = name.strip()
        version = version.strip()
        if not name:
            continue
        key = f"{name}|{version}"
        if key in seen:
            continue
        seen.add(key)
        packages.append((name, version))

    return packages


def write_runtime_sbom(
    binary_path: Path,
    assets_path: Path,
    output_path: Path,
    julia_project_dir: Path) -> None:
    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    serial_uuid = "00000000-0000-0000-0000-000000000000"
    if shutil.which("julia") is not None:
        result = run_command(
            ["julia", "-e", "using UUIDs; print(uuid4())"],
            capture_output=True,
        )
        if result.returncode == 0 and result.stdout.strip():
            serial_uuid = result.stdout.strip()
    else:
        serial_uuid = str(uuid.uuid4())

    runtime_libs = collect_runtime_libs(binary_path)
    julia_packages = collect_julia_packages(julia_project_dir)

    binary_name = "bin/euclid.exe" if is_windows() else "bin/euclid"

    components: list[dict[str, object]] = [
        {
            "type": "file",
            "bom-ref": f"file:{binary_name}",
            "name": binary_name,
            "version": "dev",
            "scope": "required",
        },
        {
            "type": "file",
            "bom-ref": "file:bin/assets.pkg",
            "name": "bin/assets.pkg",
            "version": "dev",
            "scope": "required",
        },
    ]

    for lib in runtime_libs:
        components.append(
            {
                "type": "library",
                "bom-ref": f"runtime:{lib}",
                "name": lib,
                "version": "unknown",
                "scope": "required",
            }
        )

    for name, version in julia_packages:
        components.append(
            {
                "type": "library",
                "bom-ref": f"pkg:julia/{name}",
                "name": name,
                "version": version,
                "scope": "required",
            }
        )

    depends_on = [f"file:{binary_name}", "file:bin/assets.pkg"]
    depends_on.extend(f"runtime:{lib}" for lib in runtime_libs)
    depends_on.extend(f"pkg:julia/{name}" for name, _ in julia_packages)

    bom = {
        "$schema": "http://cyclonedx.org/schema/bom-1.6.schema.json",
        "bomFormat": "CycloneDX",
        "specVersion": "1.6",
        "serialNumber": f"urn:uuid:{serial_uuid}",
        "version": 1,
        "metadata": {
            "timestamp": timestamp,
            "component": {
                "type": "application",
                "bom-ref": "app:euclid",
                "name": "EuclidApp",
                "version": "dev",
            },
        },
        "components": components,
        "dependencies": [
            {
                "ref": "app:euclid",
                "dependsOn": depends_on,
            }
        ],
    }

    output_path.write_text(json.dumps(bom, indent=2) + "\n", encoding="ascii")


def build_odin(do_vet: bool, julia_linker_flags: str) -> None:
    print("Building Odin...")

    cmd = ["odin", "build", "main.odin", "-file", "-out:../bin/euclid"]
    if is_windows():
        cmd[-1] = "-out:../bin/euclid.exe"
    if julia_linker_flags:
        cmd.append(f"-extra-linker-flags:{julia_linker_flags}")
    if do_vet:
        cmd.extend(["-vet", "-strict-style", "-disallow-do", "-warnings-as-errors"])

    build_result = run_command(cmd, cwd=SRC_DIR)
    if do_vet:
        print(f"Odin build exited {build_result.returncode}")
    else:
        print(f"Build exited {build_result.returncode}")
    if build_result.returncode != 0:
        raise RuntimeError("Build failed.")

    if do_vet:
        print("Validating Julia...")
        validation_result = run_command(
            ["julia", "-e", 'Meta.parseall(read("julia/script.jl", String))'],
            cwd=SRC_DIR,
        )
        print(f"Julia validation exited {validation_result.returncode}")
        if validation_result.returncode != 0:
            raise RuntimeError("Julia validation failed.")


def run_vet_analysis(fail_lizard: bool) -> None:
    if shutil.which("lizard") is None:
        print("Warning: lizard is not installed or not on PATH; skipping lizard analysis.")
        return

    had_findings = False

    print("Running lizard analysis (python)...")
    python_result = run_command(["lizard", "."], cwd=SCRIPT_DIR)
    print(f"Lizard python analysis exited {python_result.returncode}")
    if python_result.returncode != 0:
        had_findings = True
        print("Lizard python analysis reported warnings.")

    odin_files = sorted(str(path) for path in SRC_DIR.rglob("*.odin"))
    if odin_files:
        print("Running lizard analysis (odin)...")
        odin_result = run_command(["lizard", "-l", "cpp", *odin_files], cwd=SCRIPT_DIR)
        print(f"Lizard odin analysis exited {odin_result.returncode}")
        if odin_result.returncode != 0:
            had_findings = True
            print("Lizard odin analysis reported warnings.")

    julia_root = SRC_DIR / "julia"
    julia_files = sorted(str(path) for path in julia_root.rglob("*.jl"))
    if julia_files:
        print("Running lizard analysis (julia)...")
        julia_result = run_command(["lizard", "-l", "ruby", *julia_files], cwd=SCRIPT_DIR)
        print(f"Lizard julia analysis exited {julia_result.returncode}")
        if julia_result.returncode != 0:
            had_findings = True
            print("Lizard julia analysis reported warnings.")

    if fail_lizard and had_findings:
        raise RuntimeError("Lizard analysis reported warnings and --fail-lizard is enabled.")


def build_assets(do_build: bool) -> None:
    print("Building assets package...")

    package_init = run_command(
        [
            "julia",
            f"--project={SCRIPT_DIR / 'src/julia'}",
            "-e",
            "using Pkg; Pkg.instantiate(); Pkg.precompile()",
        ]
    )
    print(f"Julia package init exited {package_init.returncode}")
    if package_init.returncode != 0:
        raise RuntimeError("Julia package init failed.")

    if ASSETS_STAGING_DIR.exists():
        shutil.rmtree(ASSETS_STAGING_DIR)

    (ASSETS_STAGING_DIR / "julia").mkdir(parents=True, exist_ok=True)
    (ASSETS_STAGING_DIR / "shaders").mkdir(parents=True, exist_ok=True)

    shutil.copytree(SRC_DIR / "julia", ASSETS_STAGING_DIR / "julia", dirs_exist_ok=True)
    shutil.copytree(SRC_DIR / "view/shaders", ASSETS_STAGING_DIR / "shaders", dirs_exist_ok=True)
    shutil.copytree(SCRIPT_DIR / "assets", ASSETS_STAGING_DIR, dirs_exist_ok=True)

    (ASSETS_STAGING_DIR / "manifest.txt").write_text(
        "package=assets.pkg\n"
        "julia_root=julia\n"
        "shader_root=shaders\n"
        "format=tar.gz\n",
        encoding="ascii",
    )

    ASSETS_ARCHIVE_PATH.parent.mkdir(parents=True, exist_ok=True)
    assets_exit_code = 0
    try:
        with tarfile.open(ASSETS_ARCHIVE_PATH, "w:gz") as archive:
            for item in ASSETS_STAGING_DIR.rglob("*"):
                archive.add(item, arcname=item.relative_to(ASSETS_STAGING_DIR))
    except Exception:
        assets_exit_code = 1
    print(f"Assets package build exited {assets_exit_code}")

    if ASSETS_STAGING_DIR.exists():
        shutil.rmtree(ASSETS_STAGING_DIR)

    if assets_exit_code != 0:
        raise RuntimeError("Assets package build failed.")

    print(f"Wrote {ASSETS_ARCHIVE_PATH}")

    if do_build:
        runtime_sbom_path = BIN_DIR / "runtime-closure.generated.cdx.json"
        write_runtime_sbom(
            app_binary_path(),
            ASSETS_ARCHIVE_PATH,
            runtime_sbom_path,
            SCRIPT_DIR / "src/julia",
        )
        print(f"Wrote {runtime_sbom_path}")


def resolve_julia_linker_flags(do_build: bool) -> tuple[str, str | None]:
    if not do_build:
        return "", None

    if not is_windows():
        julia_config = run_command(
            [
                "julia",
                "-e",
                'print(joinpath(Sys.BINDIR, Base.DATAROOTDIR, "julia", "julia-config.jl"))',
            ],
            capture_output=True,
        )
        if julia_config.returncode != 0:
            raise RuntimeError("Error: Could not resolve julia-config.jl path.")

        julia_config_path = julia_config.stdout.strip()
        flags_result = run_command([julia_config_path, "--ldflags", "--ldlibs"], capture_output=True)
        if flags_result.returncode != 0:
            raise RuntimeError("Error: Failed to query Julia linker flags.")
        return " ".join(flags_result.stdout.splitlines()).strip(), None

    julia_bindir_result = run_command(["julia", "-e", "print(Sys.BINDIR)"], capture_output=True)
    if julia_bindir_result.returncode != 0 or not julia_bindir_result.stdout.strip():
        raise RuntimeError("Error: Could not resolve Julia Sys.BINDIR.")

    julia_bindir = Path(julia_bindir_result.stdout.strip())
    libjulia_dll = julia_bindir / "libjulia.dll"
    libopenlibm_dll = julia_bindir / "libopenlibm.dll"
    if not libjulia_dll.exists():
        raise RuntimeError(f"Error: Missing Julia runtime DLL at {libjulia_dll}")
    if not libopenlibm_dll.exists():
        raise RuntimeError(f"Error: Missing Julia runtime DLL at {libopenlibm_dll}")

    import_lib_dir = BIN_DIR / ".julia_import_libs"
    import_lib_dir.mkdir(parents=True, exist_ok=True)

    lib_exe_path = resolve_msvc_tool_path(
        "VC/Tools/MSVC/**/bin/Hostx64/x64/lib.exe",
        "Error: Could not locate MSVC lib.exe. Install the C++ Build Tools workload.",
    )

    new_import_library(
        libjulia_dll,
        import_lib_dir / "libjulia.def",
        import_lib_dir / "julia.lib",
        "libjulia.dll",
        lib_exe_path,
        strip_data_markers=True,
    )
    new_import_library(
        libopenlibm_dll,
        import_lib_dir / "libopenlibm.def",
        import_lib_dir / "openlibm.lib",
        "libopenlibm.dll",
        lib_exe_path,
    )

    return f"/LIBPATH:{import_lib_dir} /DEFAULTLIB:julia.lib /DEFAULTLIB:openlibm.lib", str(julia_bindir)


def run_binary(run_args: list[str], julia_bindir: str | None) -> None:
    binary = app_binary_path()
    if not binary.exists():
        raise RuntimeError("Error: Built binary not found in bin/.")

    env = dict(os.environ)
    if is_windows() and julia_bindir:
        env["PATH"] = f"{julia_bindir};{env.get('PATH', '')}"

    result = run_command([str(binary), *run_args], cwd=BIN_DIR, env=env)
    if result.returncode != 0:
        raise RuntimeError("Run step failed.")


def clean_build_files() -> None:
    targets: list[Path] = [
        app_binary_path(),
        ASSETS_ARCHIVE_PATH,
        BIN_DIR / "runtime-closure.generated.cdx.json",
        BIN_DIR / "libeuclid.so",
        BIN_DIR / "libeuclid.dll",
        BIN_DIR / "libeuclid.dylib",
        BIN_DIR / "build",
        ASSETS_STAGING_DIR,
        BIN_DIR / ".julia_import_libs",
        SCRIPT_DIR / "__pycache__",
    ]

    removed: list[str] = []
    for target in targets:
        if not target.exists():
            continue

        if target.is_dir():
            shutil.rmtree(target)
        else:
            target.unlink()

        removed.append(str(target.relative_to(SCRIPT_DIR)))

    if removed:
        print("Cleaned build artifacts:")
        for item in removed:
            print(f"  - {item}")
    else:
        print("No build artifacts found to clean.")


def explicit_action_requested(args: argparse.Namespace) -> bool:
    return any(
        [
            args.run,
            args.build,
            args.assets,
            args.vet,
            args.no_build,
            args.no_assets,
        ]
    )


def resolve_build_plan(args: argparse.Namespace) -> tuple[bool, bool, bool]:
    do_build = True
    do_vet = False
    do_assets = True

    if args.no_build:
        do_build = False
        do_vet = False
    elif args.vet:
        do_build = True
        do_vet = True
    elif args.build:
        do_build = True
        do_vet = False

    if args.no_assets:
        do_assets = False
    elif args.assets:
        do_assets = True

    if args.assets and not args.build and not args.vet and not args.no_build:
        do_build = False

    return do_build, do_vet, do_assets


def ensure_required_commands(do_build: bool, do_assets: bool) -> None:
    if do_build:
        require_command("julia", "Please install Julia to continue.")
        require_command("odin", "Please install Odin to continue.")

    if do_assets:
        require_command("julia", "Please install Julia to continue.")

    if do_build and is_windows():
        require_command(
            "gendef",
            "Install gendef (for example via Strawberry Perl or MSYS2) to generate import libraries.",
        )


def execute_build_plan(
    do_build: bool,
    do_vet: bool,
    do_assets: bool,
    fail_lizard: bool,
    run_after_build: bool,
    run_args: list[str]) -> None:
    julia_flags, julia_bindir = resolve_julia_linker_flags(do_build)

    if do_build:
        build_odin(do_vet, julia_flags)

    if do_vet:
        run_vet_analysis(fail_lizard)

    if do_assets:
        build_assets(do_build)

    if run_after_build:
        run_binary(run_args, julia_bindir)


def main() -> int:
    try:
        args, run_args = parse_args(sys.argv[1:])
    except ValueError as exc:
        print(str(exc), file=sys.stderr)
        print(show_help(), end="", file=sys.stderr)
        return 1

    if args.help:
        print(show_help(), end="")
        return 0

    run_after_build = args.run
    has_explicit_action = explicit_action_requested(args)

    if args.clean:
        clean_build_files()
        if not has_explicit_action:
            return 0

    do_build, do_vet, do_assets = resolve_build_plan(args)

    try:
        ensure_required_commands(do_build, do_assets)
        execute_build_plan(
            do_build,
            do_vet,
            do_assets,
            args.fail_lizard,
            run_after_build,
            run_args,
        )

        return 0
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
