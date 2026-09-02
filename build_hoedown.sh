#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e
set -o pipefail
SCRIPTDIR=$(dirname "$(readlink -f "$0")")
OUTPUTDIR="$SCRIPTDIR/OUTPUT"
BUILDDIR="$SCRIPTDIR/BUILD"
rm -rf "$OUTPUTDIR" "$BUILDDIR"
mkdir -p "$OUTPUTDIR" "$BUILDDIR"

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

    cd "$BUILDDIR"
    echo "Cloning hoedown repository..."
    if [[ -d hoedown ]]; then
        echo "Updating existing hoedown checkout..."
        cd hoedown
        git fetch --depth 1 origin && git reset --hard origin/master
    else
        git clone --depth 1 https://github.com/hoedown/hoedown.git
        cd hoedown
    fi

    echo "Building hoedown..."
    make clean
    make CC="${TOOLCHAIN_PREFIX}gcc"

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
