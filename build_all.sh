#!/bin/bash
set -e
set -o pipefail
SCRIPTDIR=$(dirname "$(readlink -f "$0")")
DIST="$SCRIPTDIR/dist"

# ========== usage ==========
usage() {
    cat <<'EOF'
Usage: ./build_all.sh [--arch <arch>] [--help]

  无参数: 一键构建全部 5 个 libhoedown.so.3 + resty (x86_64, kobo/armv7_hardfp, kindlepw2/armv7_softfp, android-armv7a, android-arm64)
  --arch:  仅构建单个架构
           可选值: x86_64 | kobo | kindlepw2 | android-armv7a | android-arm64
  --help:  显示此帮助

产物输出到 dist/:
  dist/x86_64/libhoedown.so.3
  dist/armv7_hardfp/libhoedown.so.3   (kobo)
  dist/armv7_softfp/libhoedown.so.3   (kindlepw2)
  dist/android_armv7a/libhoedown.so.3
  dist/android_arm64/libhoedown.so.3
  dist/resty/                         (lua-resty-hoedown 纯 Lua)

示例:
  ./build_all.sh
  ./build_all.sh --arch x86_64
  ./build_all.sh --arch kobo
  ./build_all.sh --arch android-arm64
EOF
}

# ========== 参数解析 ==========
ARCH_FILTER=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --arch)
            ARCH_FILTER="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

case "$ARCH_FILTER" in
    ""|x86_64|kobo|kindlepw2|android-armv7a|android-arm64) ;;
    *)
        echo "Error: --arch must be one of: x86_64, kobo, kindlepw2, android-armv7a, android-arm64" >&2
        exit 1
        ;;
esac

should_build() {
    local arch="$1"
    [[ -z "$ARCH_FILTER" ]] && return 0
    [[ "$ARCH_FILTER" == "$arch" ]] && return 0
    return 1
}

# ========== 依赖检查 ==========
# 基础依赖：tar, zstd, git, curl/wget
for cmd in tar git; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: required command '$cmd' not found" >&2
        exit 1
    fi
done
if ! command -v zstd >/dev/null 2>&1; then
    echo "Error: required command 'zstd' not found (needed for koxtoolchain .tar.zst)" >&2
    exit 1
fi
if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    echo "Error: neither 'curl' nor 'wget' found (needed to download koxtoolchain)" >&2
    exit 1
fi

# docker 仅在需要构建 Android 时强制检查
NEED_DOCKER=false
if [[ -z "$ARCH_FILTER" ]] || [[ "$ARCH_FILTER" == android-* ]]; then
    NEED_DOCKER=true
fi
if [[ "$NEED_DOCKER" == true ]] && ! command -v docker >/dev/null 2>&1; then
    echo "Error: required command 'docker' not found (needed for Android builds)" >&2
    exit 1
fi

# ========== 固定版本 ==========
KOX_VERSION="2026.08"
KOX_BASE_URL="https://github.com/koreader/koxtoolchain/releases/download/${KOX_VERSION}"
DOCKER_IMAGE="liasoft/antispy-build-android:ndk-r23c"
HOEDOWN_URL="https://github.com/hoedown/hoedown.git"
RESTY_URL="https://github.com/bungle/lua-resty-hoedown.git"

# ========== 工具函数 ==========
download_file() {
    local url="$1" dest="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -L -o "$dest" "$url"
    else
        wget -O "$dest" "$url"
    fi
}

# 确保 hoedown 源码存在 (幂等)
ensure_hoedown_src() {
    if [[ -d "$SCRIPTDIR/hoedown" && -f "$SCRIPTDIR/hoedown/Makefile" ]]; then
        echo "==> hoedown already exists at $SCRIPTDIR/hoedown, updating (fetch --depth 1)..."
        git -C "$SCRIPTDIR/hoedown" fetch --depth 1 origin 2>/dev/null || true
        # 尝试 reset 到 origin/master 或 origin/main，兼容两种分支名
        git -C "$SCRIPTDIR/hoedown" reset --hard origin/master 2>/dev/null || git -C "$SCRIPTDIR/hoedown" reset --hard origin/main 2>/dev/null || true
    elif [[ -d "$SCRIPTDIR/BUILD/hoedown" && -f "$SCRIPTDIR/BUILD/hoedown/Makefile" ]]; then
        echo "==> Found hoedown at $SCRIPTDIR/BUILD/hoedown, copying to $SCRIPTDIR/hoedown for docker..."
        mkdir -p "$SCRIPTDIR/hoedown"
        cp -a "$SCRIPTDIR/BUILD/hoedown/." "$SCRIPTDIR/hoedown/"
    elif [[ ! -d "$SCRIPTDIR/hoedown" ]]; then
        echo "==> Cloning hoedown (depth 1)..."
        git clone --depth 1 "$HOEDOWN_URL" "$SCRIPTDIR/hoedown"
    fi
}

