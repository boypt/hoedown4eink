# hoedown4eink
shell script to build libhoedown and lua-resty-hoedown for eink devices (KOReader)

This script is aiming at providing hoedown native support for `asstiant.koreader`.

The release files are crosscompiled using KOReader's [koxtoolchain](https://github.com/koreader/koxtoolchain).

Below are tested device / platform for different tagged version.

Download from the release page.

| Device            | Hoedown file|
|-------------------|-------------|
| Kindle PW3/Oasis 2| lua-hoedown_kindlepw2.tgz |
| Kobo H2O/Libra 2/Clare BW | lua-hoedown_kobo.tgz |
| Remarkable 1      | lua-hoedown_kobo.tgz   |
| Linux x86_64      | lua-hoedown_x86_64.tgz |

## Install
```sh
# download the lua-hoedown_XXXX.tgz and `hoeins` to KOReader's directory
# open Termintal (Menu->Tools->More Tools>Terminal emulator->Open terminal session)

# enter below commands
sh hoeins

# once finished, the files `hoeins` and lua-hoedown_XXXX.tgz are removed.
```

Then restart KOReader.

## Verify hoedown is working
```sh
# open Termintal (Menu->Tools->More Tools>Terminal emulator->Open terminal session)

grep markdown crash.log
```

A line like this means the plugin is using hoedown.

`07/22/25-16:14:44 INFO  Using hoedown (C binding) for markdown parsing`

## Build your own

setup [koxtoolchain](https://github.com/koreader/koxtoolchain). and setup the target env you need.

#### example

```sh
./gen-tc.sh kobo
./gen-tc.sh kindlepw2

# check x-tools for toolchain prefix
ls ../x-tools

# building the kindlepw2
source ./koxtoolchain/refs/x-compile.sh kindlepw2 env bare
./build_hoedown.sh arm-kindlepw2-linux-gnueabi

# building the kobo
source ./koxtoolchain/refs/x-compile.sh kobo env bare
./build_hoedown.sh arm-kobo-linux-gnueabihf

# building natively
./build_hoedown.sh
```
