#!/usr/bin/env bash
# Resolve a maintenance-only checkout, never used by application builds.
set -euo pipefail

repository=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
pin=$(sed -n 's/^source_commit = "\([0-9a-f]*\)"$/\1/p' \
    "$repository/libs/sdl_shadercross/source-pin.toml")
if [[ "$pin" != 1ff05bec573988a98ef9e0260b4da44f512b8367 ]]; then
    echo "Shadercross maintenance recipe does not match the repository source pin." >&2
    exit 1
fi
source="${EUCLID_SHADERCROSS_SOURCE:-$repository/.build/shadercross-source}"
if [[ ! -d "$source" ]]; then
    mkdir -p "$(dirname "$source")"
    git clone --no-checkout https://github.com/libsdl-org/SDL_shadercross.git "$source"
    git -C "$source" checkout --detach "$pin"
    git -C "$source" submodule update --init --recursive
fi
while read -r expected dependency; do
    actual=$(git -C "$source/$dependency" rev-parse HEAD)
    if [[ "$actual" != "$expected" ]] ||
        [[ -n "$(git -C "$source/$dependency" status --porcelain --untracked-files=no)" ]]; then
        echo "Unexpected or modified shadercross source: $source/$dependency" >&2
        exit 1
    fi
done <<'PINS'
1ff05bec573988a98ef9e0260b4da44f512b8367 .
1a6169566c73d3da552748fc372fe2bbb856e46e external/SPIRV-Cross
ad9184e76a66b1001c29db9b0a3e87f646c64de0 external/SPIRV-Headers
0539c81f69a3daeb706fd3477dca61435b475156 external/SPIRV-Tools
2c84a1c5ab7091608c97df6ba5ccf46e71c322eb external/DirectXShaderCompiler
980971e835876dc0cde415e8f9bc646e64667bf7 external/DirectXShaderCompiler/external/DirectX-Headers
04f10f650d514df88b76d25e83db360142c7b174 external/DirectXShaderCompiler/external/SPIRV-Headers
fbe4f3ad913c44fe8700545f8ffe35d1382b7093 external/DirectXShaderCompiler/external/SPIRV-Tools
PINS
