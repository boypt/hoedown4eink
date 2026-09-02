# AGENTS.md

## Overview
Cross-compilation wrapper that builds `libhoedown` (C Markdown parser) for `../assistant.koplugin`. Release artifact is `dist/hoedown-libs.tgz` (single archive containing `lib/` with 5 `libhoedown.so.3`), extracted directly into the plugin as `lib/*/libhoedown.so.3`. Legacy per-arch `lua-hoedown_<tag>.tgz` packaging has been removed. Not a Node/Python package — no package manager, no lint/typecheck.

## Required Artifacts (consumed by `../assistant.koplugin`)

`assistant_mdparser.lua:get_platform_libdir()` resolves at runtime — the 5 binaries below are **all required**; `lib/` is NOT excluded by `.releaseignore` (verified: `is_excluded("lib/libhoedown.so.3")==false`) and ships inside the release zip.

| Plugin path (`assistant.koplugin/lib/`) | `get_platform_libdir()` | Device mapping | Build in this repo | ELF / toolchain | Size (stripped) |
|---|---|---|---|---|---|
| `armv7_softfp/libhoedown.so.3` | `armv7_softfp` | Kindle PW3/Oasis, soft-float ARM e-readers | `build_hoedown.sh arm-kindlepw2-linux-gnueabi` (after `source .../x-compile.sh kindlepw2 env bare`) | ELF32 ARM EABI5 soft-float, `libc.so.6` | ~42K |
| `armv7_hardfp/libhoedown.so.3` | `armv7_hardfp` | Kobo/Remarkable/PocketBook, hard-float ARM e-readers | `build_hoedown.sh arm-kobo-linux-gnueabihf` (after `source .../x-compile.sh kobo env bare`) | ELF32 ARM EABI5 hard-float VFP (`Tag_ABI_VFP_args`), `libc.so.6` | ~42K |
| `android_armv7a/libhoedown.so.3` | `android_armv7a` | Android ARM 32-bit | `./build_android.sh armeabi-v7a` inside Docker `liasoft/antispy-build-android:ndk-r23c` (API 18, `armv7a-linux-androideabi21-clang`, NDK r23c) | ELF32 ARM for Android 18, `libc.so` | ~48K |
| `android_arm64/libhoedown.so.3` | `android_arm64` | Android ARM 64-bit | `./build_android.sh arm64-v8a` inside same Docker image (API 21, `aarch64-linux-android21-clang`) | ELF64 AArch64 for Android 21, `libc.so` | ~57K |
| `x86_64/libhoedown.so.3` | `x86_64` | Desktop/Emulator (`Device:isDesktop()`) | `./build_hoedown.sh` native (no prefix, `uname -m` tag) | ELF64 x86-64, `libc.so.6` | ~75K |

**Historical names**: `build_hoedown.sh` previously tagged output as `lua-hoedown_<tag>.tgz` where `<tag>=$(echo $TOOLCHAIN_PREFIX | cut -d- -f2)` → `kobo` (=`armv7_hardfp`), `kindlepw2` (=`armv7_softfp`), `x86_64`; legacy per-arch tgz packaging has been removed in favor of the unified `dist/` + `hoedown-libs.tgz` flow. Renamed in `assistant.koplugin@9d05b14` from `lib/arm_kobo|arm_kindle` to `lib/armv7_hardfp|armv7_softfp` to reflect generic float-ABI detection; `README.md` now documents the `dist/` → `lib/` mapping including `android_*`.

**Runtime selection** (`assistant_mdparser.lua`):
- `Device:isDesktop()|isEmulator() → x86_64`; `Device:isAndroid() → jit.arch` picks `android_arm64` vs `android_armv7a` (staged via `stage_android_library()` to `android.dir/plugins/...` because `dlopen` fails on external storage).
- Generic ARM → `isHardFP()` checks `/lib/ld-linux-armhf.so.3` (same heuristic as KOReader `kindle/device.lua`) → `armv7_hardfp` vs `armv7_softfp`. One soft-float build works on any EABI5 environment; hard-float build also loads on aarch64 hosts.
- Fallback: `pcall(ffi.loadlib,"hoedown",3)` (system) before plugin path; then `package.preload["resty.hoedown.library"] = LibHoedown` + `package.path += "lib/?.lua"` + `require("resty.hoedown")` with extensions `space_headers,tables,fenced_code,footnotes,autolink,strikethrough,underline,highlight,quote,superscript,math,math_explicit`. Missing file falls back to pure-Lua `apps/filemanager/lib/md`.

**Packaging note**: this repo produces only `libhoedown.so.3` (C). The consumer commits them directly under `assistant.koplugin/lib/` (see `assistant.koplugin/lib/` — 5 `libhoedown.so.3`). `build_all.sh` produces `dist/hoedown-libs.tgz` (`tar -czf dist/hoedown-libs.tgz -C dist lib`) and `dist/hoedown-libs.zip` with top-level `lib/` ready for `tar xzf -C ../assistant.koplugin`. Legacy per-arch `lua-hoedown_*.tgz` is no longer produced; `/*.tgz` stays gitignored defensively.

