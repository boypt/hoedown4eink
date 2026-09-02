# AGENTS.md

## Overview
Cross-compilation wrapper that builds `libhoedown` (C Markdown parser) + `lua-resty-hoedown` (Lua binding) for `../assistant.koplugin`. Release artifacts were `lua-hoedown_<tag>.tgz` (now directly committed as `lib/*/libhoedown.so.3` in the plugin). Not a Node/Python package — no package manager, no lint/typecheck.

## Required Artifacts (consumed by `../assistant.koplugin`)

`assistant_mdparser.lua:get_platform_libdir()` resolves at runtime — the 5 binaries below are **all required**; `lib/` is NOT excluded by `.releaseignore` (verified: `is_excluded("lib/libhoedown.so.3")==false`) and ships inside the release zip.

| Plugin path (`assistant.koplugin/lib/`) | `get_platform_libdir()` | Device mapping | Build in this repo | ELF / toolchain | Size (stripped) |
|---|---|---|---|---|---|
| `armv7_softfp/libhoedown.so.3` | `armv7_softfp` | Kindle PW3/Oasis, soft-float ARM e-readers | `build_hoedown.sh arm-kindlepw2-linux-gnueabi` (after `source .../x-compile.sh kindlepw2 env bare`) | ELF32 ARM EABI5 soft-float, `libc.so.6` | ~42K |
| `armv7_hardfp/libhoedown.so.3` | `armv7_hardfp` | Kobo/Remarkable/PocketBook, hard-float ARM e-readers | `build_hoedown.sh arm-kobo-linux-gnueabihf` (after `source .../x-compile.sh kobo env bare`) | ELF32 ARM EABI5 hard-float VFP (`Tag_ABI_VFP_args`), `libc.so.6` | ~42K |
| `android_armv7a/libhoedown.so.3` | `android_armv7a` | Android ARM 32-bit | `./build-android.sh armeabi-v7a` inside Docker `liasoft/antispy-build-android:ndk-r23c` (API 18, `armv7a-linux-androideabi21-clang`, NDK r23c) | ELF32 ARM for Android 18, `libc.so` | ~48K |
| `android_arm64/libhoedown.so.3` | `android_arm64` | Android ARM 64-bit | `./build-android.sh arm64-v8a` inside same Docker image (API 21, `aarch64-linux-android21-clang`) | ELF64 AArch64 for Android 21, `libc.so` | ~57K |
| `x86_64/libhoedown.so.3` | `x86_64` | Desktop/Emulator (`Device:isDesktop()`) | `./build_hoedown.sh` native (no prefix, `uname -m` tag) | ELF64 x86-64, `libc.so.6` | ~75K |
| `resty/hoedown.lua` + `resty/hoedown/*.lua` (9 files) | — | all platforms | `bungle/lua-resty-hoedown` cloned by `build_hoedown.sh:checkout_lua_resty_hoedown()` via `tar c lib \| tar x -C ../OUTPUT` → `OUTPUT/lib/resty/` | pure Lua (FFI) | ~25K total |

**Historical names**: `build_hoedown.sh` tags output as `lua-hoedown_<tag>.tgz` where `<tag>=$(echo $TOOLCHAIN_PREFIX | cut -d- -f2)` → `kobo` (=`armv7_hardfp`), `kindlepw2` (=`armv7_softfp`), `x86_64`. Renamed in `assistant.koplugin@9d05b14` from `lib/arm_kobo|arm_kindle` to `lib/armv7_hardfp|armv7_softfp` to reflect generic float-ABI detection; `README.md` now documents the `dist/` → `lib/` mapping including `android_*`.

**Runtime selection** (`assistant_mdparser.lua`):
- `Device:isDesktop()|isEmulator() → x86_64`; `Device:isAndroid() → jit.arch` picks `android_arm64` vs `android_armv7a` (staged via `stage_android_library()` to `android.dir/plugins/...` because `dlopen` fails on external storage).
- Generic ARM → `isHardFP()` checks `/lib/ld-linux-armhf.so.3` (same heuristic as KOReader `kindle/device.lua`) → `armv7_hardfp` vs `armv7_softfp`. One soft-float build works on any EABI5 environment; hard-float build also loads on aarch64 hosts.
- Fallback: `pcall(ffi.loadlib,"hoedown",3)` (system) before plugin path; then `package.preload["resty.hoedown.library"] = LibHoedown` + `package.path += "lib/?.lua"` + `require("resty.hoedown")` with extensions `space_headers,tables,fenced_code,footnotes,autolink,strikethrough,underline,highlight,quote,superscript,math,math_explicit`. Missing file falls back to pure-Lua `apps/filemanager/lib/md`.

**Packaging note**: this repo produces `libhoedown.so.3` (C) + `lib/resty/*` (Lua). The consumer commits them directly under `assistant.koplugin/lib/` (see `assistant.koplugin/lib/` — 5 `libhoedown.so.3` + 10 Lua files). Legacy `lua-hoedown_*.tgz` with `lib/` prefix extracted by `hoeins`/`gethoedown.lua` into `plugins/assistant.koplugin/` is now historical; keep `/*.tgz` gitignored.