# koxtoolchain 仓库 (用于 refs/x-compile.sh)
ensure_kox_repo() {
    local kox_dir="/tmp/koxtoolchain"
    if [[ -d "$kox_dir/.git" ]]; then
        echo "==> koxtoolchain repo already at $kox_dir, fetching..."
        git -C "$kox_dir" fetch --depth 1 origin 2>/dev/null || true
        git -C "$kox_dir" reset --hard origin/master 2>/dev/null || git -C "$kox_dir" reset --hard origin/main 2>/dev/null || true
    elif [[ ! -d "$kox_dir" ]]; then
        echo "==> Cloning koxtoolchain (depth 1) to $kox_dir..."
        git clone --depth 1 https://github.com/koreader/koxtoolchain.git "$kox_dir"
    fi
}

# 安装/复用 koxtoolchain 工具链
# 参数: $1 = kobo | kindlepw2
ensure_toolchain() {
    local tc="$1"       # kobo / kindlepw2
    local prefix
    if [[ "$tc" == "kobo" ]]; then
        prefix="arm-kobo-linux-gnueabihf"
    else
        prefix="arm-kindlepw2-linux-gnueabi"
    fi

    # 判断是否已安装
    # 优先检查 ~/x-tools，其次 /tmp/x-tools
    local x_tools_home="$HOME/x-tools"
    # HOME 不可写时回退到 /tmp/x-tools
    if [[ ! -w "$HOME" ]] 2>/dev/null || [[ ! -d "$HOME" ]]; then
        x_tools_home="/tmp/x-tools"
    fi
    local gcc_path="$x_tools_home/$tc/bin/${prefix}-gcc"
    local alt_gcc="/tmp/x-tools/$tc/bin/${prefix}-gcc"

    if [[ -x "$gcc_path" ]] || [[ -x "$alt_gcc" ]]; then
        echo "==> Toolchain $tc already installed, skipping download."
        return 0
    fi
    # 也检查 PATH 中是否已有对应 gcc (用户自行安装的情况)
    if command -v "${prefix}-gcc" >/dev/null 2>&1; then
        echo "==> ${prefix}-gcc found in PATH, skipping download."
        return 0
    fi

    local cache_dir="/tmp/koxtoolchain-cache"
    mkdir -p "$cache_dir"
    local archive="$cache_dir/${tc}.tar.zst"
    local url="${KOX_BASE_URL}/${tc}.tar.zst"

    if [[ ! -f "$archive" ]]; then
        echo "==> Downloading $tc toolchain $KOX_VERSION..."
        echo "    URL: $url"
        download_file "$url" "$archive"
    else
        echo "==> Using cached $archive"
    fi

    # 选择安装目录：优先 $HOME/x-tools，若 HOME 不可写则 /tmp/x-tools
    local install_root="$HOME/x-tools"
    if [[ ! -w "$HOME" ]] 2>/dev/null; then
        install_root="/tmp/x-tools"
        echo "==> HOME not writable, installing to $install_root"
    fi
    mkdir -p "$install_root"

    echo "==> Extracting $tc.tar.zst to $install_root (requires zstd)..."
    # 尝试 tar --zstd，若不支持则用 zstd -d | tar
    if tar --help 2>&1 | grep -q "zstd"; then
        tar --zstd -xf "$archive" -C "$install_root"
    else
        zstd -d -c "$archive" | tar -xf - -C "$install_root"
    fi

    echo "==> Toolchain $tc installed to $install_root/$tc"
    # 验证
    if [[ -x "$install_root/$tc/bin/${prefix}-gcc" ]]; then
        echo "    Verified: $install_root/$tc/bin/${prefix}-gcc"
    else
        echo "Warning: expected $install_root/$tc/bin/${prefix}-gcc not found after extraction" >&2
        ls -R "$install_root/$tc" 2>&1 | head -n 30 >&2 || true
    fi
}

