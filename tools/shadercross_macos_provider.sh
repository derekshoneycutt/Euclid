#!/usr/bin/env bash
# Build the pinned arm64 compiler closure without Homebrew runtime dependencies.
set -euo pipefail

if [[ "$(uname -s)" != Darwin || "$(uname -m)" != arm64 ]]; then
    echo "macOS shadercross binary production requires an Apple Silicon host." >&2
    exit 1
fi
repository=$(cd "$(dirname "$0")/.." && pwd)
source "$repository/tools/shadercross_provider_source.sh"
work="$repository/.build/shadercross-macos-provider"
mkdir -p "$work"
if [[ ! -d "$work/SDL3-3.4.16" ]]; then
    curl --fail --location --retry 3 \
        https://github.com/libsdl-org/SDL/releases/download/release-3.4.16/SDL3-3.4.16.tar.gz \
        --output "$work/SDL3.tar.gz"
    echo "7322236cd12090c3eb40b9728be4d49c76f66ad17d04369584d4ecad5cf77c68  $work/SDL3.tar.gz" |
        shasum --algorithm 256 --check
    tar --extract --gzip --file "$work/SDL3.tar.gz" --directory "$work"
fi

cmake -S "$repository/tools/shadercross_macos_build" -B "$work/build" -G Ninja \
    -DEUCLID_PROVIDER_SDL_SOURCE="$work/SDL3-3.4.16" \
    -DEUCLID_PROVIDER_SHADERCROSS_SOURCE="$source" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0 \
    -DSDL_SHARED=OFF -DSDL_STATIC=ON -DSDL_TESTS=OFF -DSDL_INSTALL=OFF \
    -DSDL_UNIX_CONSOLE_BUILD=ON \
    -DSDL_AUDIO=OFF -DSDL_VIDEO=OFF -DSDL_RENDER=OFF \
    -DSDL_JOYSTICK=OFF -DSDL_HAPTIC=OFF -DSDL_SENSOR=OFF -DSDL_CAMERA=OFF \
    -DSDLSHADERCROSS_VENDORED=ON -DSDLSHADERCROSS_SHARED=OFF \
    -DSDLSHADERCROSS_STATIC=ON -DSDLSHADERCROSS_CLI_STATIC=ON \
    -DSDLSHADERCROSS_SPIRVCROSS_SHARED=OFF \
    -DSDLSHADERCROSS_CLI=ON -DSDLSHADERCROSS_DXC=ON \
    -DSDLSHADERCROSS_INSTALL=OFF -DSDLSHADERCROSS_TESTS=OFF \
    -DSPIRV_WERROR=OFF -DSPIRV_SKIP_TESTS=ON \
    -DLLVM_ENABLE_ZLIB=OFF -DLLVM_ENABLE_LIBXML2=OFF
cmake --build "$work/build" --target shadercross spirv-val spirv-dis --parallel 4

mkdir -p "$work/payload"
cp "$work/build/shadercross/shadercross" "$work/payload/"
cp "$work/build/shadercross/external/SPIRV-Tools/tools/spirv-val" "$work/payload/"
cp "$work/build/shadercross/external/SPIRV-Tools/tools/spirv-dis" "$work/payload/"
cp "$work/build/shadercross/external/DirectXShaderCompiler/lib/libdxcompiler.dylib" "$work/payload/"
cp "$work/build/shadercross/external/DirectXShaderCompiler/lib/libdxil.dylib" "$work/payload/"
for library in libdxcompiler.dylib libdxil.dylib; do
    install_name_tool -id "@loader_path/$library" "$work/payload/$library"
done
for artifact in shadercross spirv-val spirv-dis libdxcompiler.dylib libdxil.dylib; do
    path="$work/payload/$artifact"
    while read -r rpath; do
        install_name_tool -delete_rpath "$rpath" "$path"
    done < <(otool -l "$path" | awk '/cmd LC_RPATH/{getline; getline; print $2}')
    while read -r dependency; do
        case "$dependency" in
            /usr/lib/*|/System/Library/*|@loader_path/*) ;;
            *)
                library=$(basename "$dependency")
                if [[ "$library" != libdxcompiler.dylib && "$library" != libdxil.dylib ]]; then
                    echo "Unbundled dependency: $dependency in $artifact" >&2
                    exit 1
                fi
                install_name_tool -change "$dependency" "@loader_path/$library" "$path"
                ;;
        esac
    done < <(otool -L "$path" | tail -n +2 | awk '{print $1}')
    strip -x "$path"
    codesign --force --sign - "$path"
    [[ "$(lipo -archs "$path")" == arm64 ]]
    codesign --verify --strict "$path"
done
"$work/payload/spirv-val" --version
"$work/payload/spirv-dis" --version
"$work/payload/shadercross" --help
