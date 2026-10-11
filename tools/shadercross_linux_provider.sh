#!/usr/bin/env bash
# Produce maintenance-only shader tools in an unprivileged Ubuntu 22.04 rootfs.
set -euo pipefail

repository=$(cd "$(dirname "$0")/.." && pwd)
work="$repository/.build/shadercross-linux-provider"
rootfs="$work/ubuntu"
mkdir -p "$work"

if [[ "$(uname -m)" != x86_64 ]]; then
    echo "Linux shadercross binary production requires an x86_64 host." >&2
    exit 1
fi
source "$repository/tools/shadercross_provider_source.sh"
if [[ "$(git -C "$source" rev-parse HEAD)" != 1ff05bec573988a98ef9e0260b4da44f512b8367 ]]; then
    echo "Linux shadercross production requires the pinned source commit." >&2
    exit 1
fi
if [[ ! -d "$rootfs" ]]; then
    curl --fail --location --retry 3 \
        https://cdimage.ubuntu.com/ubuntu-base/releases/22.04/release/ubuntu-base-22.04.5-base-amd64.tar.gz \
        --output "$work/ubuntu.tar.gz"
    echo "242cd8898b33ea806ef5f13b1076ed7c76f9f989d18384452f7166692438ff1a  $work/ubuntu.tar.gz" |
        sha256sum --check
    mkdir "$rootfs"
    tar --extract --gzip --file "$work/ubuntu.tar.gz" --directory "$rootfs"
fi
if [[ ! -d "$work/source" ]]; then
    git clone --local "$source" "$work/source"
    for dependency in external/SPIRV-Cross external/SPIRV-Headers \
        external/SPIRV-Tools external/DirectXShaderCompiler \
        external/DirectXShaderCompiler/external/DirectX-Headers \
        external/DirectXShaderCompiler/external/SPIRV-Headers \
        external/DirectXShaderCompiler/external/SPIRV-Tools; do
        git clone --local "$source/$dependency" "$work/source/$dependency"
    done
fi
for checkout in "$source" "$work/source"; do
    while read -r expected dependency; do
        actual=$(git -C "$checkout/$dependency" rev-parse HEAD)
        if [[ "$actual" != "$expected" ]] ||
            [[ -n "$(git -C "$checkout/$dependency" status --porcelain --untracked-files=no)" ]]; then
            echo "Unexpected or modified shadercross source: $checkout/$dependency" >&2
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
done

bwrap --unshare-user --uid 0 --gid 0 \
    --bind "$rootfs" / --proc /proc --dev /dev \
    --ro-bind /etc/resolv.conf /etc/resolv.conf \
    --bind "$work/source" /source --bind "$work" /work \
    --ro-bind "$repository/tools/shadercross_linux_build" /recipe \
    --chdir /work --setenv HOME /root --setenv LC_ALL C \
    /bin/bash /recipe/build.sh
