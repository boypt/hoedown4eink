#!/bin/bash
set -e

export ANDROID_NDK_HOME=${ANDROID_NDK_ROOT:-/opt/android-ndk-r23c}/android-ndk-r23c
export PATH=$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH

# ==================== 配置 ====================
ARCH=${1:-armeabi-v7a}   # 或 arm64-v8a
NDK=$ANDROID_NDK_HOME

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

# CFLAGS 优化：去除 -g，使用 -Os 优化体积，开启 sections 隔离以便 gc-sections 裁减
export CFLAGS="-Os -pipe -fomit-frame-pointer -fPIC -std=gnu11 -fvisibility=hidden -ffunction-sections -fdata-sections -Isrc"

# LDFLAGS 优化：加入 -Wl,-s 在链接时丢弃符号，确保 --gc-sections 生效
export LDFLAGS="-shared -Wl,-soname,libhoedown.so.3 -Wl,--as-needed,--gc-sections -Wl,-s -no-canonical-prefixes $EXTRA_LDFLAGS"

echo "=== Building for $ARCH (API $API) ==="

# 清理构建环境
make clean

# 编译共享库
make -j$(nproc) \
  CC="$CC" \
  AR="$AR" \
  RANLIB="$RANLIB" \
  CFLAGS="$CFLAGS" \
  LDFLAGS="$LDFLAGS" \
  libhoedown.so.3

# 执行可执行文件/动态库剥离，剥离非必要符号
$STRIP --strip-unneeded libhoedown.so.3

echo "=== Build completed: libhoedown.so.3 for $ARCH ==="
ls -lh libhoedown.so.3
file libhoedown.so.3