## Structure
- `build_hoedown.sh` — clones `hoedown/hoedown` + `bungle/lua-resty-hoedown`, compiles `libhoedown.so.3` with `make CC=${TOOLCHAIN_PREFIX}gcc`, strips, installs to `OUTPUT/lib/`, packages `OUTPUT/` → `lua-hoedown_<tag>.tgz`
- `build-android.sh` — Android cross-compile (runs inside Docker, not via koxtoolchain); `hoedown/build-android.sh` is vendored copy with identical logic
- `hoedown/` — git-cloned C source (currently untracked, **do not commit**); contains `Makefile`, `src/`, `test/`
- `BUILD/` / `OUTPUT/` / `dist/` — ephemeral build dirs, gitignored; `OUTPUT/lib/` gets Lua files via `tar c lib | tar x` from lua-resty-hoedown; `dist/` is the reproducible output staged by `build_all.sh` (5 `libhoedown.so.3` + `resty/`)
- `build_all.sh` — reproducible one-click wrapper: pins koxtoolchain 2026.08 (`kobo`/`kindlepw2` `.tar.zst` via `zstd`), Docker `liasoft/antispy-build-android:ndk-r23c` (NDK r23c API 18/21), `hoedown`/`lua-resty-hoedown` depth 1; stages to `dist/` (`--arch` filter supported)
- `gethoedown.lua` — KOReader-side installer (LuaJIT, not standalone Lua) — downloads `lua-hoedown_<tag>.tgz` via GitHub API and extracts to `plugins/assistant.koplugin/`
- `hoeins` — shell helper `tar xvzf lua-hoedown_*.tgz -C plugins/assistant.koplugin/`
- `*.tgz` at repo root is `/*.tgz` gitignored (legacy); `dist/` / `hoedown/` / `lua-resty-hoedown/` are also gitignored

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
./build-android.sh armeabi-v7a   # → lib/android_armv7a
./build-android.sh arm64-v8a     # → lib/android_arm64

# Verify binaries committed to consumer
file ../assistant.koplugin/lib/*/libhoedown.so.3
readelf -A ../assistant.koplugin/lib/armv7_*/libhoedown.so.3 | grep -E 'Tag_ABI|VFP'
ls -lh ../assistant.koplugin/lib/resty/hoedown.lua ../assistant.koplugin/lib/resty/hoedown/

# Test C library directly (inside hoedown/)
cd hoedown && make test          # python test/runner.py; requires python
cd hoedown && make test-pl       # perl MarkdownTest, requires tidy
```

Build script validates toolchain by checking `${ARG1}-gcc` exists; if not found `TOOLCHAIN_PREFIX` stays empty and falls back to native `gcc`. Package tag is `$(echo $TOOLCHAIN_PREFIX | cut -d- -f2)` or `uname -m` for native.

## Gotchas
- **Env sourcing order matters**: `source x-compile.sh <target> env bare` must precede `./build_hoedown.sh <prefix>`.
- **`BUILD`/`OUTPUT` are now clean**: fixed in `build_hoedown.sh` to `rm -rf "$OUTPUTDIR" "$BUILDDIR"` unconditionally; `build_all.sh` further stages each arch to `dist/` so overwrites are safe. For manual runs, `rm -rf BUILD OUTPUT` still works for extra hygiene.
- **Two Android scripts**: root `build-android.sh` and `hoedown/build-android.sh` are near-identical (API 18 for armeabi-v7a with `-Wl,--fix-cortex-a8 -march=armv7-a`, API 21 for arm64-v8a, NDK r23c at `/usr/local/android/android-ndk-r23c`). Android CFLAGS are size-optimized (`-Os -ffunction-sections -fdata-sections -Wl,--gc-sections -Wl,-s`) → ~30% smaller than koxtoolchain builds (`CFLAGS=-g -O3`); **do NOT add `-fvisibility=hidden`** — hoedown has no visibility annotations, hidden + `--gc-sections` produces 2.5K empty libs (`dynsym 3`, `0 hoedown`, `.text 68B`). Fixed in `15e082c`; verified inside NDK container with `llvm-readelf` (hidden 2.5K/0 hoedown vs fixed 48K/45 hoedown).
- **`gethoedown.lua` only runs inside KOReader**: depends on `ffi/loadlib`, `socket.http`, `rapidjson` from KOReader's `common/` and `frontend/`. Cannot test with plain `lua`/`luajit`. `GITHUB_PROXY=""` is truthy in Lua (`""` != nil), so `if GITHUB_PROXY then` always prepends (harmless when empty); set to URL prefix like `https://gh.llkk.cc/` to enable.
- **No CI / no pre-commit**: no `.github/workflows`, no `opencode.json`, no formatter. Do not add CI assumptions.
- **Do not commit clones**: `hoedown/`, `BUILD/`, `OUTPUT/`, `*.tgz`, `lua-resty-hoedown/` are gitignored/untracked intentionally. The consumer's `lib/*.so.3` ARE committed.

## Conventions
- Shell scripts use `set -e`; keep it.
- `build-android.sh` comments are in Chinese — preserve when editing.
- Artifact naming: `lua-hoedown_<platform>.tgz` where platform tag maps to plugin subdir as above; `gethoedown.lua` does substring match `asset.name:find(tag)`.
