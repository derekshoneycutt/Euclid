#!/usr/bin/env bash
# Build the pinned compiler closure without graphics/audio development packages.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get -o APT::Sandbox::User=root update
apt-get -o APT::Sandbox::User=root install --yes --no-install-recommends \
    ca-certificates curl cmake ninja-build gcc g++ python3 git patchelf

if [[ ! -d /work/SDL3-3.4.16 ]]; then
    curl --fail --location --retry 3 \
        https://github.com/libsdl-org/SDL/releases/download/release-3.4.16/SDL3-3.4.16.tar.gz \
        --output /work/SDL3.tar.gz
    echo "7322236cd12090c3eb40b9728be4d49c76f66ad17d04369584d4ecad5cf77c68  /work/SDL3.tar.gz" |
        sha256sum --check
    tar --extract --gzip --file /work/SDL3.tar.gz --directory /work
fi

cmake -S /recipe -B /work/build-linux -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DSDL_SHARED=OFF -DSDL_STATIC=ON -DSDL_TESTS=OFF \
    -DSDL_INSTALL=OFF -DSDL_UNIX_CONSOLE_BUILD=ON \
    -DSDL_AUDIO=OFF -DSDL_VIDEO=OFF -DSDL_RENDER=OFF \
    -DSDL_JOYSTICK=OFF -DSDL_HAPTIC=OFF -DSDL_SENSOR=OFF -DSDL_CAMERA=OFF \
    -DSDL_DBUS=OFF -DSDL_IBUS=OFF -DSDL_LIBUDEV=OFF \
    -DSDLSHADERCROSS_VENDORED=ON -DSDLSHADERCROSS_SHARED=OFF \
    -DSDLSHADERCROSS_STATIC=ON -DSDLSHADERCROSS_CLI_STATIC=ON \
    -DSDLSHADERCROSS_SPIRVCROSS_SHARED=OFF \
    -DSDLSHADERCROSS_INSTALL=OFF -DSDLSHADERCROSS_TESTS=OFF \
    -DSPIRV_WERROR=OFF -DSPIRV_SKIP_TESTS=ON \
    -DLLVM_ENABLE_ZLIB=OFF -DLLVM_ENABLE_LIBXML2=OFF
cmake --build /work/build-linux --target shadercross spirv-val spirv-dis --parallel 1

mkdir -p /work/payload
cp /work/build-linux/shadercross/shadercross /work/payload/
cp /work/build-linux/shadercross/external/SPIRV-Tools/tools/spirv-val /work/payload/
cp /work/build-linux/shadercross/external/SPIRV-Tools/tools/spirv-dis /work/payload/
cp /work/build-linux/shadercross/external/DirectXShaderCompiler/lib/libdxcompiler.so /work/payload/
cp /work/build-linux/shadercross/external/DirectXShaderCompiler/lib/libdxil.so /work/payload/
for artifact in /work/payload/*; do
    strip "$artifact"
    patchelf --set-rpath '$ORIGIN' "$artifact"
done
dpkg-query --show > /work/build-packages.txt
/work/payload/spirv-val --version
/work/payload/shadercross --help
