# Using and making the SDKs

The short version is in [../README.md](../README.md).

| Tarball | Builds for |
|---|---|
| `sdk_windows.tar.gz` | Windows x64 |
| `sdk_linux_amd64.tar.gz` | Linux x86-64, Ubuntu 26.04 or newer |
| `sdk_linux_arm64.tar.gz` | Linux arm64, Ubuntu 26.04 or newer (Raspberry Pi) |
| `sdk_macos_amd64.tar.gz` | macOS 12 or newer, Intel |
| `sdk_macos_arm64.tar.gz` | macOS 12 or newer, Apple silicon |

Each one is made on its own and holds its own clang 23, its own target system (the sysroot) and OnAir's libraries.

## All options of build_sdk.sh and build_sdk.bat

| Argument | Meaning |
|---|---|
| `--windows` `--linux_amd64` `--linux_arm64` `--macos_amd64` `--macos_arm64` | The SDKs to make. Without any, it asks. |
| `--docker` | Build in the safe container: no root, no Linux capabilities, a pinned base image, and this folder read-only except `cache/` and `build/`. |
| `--keep-sources` | Keep unpacked copies of the libraries' sources in `kept_sources/`, as downloaded. Default: no. |
| `--keep-build-artif` | Keep the unpacked SDK in `build/` and, for libraries compiled in this run, their build folders in `cache/work/`. Libraries that come from `cache/built/` have no build folder. Default: each is deleted as soon as it is done with. |
| `--build-onair` | Afterwards, check out OnAir's `clang_and_packaging` branch and build its installers with these SDKs, into `installers/`. It logs the commands and its progress, the compilers' output goes to a log, and an error stops it. OnAir's build folders are deleted as soon as each platform is done. |
| `--dry-run` | Show what would happen (`build_sdk.sh` only). |

* Without arguments, the script asks which SDKs to make, whether to build in the Docker safe build (default: no on Ubuntu 26.04, yes elsewhere), whether to keep the build artifacts, and whether to build OnAir afterwards.
* The tarballs and a `SHA256SUMS` file end up in the top folder.
* If a tarball is already there and matches `SHA256SUMS`, `build_sdk.sh` asks whether to skip making it (default: yes). Without a terminal, it makes it again.
* `cache/` is never deleted, so a second run reuses the downloads and the built libraries. Every download is checked against the hash in the lock files.
* To limit the CPUs, run it under `taskset`. A Docker build takes over the same CPUs: `taskset -c 4-7 ./build_sdk.sh --docker --windows`.
* On a Mac with Apple silicon, Docker runs the build under emulation, which is slow.
* `build_sdk.bat` runs the build in Docker, or in WSL if you answer no to Docker.

## Using each SDK directly

Unpack it anywhere and source its environment. A shell holds one SDK at a time, so use a new shell for another platform. Everything below assumes this `hello.cpp`:

```cpp
#include <cstdio>
int main() { puts("hello"); }
```

### Windows

```bash
tar xzf sdk_windows.tar.gz
. ./environment_windows.sh

cmake -S . -B build-win -G Ninja -DCMAKE_BUILD_TYPE=Release && cmake --build build-win
$CXX hello.cpp -o hello.exe                  # or without CMake
sysroot_windows/collect_dlls.sh hello.exe    # copies the DLLs it needs next to it
```

Linking a library's `pkg-config` flags by hand also needs `-lpthread`, which CMake builds get from the toolchain file.

### Linux x86-64

```bash
tar xzf sdk_linux_amd64.tar.gz
. ./environment_linux_amd64.sh

cmake -S . -B build-linux -G Ninja -DCMAKE_BUILD_TYPE=Release && cmake --build build-linux
$CXX hello.cpp -o hello
```

### Linux arm64

```bash
tar xzf sdk_linux_arm64.tar.gz
. ./environment_linux_arm64.sh

cmake -S . -B build-arm64 -G Ninja -DCMAKE_BUILD_TYPE=Release -DRPI_CPU=generic && cmake --build build-arm64
$CXX hello.cpp -o hello
```

The default CPU is the Raspberry Pi 5's. `-DRPI_CPU=generic` runs on any 64-bit ARM.

### macOS Intel and Apple silicon