# 暂存 OUTPUT/lib 到 DIST
stage_output() {
    local dest_subdir="$1"   # e.g. armv7_hardfp / x86_64
    local dest="$DIST/$dest_subdir"
    mkdir -p "$dest"
    if [[ -f "$SCRIPTDIR/OUTPUT/lib/libhoedown.so.3" ]]; then
        echo "==> Staging libhoedown.so.3 -> $dest/"
        cp -a "$SCRIPTDIR/OUTPUT/lib/libhoedown.so.3" "$dest/"
    else
        echo "Warning: OUTPUT/lib/libhoedown.so.3 not found, skipping stage for $dest_subdir" >&2
    fi
    # resty：只要 OUTPUT 中有就同步到 DIST/resty (幂等覆盖)
    if [[ -d "$SCRIPTDIR/OUTPUT/lib/resty" ]]; then
        echo "==> Staging resty -> $DIST/resty/"
        mkdir -p "$DIST/resty"
        cp -a "$SCRIPTDIR/OUTPUT/lib/resty/." "$DIST/resty/" 2>/dev/null || cp -a "$SCRIPTDIR/OUTPUT/lib/resty" "$DIST/" 2>/dev/null || true
        # 同时确保顶层 hoedown.lua
        if [[ -f "$SCRIPTDIR/OUTPUT/lib/resty/hoedown.lua" ]]; then
            : # already covered
            true
        fi
        # OUTPUT/lib/resty 结构是 lib/resty/*，tar x 后为 OUTPUT/lib/resty
        # 确保 DIST/resty 包含 hoedown.lua
        if [[ ! -f "$DIST/resty/hoedown.lua" && -f "$SCRIPTDIR/OUTPUT/lib/resty/hoedown.lua" ]]; then
            cp -a "$SCRIPTDIR/OUTPUT/lib/resty/hoedown.lua" "$DIST/resty/"
        fi
    fi
}

# Android 产物暂存
stage_android() {
    local src_arch="$1"   # armeabi-v7a / arm64-v8a
    local dest_subdir="$2" # android_armv7a / android_arm64
    local dest="$DIST/$dest_subdir"
    mkdir -p "$dest"
    local src="$SCRIPTDIR/hoedown/libhoedown.so.3"
    if [[ -f "$src" ]]; then
        echo "==> Staging Android $src_arch libhoedown.so.3 -> $dest/"
        cp -a "$src" "$dest/libhoedown.so.3"
    else
        echo "Warning: $src not found after Android build for $src_arch" >&2
    fi
}

ensure_resty_fallback() {
    if [[ -d "$DIST/resty" && -f "$DIST/resty/hoedown.lua" ]]; then
        return 0
    fi
    echo "==> resty not yet staged, ensuring via git clone fallback..."
    local tmp_rest
    tmp_rest=$(mktemp -d)
    if git clone --depth 1 "$RESTY_URL" "$tmp_rest/lua-resty-hoedown" 2>/dev/null; then
        mkdir -p "$DIST/resty"
        if [[ -d "$tmp_rest/lua-resty-hoedown/lib/resty" ]]; then
            cp -a "$tmp_rest/lua-resty-hoedown/lib/resty/." "$DIST/resty/"
        fi
        echo "    resty staged from fallback clone"
    else
        echo "Warning: failed to clone lua-resty-hoedown for resty fallback" >&2
    fi
    rm -rf "$tmp_rest"
}

# ========== 初始化 DIST ==========
mkdir -p "$DIST"

# 预先确保 hoedown 源码存在 (Android docker 需要 /workspace/hoedown)
if should_build "android-armv7a" || should_build "android-arm64"; then
    ensure_hoedown_src
fi
# koxtoolchain 构建也会通过 build_hoedown.sh 克隆，但提前准备可加速
if should_build "kobo" || should_build "kindlepw2" || should_build "x86_64"; then
    # 不强制提前克隆，build_hoedown.sh 会处理；但为幂等可先确保
    :
fi

# ========== 构建 x86_64 (原生) ==========
if should_build "x86_64"; then
    echo "=================================================================="
    echo "==> Building x86_64 (native)..."
    echo "=================================================================="
    # 原生直接调用 build_hoedown.sh，无需工具链
    "$SCRIPTDIR/build_hoedown.sh"
    stage_output "x86_64"
fi

# ========== 构建 kobo (armv7_hardfp) ==========
if should_build "kobo"; then
    echo "=================================================================="
    echo "==> Building kobo -> armv7_hardfp (arm-kobo-linux-gnueabihf)..."
    echo "=================================================================="
    ensure_kox_repo
    ensure_toolchain "kobo"
    # 在子 shell 中 source 环境并构建，避免污染后续构建
    (
        set -e
        set -o pipefail
        # shellcheck disable=SC1091
        source /tmp/koxtoolchain/refs/x-compile.sh kobo env bare
        "$SCRIPTDIR/build_hoedown.sh" arm-kobo-linux-gnueabihf
    )
    stage_output "armv7_hardfp"
