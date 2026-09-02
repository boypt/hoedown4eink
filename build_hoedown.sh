#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e
set -o pipefail
SCRIPTDIR=$(dirname "$(readlink -f "$0")")
OUTPUTDIR="$SCRIPTDIR/OUTPUT"
# 源码树持久化在 $SCRIPTDIR/hoedown（gitignored），多架构循环共用：
# 首次缺失才 clone，之后每次只 make clean + 重新 make，避免每个架构各 clone 一次
HOEDOWN_SRC="$SCRIPTDIR/hoedown"
rm -rf "$OUTPUTDIR"
mkdir -p "$OUTPUTDIR"

# Dependency checks: verify required commands exist
for cmd in make strip tar git; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: required command '$cmd' not found" >&2
        exit 1
    fi
done

# Function to build hoedown
build_hoedown() {

    local LIBOBJ="libhoedown.so.3"
    [[ -z $TOOLCHAIN_PREFIX ]] && TOOLCHAIN_PREFIX=""

    if [[ ! -d "$HOEDOWN_SRC" ]]; then
        echo "Cloning hoedown repository to $HOEDOWN_SRC (reused across arch builds)..."
        git clone --depth 1 https://github.com/hoedown/hoedown.git "$HOEDOWN_SRC"
    fi
    cd "$HOEDOWN_SRC"

    echo "Building hoedown (make clean for arch ${TOOLCHAIN_PREFIX:-native})..."
    make clean
    # size-优先参数（与 build-android.sh 一致）；切勿加 -fvisibility=hidden
    # （hoedown 无 visibility 标注，hidden+--gc-sections 会裁成 2.5K 空壳，见 AGENTS.md）
    make CC="${TOOLCHAIN_PREFIX}gcc" \
        CFLAGS="-Os -pipe -fomit-frame-pointer -fPIC -std=gnu11 -ffunction-sections -fdata-sections" \
        LDFLAGS="-shared -Wl,-soname,libhoedown.so.3 -Wl,--as-needed,--gc-sections -Wl,-s" \
        libhoedown.so.3

    echo "Stripping $LIBOBJ..."
    ${TOOLCHAIN_PREFIX}strip $LIBOBJ

    mkdir -p "$OUTPUTDIR/lib/"
    install -m644 $LIBOBJ "$OUTPUTDIR/lib/"
}

# Function to package the libraries and binary
package_files() {
    cd "$SCRIPTDIR"
    echo "Packaging files into tar.gz..."

    cd OUTPUT
    local PACKAGETAG=
    [[ -n $TOOLCHAIN_PREFIX ]] &&
        PACKAGETAG=$(echo $TOOLCHAIN_PREFIX | cut -d- -f2)
    [[ -z $TOOLCHAIN_PREFIX ]] && PACKAGETAG="$(uname -m)"
    tar -czvf ../lua-hoedown_${PACKAGETAG}.tgz .
}

# Main script execution
ARG1=${1:-}
if [[ -n $ARG1 ]]; then
    if command -v ${ARG1}-gcc >/dev/null 2>&1; then
        export TOOLCHAIN_PREFIX=${ARG1}-
    else
        echo "Warning: ${ARG1}-gcc not found, falling back to native gcc" >&2
        TOOLCHAIN_PREFIX=""
    fi
fi

build_hoedown
package_files

echo "Build and packaging completed successfully. ${TOOLCHAIN_PREFIX:-}"
