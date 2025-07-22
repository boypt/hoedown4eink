#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e
SCRIPTDIR=$(dirname "$(readlink -f "$0")")
OUTPUTDIR="$SCRIPTDIR/OUTPUT"
BUILDDIR="$SCRIPTDIR/BUILD"
[[ -d $OUTPUTDIR ]] || rm -rf $OUTPUTDIR
[[ -d $BUILDDIR ]] || rm -rf $BUILDDIR
mkdir -p $OUTPUTDIR $BUILDDIR

# Function to build hoedown
build_hoedown() {

    local TOOLCHIAN_PREFIX=${TOOLCHAIN_PREFIX:-""}
    cd $BUILDDIR
    echo "Cloning hoedown repository..."
    git clone --depth 1 https://github.com/hoedown/hoedown.git
    cd hoedown

    echo "Building hoedown..."
    make clean
    make CC="${TOOLCHIAN_PREFIX}gcc"

    echo "Stripping libhoedown.so.3..."
    ${TOOLCHIAN_PREFIX}strip libhoedown.so.3

    mkdir -p "$OUTPUTDIR/lib/"
    install -m644 libhoedown.so.3 "$OUTPUTDIR/lib/"
}

# Function to check out lua-resty-hoedown
checkout_lua_resty_hoedown() {
    cd "$SCRIPTDIR"
    echo "Cloning lua-resty-hoedown repository..."
    git clone --depth 1 https://github.com/bungle/lua-resty-hoedown.git
    cd lua-resty-hoedown
    tar c lib | tar x -C ../OUTPUT
}

# Function to package the libraries and binary
package_files() {
    cd "$SCRIPTDIR"
    echo "Packaging files into tar.gz..."

    cd OUTPUT
    local PACKAGETAG=
    [[ -n $TOOLCHIAN_PREFIX ]] &&
        PACKAGETAG=$(echo $TOOLCHIAN_PREFIX | cut -d- -f2)
    [[ -z $TOOLCHIAN_PREFIX ]] && PACKAGETAG="$(uname -m)"
    tar -czvf ../lua-hoedown_${PACKAGETAG}.tgz .
}

# Main script execution
build_hoedown
checkout_lua_resty_hoedown
package_files

echo "Build and packaging completed successfully."