fi

# ========== 构建 kindlepw2 (armv7_softfp) ==========
if should_build "kindlepw2"; then
    echo "=================================================================="
    echo "==> Building kindlepw2 -> armv7_softfp (arm-kindlepw2-linux-gnueabi)..."
    echo "=================================================================="
    ensure_kox_repo
    ensure_toolchain "kindlepw2"
    (
        set -e
        set -o pipefail
        # shellcheck disable=SC1091
        source /tmp/koxtoolchain/refs/x-compile.sh kindlepw2 env bare
        "$SCRIPTDIR/build_hoedown.sh" arm-kindlepw2-linux-gnueabi
    )
    stage_output "armv7_softfp"
fi

# ========== 构建 Android (docker) ==========
# Android 必须通过 docker 运行，不使用宿主机 NDK
# 固定 Docker 镜像 liasoft/antispy-build-android:ndk-r23c
#   - NDK r23c
#   - API 18 for armeabi-v7a (armv7a-linux-androideabi21-clang + -Wl,--fix-cortex-a8)
#   - API 21 for arm64-v8a  (aarch64-linux-android21-clang)
# CFLAGS 已在 build-android.sh 中固定且移除了 -fvisibility=hidden

if should_build "android-armv7a"; then
    echo "=================================================================="
    echo "==> Building android-armv7a (armeabi-v7a, API 18) via docker..."
    echo "=================================================================="
    ensure_hoedown_src
    # --fix-cortex-a8 仅用于 armeabi-v7a，已在 build-android.sh 中处理
    docker run --rm \
        -v "$SCRIPTDIR:/workspace" \
        -w /workspace \
        "$DOCKER_IMAGE" \
        /workspace/build-android.sh armeabi-v7a
    stage_android "armeabi-v7a" "android_armv7a"
fi

if should_build "android-arm64"; then
    echo "=================================================================="
    echo "==> Building android-arm64 (arm64-v8a, API 21) via docker..."
    echo "=================================================================="
    ensure_hoedown_src
    docker run --rm \
        -v "$SCRIPTDIR:/workspace" \
        -w /workspace \
        "$DOCKER_IMAGE" \
        /workspace/build-android.sh arm64-v8a
    stage_android "arm64-v8a" "android_arm64"
fi

# ========== 确保 resty 已收集 ==========
# build_hoedown.sh 已克隆 lua-resty-hoedown 并放入 OUTPUT/lib/resty，
# 优先从 x86_64/kobo/kindlepw2 的 OUTPUT 暂存；若仅构建 Android 则 fallback
if [[ ! -d "$DIST/resty" || ! -f "$DIST/resty/hoedown.lua" ]]; then
    # 尝试从最近一次 OUTPUT 暂存
    if [[ -d "$SCRIPTDIR/OUTPUT/lib/resty" ]]; then
        echo "==> Collecting resty from last OUTPUT..."
        mkdir -p "$DIST/resty"
        cp -a "$SCRIPTDIR/OUTPUT/lib/resty/." "$DIST/resty/" 2>/dev/null || true
    fi
fi
# 若仍缺失，使用 git fallback
if [[ ! -d "$DIST/resty" || ! -f "$DIST/resty/hoedown.lua" ]]; then
    ensure_resty_fallback
else
    echo "==> resty already staged at $DIST/resty/"
fi

# ========== 打包（适配 assistant.koplugin 直接跟踪结构） ==========
# 用户要求：build_all.sh 直接输出包含以下结构的压缩包（不再是旧的 lua-hoedown_kobo.tgz 分包）：
#   lib/android_arm64/libhoedown.so.3
#   lib/android_armv7a/libhoedown.so.3
#   lib/armv7_hardfp/libhoedown.so.3
#   lib/armv7_softfp/libhoedown.so.3
#   lib/x86_64/libhoedown.so.3
#   lib/resty/hoedown.lua + lib/resty/hoedown/*.lua
# 该压缩包可直接解压到 assistant.koplugin 根目录（tar xzf -C ../assistant.koplugin）或 dist/lib
PKG_DIR="$DIST/lib"
PKG_TGZ="$DIST/hoedown-libs.tgz"
PKG_ZIP="$DIST/hoedown-libs.zip"
echo ""
echo "=================================================================="
echo "  Packaging lib/ archive"
echo "=================================================================="
# 清理旧的打包目录，重新组装
rm -rf "$PKG_DIR"
mkdir -p "$PKG_DIR"
for d in armv7_hardfp armv7_softfp x86_64 android_armv7a android_arm64; do
    if [[ -f "$DIST/$d/libhoedown.so.3" ]]; then
        mkdir -p "$PKG_DIR/$d"
        cp -a "$DIST/$d/libhoedown.so.3" "$PKG_DIR/$d/"
        echo "  staged lib/$d/libhoedown.so.3"
    else
        echo "  skip lib/$d/libhoedown.so.3 (not built)" >&2
    fi
