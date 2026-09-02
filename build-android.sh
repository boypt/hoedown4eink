#!/bin/bash
set -e

SCRIPTDIR=$(dirname "$(readlink -f "$0")")
HOEDOWN_SRC="$SCRIPTDIR/hoedown"

# NDK 路径处理: 兼容 Docker 镜像与本地多种安装位置
# Docker 镜像 liasoft/antispy-build-android:ndk-r23c 设置 ANDROID_NDK=/usr/local/android/android-ndk-r23c
# 且 ANDROID_NDK_ROOT=/usr/local/android；而旧逻辑仅处理 ANDROID_NDK_ROOT 故会拼接出不存在的路径
if [[ -n $ANDROID_NDK ]]; then
  ANDROID_NDK_HOME=$ANDROID_NDK
elif [[ -n $ANDROID_NDK_ROOT ]]; then
  ANDROID_NDK_HOME=$ANDROID_NDK_ROOT/android-ndk-r23c
else
  ANDROID_NDK_HOME=/opt/android-ndk-r23c/android-ndk-r23c
fi
export ANDROID_NDK_HOME

# 确保工具链在 PATH 中：优先使用 ANDROID_NDK_HOME 下的 llvm/prebuilt，若不存在则回退到 ANDROID_NDK
if [ -d "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin" ]; then
  export PATH="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH"
elif [ -n "$ANDROID_NDK" ] && [ -d "$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin" ]; then
  export PATH="$ANDROID_NDK/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH"
  # 同步 ANDROID_NDK_HOME 以保持一致
  ANDROID_NDK_HOME="$ANDROID_NDK"
  export ANDROID_NDK_HOME
else
  # 默认追加，缺失时后续依赖检查会给出清晰错误
  export PATH="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin:$PATH"
fi

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
  echo "Unsupported ARCH: $ARCH" >&2
  echo "Supported: armeabi-v7a, arm64-v8a" >&2
  exit 1
fi

export CC="$TRIPLE$API-clang"
export CXX="$TRIPLE$API-clang++"
export AR=llvm-ar
export RANLIB=llvm-ranlib
export STRIP=llvm-strip

# 依赖检查：确保关键工具存在，失败时给出明确提示
for cmd in make "$CC" "$AR" "$RANLIB" "$STRIP"; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Error: required command '$cmd' not found" >&2
    echo "  ANDROID_NDK_HOME=$ANDROID_NDK_HOME" >&2
    echo "  PATH=$PATH" >&2
    if [ "$cmd" = "$CC" ]; then
      echo "  Hint: check NDK installation and API level (API $API for $ARCH)" >&2
    fi
    exit 1
  fi
done
# llvm-readelf 可选，仅用于验证，不强制要求
if ! command -v llvm-readelf >/dev/null 2>&1 && ! command -v readelf >/dev/null 2>&1; then
  echo "Warning: neither llvm-readelf nor readelf found, skipping ELF verification" >&2
fi

# CFLAGS 优化：去除 -g，使用 -Os 优化体积，开启 sections 隔离以便 gc-sections 裁减
# NOTE: 移除 -fvisibility=hidden — hoedown 无 visibility 标注，hidden 会使全部 hoedown_* 不进 .dynsym，
# 配合 --gc-sections 会被 LLD 当作无用段裁掉，得到 2.5K 空壳库（验证：dynsym 2个，无 hoedown_*）。
export CFLAGS="-Os -pipe -fomit-frame-pointer -fPIC -std=gnu11 -ffunction-sections -fdata-sections -Isrc"

# LDFLAGS 优化：加入 -Wl,-s 在链接时丢弃符号，确保 --gc-sections 生效
export LDFLAGS="-shared -Wl,-soname,libhoedown.so.3 -Wl,--as-needed,--gc-sections -Wl,-s -no-canonical-prefixes $EXTRA_LDFLAGS"

echo "=== Building for $ARCH (API $API) ==="
echo "  ANDROID_NDK_HOME=$ANDROID_NDK_HOME"
echo "  CC=$CC"
echo "  CFLAGS=$CFLAGS"
echo "  LDFLAGS=$LDFLAGS"

# 解析 hoedown 源码位置，脚本可在仓库根目录直接运行
# Makefile 位于 hoedown/ 子目录（由 build_hoedown.sh 克隆或手动 git clone），而非仓库根目录
if [ ! -d "$HOEDOWN_SRC" ]; then
  if [ -d "$SCRIPTDIR/BUILD/hoedown" ]; then
    HOEDOWN_SRC="$SCRIPTDIR/BUILD/hoedown"
    echo "Found hoedown source at BUILD/hoedown, using $HOEDOWN_SRC"
  else
    echo "hoedown source not found at $SCRIPTDIR/hoedown, cloning..."
    if ! command -v git >/dev/null 2>&1; then
      echo "Error: git not found, cannot clone hoedown" >&2
      exit 1
    fi
    git clone --depth 1 https://github.com/hoedown/hoedown.git "$HOEDOWN_SRC"
    echo "Cloned hoedown to $HOEDOWN_SRC"
  fi
fi

if [ ! -f "$HOEDOWN_SRC/Makefile" ]; then
  echo "Error: Makefile not found in $HOEDOWN_SRC" >&2
  ls -la "$HOEDOWN_SRC" >&2 || true
  exit 1
fi

cd "$HOEDOWN_SRC"
echo "  HOEDOWN_SRC=$HOEDOWN_SRC (pwd: $(pwd))"

# 清理构建环境
make clean

# 编译共享库
make -j$(nproc 2>/dev/null || echo 4) \
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
# 额外验证：若存在 llvm-readelf/readelf 则打印动态符号与 ELF 信息，便于排查空壳库问题
if command -v llvm-readelf >/dev/null 2>&1; then
  echo "--- llvm-readelf --dyn-symbols (hoedown_*) ---"
  llvm-readelf --dyn-symbols libhoedown.so.3 | grep -E "hoedown|Num:" | head -n 50 || true
elif command -v readelf >/dev/null 2>&1; then
  echo "--- readelf --dyn-syms (hoedown_*) ---"
  readelf --dyn-syms libhoedown.so.3 | grep -E "hoedown|Num:" | head -n 50 || true
fi