```bash
tar xzf sdk_macos_arm64.tar.gz               # or sdk_macos_amd64.tar.gz
. ./environment_macos_arm64.sh               # or environment_macos_amd64.sh

cmake -S . -B build-mac -G Ninja -DCMAKE_BUILD_TYPE=Release && cmake --build build-mac
$CXX hello.cpp -o hello
```

For an app, `sysroot_macos_arm64/collect_dylibs.sh <program> <folder> "$MAC_SYSROOT"` copies the libraries it needs. Signing and disk image tools are included: `rcodesign`, `hfsplus` and `dmg`.

## What the package target does

With an SDK sourced, OnAir's `cmake --build build --target package` builds the programs that are shipped and runs `tools/package/sdk/` for that platform. It uses the tools in the SDK, and the installers end up in `build/packages/`.

## What is in a tarball

```
sysroot_<arch>/          the compiler and tools, the target system, OnAir's libraries, toolchain-*.cmake
sysroot_<arch>/LICENSES.txt   every part with its version, licence and the folder of its licence text
environment_<arch>.sh    source this
```

* **Compiled here, from pinned sources:** OnAir's 15 libraries (FFmpeg as LGPL, libusb, OpenSSL, GLFW, the radio libraries), and for macOS `dmg`, `hfsplus` and `rcodesign`.
* **Prebuilt, from upstream:** clang, Rust, and the target system: MSYS2 packages for Windows, Ubuntu packages for Linux, Apple's SDK and conda-forge packages for macOS.
* **Packaging tools, only for their platform:** `makensis` in the Windows SDK; `mkfs.hfsplus`, `hfsplus`, `dmg` and `rcodesign` in the macOS SDKs; none in the Linux SDKs (a `.deb` is made with the build machine's `dpkg-deb`). The GNU binutils for MinGW are only in the Windows SDK.

## Licences

Sourcing an environment script prints `LICENSES.txt`: each part of the SDK, its version, its licence and where its licence text is. `ONAIR_SDK_QUIET=1` before sourcing leaves the list out. The licence texts are in:

| Folder in `sysroot_<arch>/` | What |
|---|---|
| `LICENSES.txt` | the list |
| `licenses/common-licenses/` | the standard texts (GPL, LGPL, Apache, MPL ...) that Ubuntu's copyright files refer to |
| `sysroots/x86_64-sdk-linux/share/licenses/` | LLVM, Rust, GNU binutils for MinGW |
| `sysroots/x86_64-sdk-linux/pkgtools/share/licenses/` | the packaging tools |
| `sysroots/x86_64-w64-mingw32/share/licenses/` | Windows: the MSYS2 packages and the libraries built from source |
| `sysroots/<triple>/usr/share/licenses/` | Linux: the Ubuntu packages (their `copyright` files) |
| `sysroots/<triple>/usr/local/share/licenses/` | Linux and macOS: the libraries built from source; macOS: the conda-forge packages |

`common/make_licenses.py` writes the list at the end of every SDK build, and stops the build when a part has no licence text or no licence in `common/licenses.map`.

## Before you share a tarball

**Do not publish the macOS tarballs.** They contain Apple's SDK, which Apple's terms do not allow redistributing and limit to Apple-branded computers. Each user should make their own with this script.

The Windows and Linux tarballs may be shared under the licences of their parts:

* **The licence texts** are in the tarball (see [Licences](#licences)); keep them with it.
* **The source of the GPL, LGPL and MPL parts** must be offered with the exact versions shipped: put it next to the tarball. That is the source archives in `cache/src/` (the libraries, with this repository's `sources/patches/`), the Ubuntu source packages of the `.deb` files in the Linux lock files and the MSYS2 source packages of the Windows lock file. This repository at the commit that made the tarball is the build scripts.
* **`FTD3XX.dll`** in the Windows SDK is FTDI's proprietary D3XX library (LimeSDR-USB), under [FTDI's driver licence terms](https://ftdichip.com/driver-licence-terms-details/). Read them before sharing; the text is not in the tarball, because FTDI's site cannot be downloaded from a script. Save it as text in `common/licenses/ftdi/` and the next build includes it.

The scripts in this repository are fine to share.

## Other documents

* [WHY-CLANG.md](WHY-CLANG.md): reproducibility across architectures, speed, code safety checks.
* [DETAILS.md](DETAILS.md): the design, the sources of every part, how to update the SDK.
* [reports/](reports/): the clang build, test and GCC comparison, and the packaging plan.