done
if [[ -d "$DIST/resty" ]]; then
    mkdir -p "$PKG_DIR/resty"
    cp -a "$DIST/resty/." "$PKG_DIR/resty/"
    echo "  staged lib/resty/"
fi
# 生成压缩包（两者都提供，优先 tgz）
if [[ -d "$PKG_DIR" ]] && ls "$PKG_DIR"/*/libhoedown.so.3 1>/dev/null 2>&1; then
    echo "  creating $PKG_TGZ ..."
    tar -czf "$PKG_TGZ" -C "$DIST" lib
    ls -lh "$PKG_TGZ"
    if command -v zip >/dev/null 2>&1; then
        echo "  creating $PKG_ZIP ..."
        (cd "$DIST" && zip -r -q "$(basename "$PKG_ZIP")" lib)
        ls -lh "$PKG_ZIP"
    fi
    echo "  package contents:"
    tar tzf "$PKG_TGZ" 2>&1 | head -n 30 || true
else
    echo "Warning: no lib to package, skipping archive" >&2
fi

# ========== 汇总 ==========
echo ""
echo "=================================================================="
echo "  Build Summary"
echo "=================================================================="
echo "DIST = $DIST"
echo ""
if ls "$DIST"/*/libhoedown.so.3 1>/dev/null 2>&1; then
    echo "--- ls -lh dist/*/libhoedown.so.3 dist/resty ---"
    ls -lh "$DIST"/*/libhoedown.so.3 2>&1 || true
    if [[ -d "$DIST/resty" ]]; then
        ls -lh "$DIST/resty" 2>&1 || true
        # 若 resty 下有多文件，列出详情
        ls -lh "$DIST/resty/hoedown.lua" "$DIST/resty/hoedown" 2>&1 | head -n 30 || true
    fi
    echo ""
    echo "--- file dist/*/libhoedown.so.3 ---"
    file "$DIST"/*/libhoedown.so.3 2>&1 || true
else
    echo "Warning: no libhoedown.so.3 found in $DIST" >&2
    ls -R "$DIST" 2>&1 | head -n 50 || true
fi

echo ""
echo "--- ELF hard/soft float check (armv7) ---"
if command -v readelf >/dev/null 2>&1; then
    for f in "$DIST"/armv7_*/libhoedown.so.3; do
        [[ -f "$f" ]] || continue
        echo ">>> $f"
        readelf -A "$f" 2>&1 | grep -E 'Tag_ABI|VFP' || echo "  (no VFP tag = soft-float)"
    done
else
    echo "(readelf not found, skipping)"
fi

echo ""
echo "To install to consumer plugin, run:"
echo "  cp -a \"$DIST\"/armv7_hardfp/libhoedown.so.3  ../assistant.koplugin/lib/armv7_hardfp/libhoedown.so.3"
echo "  cp -a \"$DIST\"/armv7_softfp/libhoedown.so.3  ../assistant.koplugin/lib/armv7_softfp/libhoedown.so.3"
echo "  cp -a \"$DIST\"/x86_64/libhoedown.so.3        ../assistant.koplugin/lib/x86_64/libhoedown.so.3"
echo "  cp -a \"$DIST\"/android_armv7a/libhoedown.so.3 ../assistant.koplugin/lib/android_armv7a/libhoedown.so.3"
echo "  cp -a \"$DIST\"/android_arm64/libhoedown.so.3  ../assistant.koplugin/lib/android_arm64/libhoedown.so.3"
echo "  cp -a \"$DIST\"/resty                         ../assistant.koplugin/lib/resty"
echo "  cp -a \"$DIST\"/resty/hoedown.lua             ../assistant.koplugin/lib/resty/hoedown.lua"
echo ""
echo "Or bulk copy:"
echo "  for d in armv7_hardfp armv7_softfp x86_64 android_armv7a android_arm64; do"
echo "    mkdir -p \"../assistant.koplugin/lib/\$d\""
echo "    cp -a \"$DIST/\$d/libhoedown.so.3\" \"../assistant.koplugin/lib/\$d/\""
echo "  done"
echo "  mkdir -p ../assistant.koplugin/lib/resty && cp -a \"$DIST/resty/.\" ../assistant.koplugin/lib/resty/"
echo ""
echo "Done."