## Structure
- `build_hoedown.sh` — clones `hoedown/hoedown`, compiles `libhoedown.so.3` with `make CC=${TOOLCHAIN_PREFIX}gcc`, strips; leaves the artifact at `hoedown/libhoedown.so.3` (same build dir as Android, no `OUTPUT/`)
- `build_android.sh` — Android cross-compile (runs inside Docker, not via koxtoolchain); supports NDK at `ANDROID_NDK` / `ANDROID_NDK_ROOT` and repo-root invocation
- `hoedown/` — git-cloned C source (currently untracked, **do not commit**); contains `Makefile`, `src/`, `test/`
- `hoedown/` — single shared build dir for native/koxtoolchain (`build_hoedown.sh`) and Android (`build_android.sh` in Docker); each build does `make clean` in-place. Clean all intermediates with `rm -rf hoedown` (there is no `BUILD/` / `OUTPUT/`)
- `dist/` — reproducible output staged by `build_all.sh`: `dist/{armv7_hardfp,armv7_softfp,x86_64,android_armv7a,android_arm64}/libhoedown.so.3` + assembled `dist/lib/` (+ `dist/hoedown-libs.tgz|zip` with top-level `lib/`)
- `build_all.sh` — reproducible one-click wrapper: pins koxtoolchain 2026.08 (`kobo`/`kindlepw2` `.tar.zst` via `zstd`), Docker `liasoft/antispy-build-android:ndk-r23c` (NDK r23c API 18/21), `hoedown` depth 1; supports `--arch` filter, stages to `dist/` and assembles `dist/lib/` + `hoedown-libs.tgz|zip`
- `dist/` / `hoedown/` are gitignored; `/*.tgz` at repo root is also gitignored defensively (no longer produced)

## Build & Verify

```sh
# Native (x86_64)
./build_hoedown.sh

# Cross-compile — source koxtoolchain env FIRST, then pass prefix
source /path/to/koxtoolchain/refs/x-compile.sh kobo env bare
./build_hoedown.sh arm-kobo-linux-gnueabihf        # → lib/armv7_hardfp
source /path/to/koxtoolchain/refs/x-compile.sh kindlepw2 env bare
./build_hoedown.sh arm-kindlepw2-linux-gnueabi     # → lib/armv7_softfp

# Android — must run inside Docker image
docker pull liasoft/antispy-build-android:ndk-r23c
docker run -it --rm -v $(pwd):/workspace -w /workspace liasoft/antispy-build-android:ndk-r23c /bin/bash
./build_android.sh armeabi-v7a   # → lib/android_armv7a
./build_android.sh arm64-v8a     # → lib/android_arm64

# Verify binaries committed to consumer
file ../assistant.koplugin/lib/*/libhoedown.so.3
readelf -A ../assistant.koplugin/lib/armv7_*/libhoedown.so.3 | grep -E 'Tag_ABI|VFP'
# Test C library directly (inside hoedown/)
cd hoedown && make test          # python test/runner.py; requires python
cd hoedown && make test-pl       # perl MarkdownTest, requires tidy
```

Build script validates toolchain by checking `${ARG1}-gcc` exists; if not found `TOOLCHAIN_PREFIX` stays empty and falls back to native `gcc`. No per-arch tgz is packaged anymore — the artifact stays in `hoedown/` and `build_all.sh` stages it into `dist/`.

## Gotchas
- **Env sourcing order matters**: `source x-compile.sh <target> env bare` must precede `./build_hoedown.sh <prefix>`.
- **Unified build dir**: native/koxtoolchain and Android both compile inside `hoedown/` — there is no `BUILD/` / `OUTPUT/` anymore. `build_all.sh` stages each arch from `hoedown/libhoedown.so.3` to `dist/` right after its build, so overwrites are safe. To clean all intermediates: `rm -rf hoedown`.
- **Android script**: root `build_android.sh` (API 18 for armeabi-v7a with `-Wl,--fix-cortex-a8 -march=armv7-a`, API 21 for arm64-v8a, NDK r23c at `/usr/local/android/android-ndk-r23c`). Android CFLAGS are size-optimized (`-Os -ffunction-sections -fdata-sections -Wl,--gc-sections -Wl,-s`) → ~30% smaller than koxtoolchain builds (`CFLAGS=-g -O3`); **do NOT add `-fvisibility=hidden`** — hoedown has no visibility annotations, hidden + `--gc-sections` produces 2.5K empty libs (`dynsym 3`, `0 hoedown`, `.text 68B`). Fixed in `15e082c`; verified inside NDK container with `llvm-readelf` (hidden 2.5K/0 hoedown vs fixed 48K/45 hoedown).
- **No CI / no pre-commit**: no `.github/workflows`, no `opencode.json`, no formatter. Do not add CI assumptions.
- **Do not commit clones**: `hoedown/` (and `dist/`, `*.tgz`) are gitignored/untracked intentionally. The consumer's `lib/*.so.3` ARE committed.

## Conventions
- Shell scripts use `set -e`; keep it.
- `build_android.sh` comments are in Chinese — preserve when editing.
- Artifact mapping: `dist/<platform>/libhoedown.so.3` → `assistant.koplugin/lib/<platform>/libhoedown.so.3` (platforms as in the table above).
