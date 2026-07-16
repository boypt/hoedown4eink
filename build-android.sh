#!/bin/bash
set -e
export ANDROID_NDK_HOME=${ANDROID_NDK_ROOT:-}/android-ndk-r23c


ARCH=${1:-armeabi-v7a}   # 或 arm64-v8a
NDK=${ANDROID_NDK_HOME:-/opt/android-ndk-r23c}

if [ "$ARCH" = "armeabi-v7a" ]; then
  API=18
  TRIPLE=armv7a-linux-androideabi
  EXTRA_LDFLAGS="-Wl,--fix-cortex-a8 -march=armv7-a"
elif [ "$ARCH" = "arm64-v8a" ]; then
  API=21
  TRIPLE=aarch64-linux-android
  EXTRA_LDFLAGS=""
else
  echo "Unsupported ARCH: $ARCH"
  exit 1
fi

export CC="$TRIPLE$API-clang"
export CXX="$TRIPLE$API-clang++"
export AR=llvm-ar
export RANLIB=llvm-ranlib
export STRIP=llvm-strip

export CFLAGS="-O2 -g -pipe -fomit-frame-pointer -fPIC -std=gnu11 -fvisibility=hidden -Isrc"
export LDFLAGS="-shared -Wl,-soname,libhoedown.so -Wl,--as-needed,--gc-sections -no-canonical-prefixes $EXTRA_LDFLAGS"

echo "=== Building for $ARCH (API $API) ==="

make clean

make -j$(nproc) \
  CC="$CC" \
  AR="$AR" \
  RANLIB="$RANLIB" \
  CFLAGS="$CFLAGS" \
  LDFLAGS="$LDFLAGS" \
  libhoedown.so.3

echo "=== Build completed: libhoedown.so.3 for $ARCH ==="
ls -lh libhoedown.so.3
file libhoedown.so.3
