# hoedown4eink

This project provides build scripts to compile `libhoedown` and `lua-resty-hoedown` for e-ink devices running KOReader. The primary goal is to enable native Markdown rendering support for the [assistant.koplugin](https://github.com/omer-faruq/assistant.koplugin).

The release assets are cross-compiled using the KOReader koxtoolchain.

## Reproducible Build (Recommended)

One-click build for all 5 `libhoedown.so.3` variants + `resty` Lua binding via `./build_all.sh`. All versions are pinned for reproducibility.

```sh
# all 5 archs + resty -> dist/
./build_all.sh

# single arch only
./build_all.sh --arch x86_64
./build_all.sh --arch kobo            # armv7_hardfp
./build_all.sh --arch kindlepw2       # armv7_softfp
./build_all.sh --arch android-armv7a  # via Docker
./build_all.sh --arch android-arm64   # via Docker
```

**Fixed versions:**
- `koxtoolchain` **2026.08** — `kobo.tar.zst` / `kindlepw2.tar.zst` from `https://github.com/koreader/koxtoolchain/releases/download/2026.08/` (requires `zstd` to extract; cached at `/tmp/koxtoolchain-cache/`, installed to `~/x-tools/` or `/tmp/x-tools`)
- Docker image `liasoft/antispy-build-android:ndk-r23c` — NDK **r23c** at `/usr/local/android/android-ndk-r23c`, API **18** for `armeabi-v7a` (`armv7a-linux-androideabi21-clang` + `-Wl,--fix-cortex-a8 -march=armv7-a`), API **21** for `arm64-v8a` (`aarch64-linux-android21-clang`)
- `hoedown` `git clone --depth 1 https://github.com/hoedown/hoedown.git`
- `lua-resty-hoedown` `git clone --depth 1 https://github.com/bungle/lua-resty-hoedown.git`

**Prerequisites:** `tar`, `git`, `curl` or `wget`, `zstd` (for `*.tar.zst`), `docker` (only for Android builds), plus `make`/`strip` for native/koxtoolchain builds.

**Output `dist/` layout (directly matches `assistant.koplugin/lib/` tracking):**

```
dist/
  armv7_hardfp/libhoedown.so.3   # kobo — hard-float VFP
  armv7_softfp/libhoedown.so.3   # kindlepw2 — soft-float
  x86_64/libhoedown.so.3         # native desktop/emulator
  android_armv7a/libhoedown.so.3 # API 18, ~48K stripped
  android_arm64/libhoedown.so.3  # API 21, ~57K stripped
  resty/hoedown.lua
  resty/hoedown/*.lua            # 9 files, pure Lua FFI binding
  lib/                           # assembled package root (for direct copy/tar)
    android_arm64/libhoedown.so.3
    android_armv7a/libhoedown.so.3
    armv7_hardfp/libhoedown.so.3
    armv7_softfp/libhoedown.so.3
    x86_64/libhoedown.so.3
    resty/...
  hoedown-libs.tgz               # compressed package containing lib/ (see above)
  hoedown-libs.zip               # same content as zip (if zip available)
```

`hoedown-libs.tgz` is the **single release artifact** (replaces legacy `lua-hoedown_kobo.tgz` per-arch tgz). Its top-level `lib/` can be extracted directly into the consumer:

```sh
# from dist/
tar tzf hoedown-libs.tgz | head -20   # shows lib/...
tar xzf hoedown-libs.tgz -C ../assistant.koplugin/   # -> ../assistant.koplugin/lib/...
# or manual copy
for d in armv7_hardfp armv7_softfp x86_64 android_armv7a android_arm64; do
  mkdir -p "../assistant.koplugin/lib/$d"
  cp -a "dist/$d/libhoedown.so.3" "../assistant.koplugin/lib/$d/"
done
mkdir -p ../assistant.koplugin/lib/resty
cp -a dist/resty/. ../assistant.koplugin/lib/resty/

# verify
file ../assistant.koplugin/lib/*/libhoedown.so.3
readelf -A ../assistant.koplugin/lib/armv7_*/libhoedown.so.3 | grep -E 'Tag_ABI|VFP'
```

## Installation

You can install the pre-compiled binaries using the automated script or by downloading them manually from the releases page.

### Automated Install (Recommended)

This method uses a Lua script to download and install the correct files for your device.

1.  Download the `gethoedown.lua` script to the root of your KOReader directory.
2.  In KOReader, open the Terminal Emulator:
    `Menu -> Tools -> More Tools -> Terminal emulator -> Open terminal session`
3.  Run the script with your device's platform tag. See the table below for the correct tag.
    ```sh
    # Example for a Kobo device
    ./luajit gethoedown.lua kobo

    # Example for a Kindle device
    ./luajit gethoedown.lua kindlepw2
    ```
4.  Restart KOReader.

### Manual Install

1.  Go to the Releases page.
2.  Download the appropriate `.tgz` archive for your device from the table below.
3.  Extract the contents of the archive into your KOReader's `plugins/assistant.koplugin/` directory.
4.  Restart KOReader.

## Downloads & Compatibility

| Device / Platform         | Platform Tag  | Release Asset             | Plugin `lib/` subdir | Size (stripped) |
|---------------------------|---------------|---------------------------|----------------------|-----------------|
| Kindle PW3/Oasis 2        | `kindlepw2`   | `lua-hoedown_kindlepw2.tgz` | `armv7_softfp`     | ~42K |
| Kobo H2O/Libra 2/Clara HD | `kobo`        | `lua-hoedown_kobo.tgz`    | `armv7_hardfp`     | ~42K |
| Remarkable 1              | `kobo`        | `lua-hoedown_kobo.tgz`    | `armv7_hardfp`     | ~42K |
| Android ARM 32-bit        | `armeabi-v7a` | `build-android.sh armeabi-v7a` (Docker) | `android_armv7a` | ~48K |
| Android ARM 64-bit        | `arm64-v8a`   | `build-android.sh arm64-v8a` (Docker)   | `android_arm64`  | ~57K |
| Linux x86_64 (Desktop/Emulator) | `x86_64` | `lua-hoedown_x86_64.tgz` | `x86_64`           | ~75K |

> Historical tag mapping: `build_hoedown.sh` tags `lua-hoedown_<tag>.tgz` with `<tag> = $(echo $TOOLCHAIN_PREFIX | cut -d- -f2)` → `kobo`/`kindlepw2`/`x86_64`. Consumer plugin renames to `armv7_hardfp`/`armv7_softfp`/`x86_64` (+ `android_*`). All 5 `libhoedown.so.3` + `resty/` are required under `assistant.koplugin/lib/`.

## Verify Installation

To confirm that the Hoedown library is being used correctly:

1.  Open the Terminal Emulator in KOReader.
2.  Check the log for a confirmation message:
    ```sh
    grep markdown crash.log
    ```
3.  A successful installation will show a line similar to this:
    ```
    07/22/25-16:14:44 INFO  Using hoedown (C binding) for markdown parsing
    ```

## Building from Source

If you prefer manual builds, the sections below call `build_hoedown.sh` / `build-android.sh` directly. For reproducible pinned versions use `./build_all.sh` above.

**Dependencies:** `make`, `strip`, `tar`, `git`, `zstd` (needed to extract `koxtoolchain/*.tar.zst`), plus `curl`/`wget` for toolchain download and `docker` for Android.

All builds produce `OUTPUT/lib/libhoedown.so.3` + `OUTPUT/lib/resty/`; `build_all.sh` stages them into `dist/` as described above. Legacy packaging `lua-hoedown_<tag>.tgz` is still created by `build_hoedown.sh`.

### Native Build

For a native build (e.g., on `Linux x86_64`), simply run the build script:

```sh
./build_hoedown.sh
# output: OUTPUT/lib/libhoedown.so.3 -> dist/x86_64/libhoedown.so.3 (via build_all.sh)
# or legacy: lua-hoedown_x86_64.tgz
```

### Cross-Compilation (Manual)

1.  **Generate or download the toolchain** for your target device via [koxtoolchain](https://github.com/koreader/koxtoolchain).
    `build_all.sh` auto-downloads pinned `2026.08` `kobo.tar.zst` / `kindlepw2.tar.zst` (requires `zstd`); manual alternative:
    ```sh
    # From your koxtoolchain directory
    ./gen-tc.sh kobo
    ./gen-tc.sh kindlepw2
    ```

2.  **Source the environment** for your target (order matters — must precede `build_hoedown.sh`).
    ```sh
    # Example for Kobo
    source /path/to/koxtoolchain/refs/x-compile.sh kobo env bare

    # Example for Kindle
    source /path/to/koxtoolchain/refs/x-compile.sh kindlepw2 env bare
    ```

3.  **Run the build script** with the correct toolchain prefix. You can find the prefix by listing the contents of the `x-tools` directory in your toolchain.
    ```sh
    # Example for Kobo -> armv7_hardfp
    ./build_hoedown.sh arm-kobo-linux-gnueabihf

    # Example for Kindle -> armv7_softfp
    ./build_hoedown.sh arm-kindlepw2-linux-gnueabi
    ```

    Or via `build_all.sh` (handles `source x-compile.sh ... bare` in a subshell):
    ```sh
    ./build_all.sh --arch kobo
    ./build_all.sh --arch kindlepw2
    ```

### Build for Android (Manual)

Previously required `docker run -w /workspace -w /workspace/hoedown` dance. The fixed `build-android.sh` works from the repo root; just mount `$(pwd)`:

```sh
docker pull liasoft/antispy-build-android:ndk-r23c

# single-step via wrapper (recommended)
./build_all.sh --arch android-armv7a
./build_all.sh --arch android-arm64

# or directly via Docker (no interactive shell needed)
docker run --rm -v $(pwd):/workspace -w /workspace \
  liasoft/antispy-build-android:ndk-r23c \
  /workspace/build-android.sh armeabi-v7a

docker run --rm -v $(pwd):/workspace -w /workspace \
  liasoft/antispy-build-android:ndk-r23c \
  /workspace/build-android.sh arm64-v8a

# legacy interactive form still works:
docker run -it --rm -v $(pwd):/workspace -w /workspace \
  liasoft/antispy-build-android:ndk-r23c /bin/bash
./build-android.sh armeabi-v7a
./build-android.sh arm64-v8a
```

Notes:
- NDK is at `/usr/local/android/android-ndk-r23c` (`ANDROID_NDK=/usr/local/android/android-ndk-r23c`, `ANDROID_NDK_ROOT=/usr/local/android`). Script auto-detects `ANDROID_NDK` / `ANDROID_NDK_ROOT` / fallback.
- `armeabi-v7a` uses API 18 with `-Wl,--fix-cortex-a8 -march=armv7-a`; `arm64-v8a` uses API 21. CFLAGS are size-optimized: `-Os -ffunction-sections -fdata-sections -Wl,--gc-sections -Wl,-s`.
- **Do NOT add `-fvisibility=hidden`** — hoedown has no visibility annotations; `hidden` + `--gc-sections` produces a 2.5K empty library (`dynsym 3`, `0 hoedown_*`, `.text 68B`). Fixed in `15e082c`; the correct size is ~48K/57K with 45 `hoedown_*` symbols. Verified with `llvm-readelf --dyn-symbols`.
