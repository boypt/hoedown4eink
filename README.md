# hoedown4eink

This project provides build scripts to compile `libhoedown` and `lua-resty-hoedown` for e-ink devices running KOReader. The primary goal is to enable native Markdown rendering support for the [assistant.koplugin](https://github.com/omer-faruq/assistant.koplugin).

The release assets are cross-compiled using the KOReader koxtoolchain.

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

| Device / Platform         | Platform Tag  | Release Asset             |
|---------------------------|---------------|---------------------------|
| Kindle PW3/Oasis 2        | `kindlepw2`   | `lua-hoedown_kindlepw2.tgz` |
| Kobo H2O/Libra 2/Clara HD | `kobo`        | `lua-hoedown_kobo.tgz`    |
| Remarkable 1              | `kobo`        | `lua-hoedown_kobo.tgz`    |
| Linux x86_64              | `x86_64`      | `lua-hoedown_x86_64.tgz`  |

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

If you want to compile the binaries yourself, you'll need to set up the KOReader koxtoolchain.

### Native Build

For a native build (e.g., on `Linux x86_64`), simply run the build script:
```sh
./build_hoedown.sh
```

### Cross-Compilation

1.  **Generate the toolchain** for your target device using [koxtoolchain](https://github.com/koreader/koxtoolchain).
    ```sh
    # From your koxtoolchain directory
    ./gen-tc.sh kobo
    ./gen-tc.sh kindlepw2
    ```

2.  **Source the environment** for your target.
    ```sh
    # Example for Kobo
    source /path/to/koxtoolchain/refs/x-compile.sh kobo env bare

    # Example for Kindle
    source /path/to/koxtoolchain/refs/x-compile.sh kindlepw2 env bare
    ```

3.  **Run the build script** with the correct toolchain prefix. You can find the prefix by listing the contents of the `x-tools` directory in your toolchain.
    ```sh
    # Example for Kobo
    ./build_hoedown.sh arm-kobo-linux-gnueabihf

    # Example for Kindle
    ./build_hoedown.sh arm-kindlepw2-linux-gnueabi
    ```

