# Cross SDK for building OnAir for Windows x64, Linux x86-64, Raspberry Pi 5 and macOS (arm64 and Intel)

A Yocto-style SDK for a Linux x86-64 build machine (Ubuntu 26.04). It is one folder with:

* **the tools that run on the build machine** (the native sysroot): LLVM 23.1.5 clang/lld (also ld64.lld and the Mach-O
  tools), the GNU mingw-w64 binutils and Rust 1.99.1;
* **one target sysroot per target**, with the headers and libraries of that target, its `environment-setup-*`
  script and its CMake toolchain file. In Yocto's words, *"the matching target sysroot contains needed headers and
  libraries for generating binaries that run on the target architecture"*.

All targets use the **same clang 23**. **Nothing is compiled**: every library is a binary package, downloaded,
checked (GPG signatures, sha256) and unpacked. Nothing is installed in the system, and neither Windows nor MSYS2 is
needed. The SDK folder can be moved, and lock files pin every file by sha256.

| Target | Sysroot | Where it comes from |
|---|---|---|
| Windows x64, UCRT (`x86_64-w64-mingw32`) | `sysroots/x86_64-w64-mingw32` | 141 **MSYS2 UCRT64** packages (GCC 16.2 runtime, mingw-w64, GLFW, libusb, OpenSSL, HackRF, SoapySDR, iconv, zlib, FFmpeg ...) |
| Linux x86-64 (`x86_64-linux-gnu`) | `sysroots/x86_64-linux-gnu` | 233 **Ubuntu 26.04** packages (glibc 2.43, GCC 16's libstdc++, GLFW, libusb, OpenSSL, HackRF, SoapySDR, GL/X11, FFmpeg ...) |
| Raspberry Pi 5 (`aarch64-linux-gnu`) | `sysroots/aarch64-linux-gnu` | 231 **Ubuntu 26.04 arm64** packages, the same list and archive snapshot as Linux x86-64 |
| macOS arm64 (`arm64-apple-darwin`) | `sysroots/arm64-apple-darwin` | **Apple's macOS 26.5 SDK** (Command Line Tools for Xcode 26.6, from Apple's software update server) + 97 **conda-forge** osx-arm64 packages in `usr/local` (LLVM libc++ 23.1.5, GLFW, libusb, OpenSSL, HackRF, SoapySDR, zlib, FFmpeg ...) |
| macOS Intel (`x86_64-apple-darwin`) | `sysroots/x86_64-apple-darwin` | the same SDK + 79 conda-forge osx-64 packages |
| all | FFmpeg | **for now each repository's own GPL build** (owner, 2026-11-07): MSYS2's 9.0.2, Ubuntu's 8.0.1 (x86-64 and arm64), conda-forge's 9.0.2. LGPL is to be sorted out later |

### Versions: Ubuntu 26.04 is the minimum

Ubuntu 26.04 LTS sets the minimum version of every library OnAir calls (Linux x86-64 and the Raspberry Pi 5 use
Ubuntu's own). Windows takes MSYS2's current packages and macOS conda-forge's, which may be newer. `common/check_versions.py` checks this on every `make_sdk.sh` and stops the SDK
if a Windows or macOS library is older (the table is in `sdk/VERSIONS.txt`):

| Library | Ubuntu 26.04 = Linux (minimum) | Windows (MSYS2) | macOS arm64 and x86_64 (conda-forge) |
|---|---|---|---|
| FFmpeg (GPL builds) | 8.0.1 (libavcodec 62) | 9.0.2 (avcodec-63.dll) | 9.0.2 (libavcodec 63) |
| GLFW | 3.4 | 3.5.1 | 3.5.1 |
| libusb | 1.0.29 | 1.0.30 | 1.0.30 |
| OpenSSL | 3.5.5 (+ Ubuntu's security patches, 3.5.5-1ubuntu3.7) | 3.6.5 | 3.6.5 (conda-forge's FFmpeg needs OpenSSL 3; 4.1 would come without it) |
| HackRF | 2026.01.3 | 2026.01.3 | 2026.01.3 |
| SoapySDR | 0.8.1 | 0.8.1 | 0.9.0 |
| zlib | 1.3.1 | 1.4 | 1.3.2 |
| C++ runtime | GCC 16 libstdc++ (16-20260322) | GCC 16.2 libstdc++ | LLVM libc++ 23.1.5 (conda-forge's, shipped with the program) |
| OS | Ubuntu 26.04 (x86-64; arm64 on the Pi 5) | Windows 10/11 (UCRT) | **macOS 12 Monterey or newer** |

```
sdk/
  environment-setup-x86_64-w64-mingw32   Windows: . it (PATH, CMAKE_TOOLCHAIN_FILE, CC/CXX/AR..., PKG_CONFIG_*, RUSTC/CARGO)
  toolchain-x86_64-w64-mingw32.cmake     ... or cmake -DCMAKE_TOOLCHAIN_FILE=<this>
  toolchain-x86_64-w64-mingw32-rules.cmake  read by it: links winpthreads (-lpthread) by default, as MSYS2's GCC does
  collect_dlls.sh                        Windows: the DLLs a built .exe needs, from the target sysroot
  environment-setup-x86_64-linux-gnu     Linux: . it
  toolchain-x86_64-linux-gnu.cmake       ... or cmake -DCMAKE_TOOLCHAIN_FILE=<this>
  environment-setup-aarch64-linux-gnu    Raspberry Pi 5: . it
  toolchain-aarch64-linux-gnu.cmake      ... or cmake -DCMAKE_TOOLCHAIN_FILE=<this>
  locks/  VERSIONS.txt  SDK-MANIFEST.txt  LICENSE
  sysroots/
    x86_64-sdk-linux/     native, 1.5 GB: llvm/ (clang, lld, llvm-*), deb/ (mingw-w64 binutils), rust/ (rustc, cargo, std
                          for Linux x86-64/arm64, Windows, macOS); bin/ = all of them, the folder to put on PATH
    x86_64-w64-mingw32/   Windows target, 1.4 GB
    x86_64-linux-gnu/     Linux target, 0.4 GB
    aarch64-linux-gnu/    Raspberry Pi 5 target, 0.4 GB
    arm64-apple-darwin/   macOS arm64 target, 1.1 GB: Apple's SDK (System/, usr/) + conda-forge in usr/local
    x86_64-apple-darwin/  macOS Intel target, 0.9 GB
  environment-setup-arm64-apple-darwin  toolchain-arm64-apple-darwin.cmake    macOS arm64: . it, or the toolchain file
  environment-setup-x86_64-apple-darwin toolchain-x86_64-apple-darwin.cmake   macOS Intel
  toolchain-apple-darwin-common.cmake  collect_dylibs.sh  macho.py            macOS: shared toolchain part; the dylibs to ship
```

## The files in this repository

```
make_sdk.sh                  makes sdk/: runs the scripts below, adds the SDK files (--target, --update, --tar, -o)
common/                      for all targets
  fetch_toolchain.sh           the native sysroot: LLVM, binutils, Rust (versions at the top)
  toolchain.lock               its exact files
  check_versions.py            Ubuntu 26.04's versions as the minimum for Windows, macOS and the Pi 5
windows/
  fetch_sysroot.sh             the Windows target sysroot from repo.msys2.org (package list at the top)
  msys2.sh                     MSYS2's repositories and signature trust (sourced by fetch_sysroot.sh)
  sysroot.lock                 its exact packages
  toolchain-x86_64-w64-mingw32.cmake  toolchain-x86_64-w64-mingw32-rules.cmake  environment-setup-x86_64-w64-mingw32  collect_dlls.sh
macos/
  fetch_sysroot.sh             a macOS target sysroot (--arch arm64|x86_64): Apple's SDK + conda-forge (PACKAGES, MACOS_MIN at the top)
  apple_sdk.py                 Apple's catalog, the package signature check, the xar/pbzx/cpio unpacker
  conda_index.py               conda-forge's dependency resolver (conda's version order, match specs) and package unpacker
  macho.py                     Mach-O reader: checks the sysroot's dylibs (deployment target, every load found); collects dylibs
  sysroot-arm64.lock  sysroot-x86_64.lock   the SDK package and the exact conda packages per architecture
  toolchain-{arm64,x86_64}-apple-darwin.cmake  toolchain-apple-darwin-common.cmake  environment-setup-*-apple-darwin  collect_dylibs.sh
linux/
  fetch_sysroot.sh             a Linux target sysroot from Ubuntu's archive (--arch amd64|arm64; package list and MINIMUM at the top)
  ubuntu_index.py              its dependency resolver (Debian version order, alternatives, Provides)
  sysroot.lock  sysroot-arm64.lock   the archive snapshot, the minimum versions and the exact packages (x86-64, Pi 5)
  toolchain-x86_64-linux-gnu.cmake  environment-setup-x86_64-linux-gnu
  toolchain-aarch64-linux-gnu.cmake  environment-setup-aarch64-linux-gnu
LICENSE (GPL-3.0-or-later, like OnAir), .gitignore, README.md, .claude/STATUS.md (work status)
sdk/, sdk.tar.zst            the SDK (6.3 GB): not published, binaries
cache/                       the downloads (llvm, msys2, rust, deb, ubuntu, apple, conda): not published; rebuilds need no network
```

`.gitignore` keeps all binaries out, so `git init && git add . && git commit` publishes the scripts and lock files only.
The binaries are third-party software under their own licences (`sdk/SDK-MANIFEST.txt`). **FFmpeg is the GPL build on
every target for now** (MSYS2's, Ubuntu's and conda-forge's are `--enable-gpl --enable-version3`, with x264/x265): a
program that links it is distributed under the GPL-3.0. The LGPL question is open (owner, 2026-11-07).

---

## 1. On the Ubuntu 26.04 build machine

```bash
sudo apt install cmake ninja-build pkgconf git curl zstd xz-utils unzip gpg gpgv python3
#   cmake ninja-build pkgconf          the builds (CMake 3.21+ reads CMAKE_TOOLCHAIN_FILE from the environment)
#   curl zstd xz-utils unzip gpg gpgv  make_sdk.sh: download, unpack, check signatures
#   python3                            make_sdk.sh: the Ubuntu dependency resolver and the version check
# optional: run the Windows programs and tests on Linux
sudo apt install wine
```

That is all. No `clang`, `gcc-mingw-w64`, `libfoo-dev` or `rustup` from apt: they are in the SDK. The build machine's
own headers and libraries are never used, so the result is the same on every machine.

Then make the SDK there, or copy one made elsewhere:

```bash
git clone <this repository> ~/onair_windows_sysroot && cd ~/onair_windows_sysroot
./make_sdk.sh                         # -> ./sdk, both targets, from the lock files (about 1.6 GB of downloads the first time)
./make_sdk.sh --target linux          # only one target (windows | linux | macos | macos-arm64 | macos-x86_64 | all)
./make_sdk.sh --tar                   # ... and ./sdk.tar.zst, to copy to other machines

# or: unpack a copied SDK anywhere
tar -I 'zstd -d' -xf sdk.tar.zst -C ~ && mv ~/sdk ~/onair-sdk
```

## 2. Build OnAir for Windows

```bash
SDK=~/onair_windows_sysroot/sdk          # wherever the SDK is
. $SDK/environment-setup-x86_64-w64-mingw32

cd ~/OnAir
cmake --fresh -S . -B build-win -G Ninja \
      -DCMAKE_BUILD_TYPE=Release -DDECT2_BUILD_APP=ON -DDECT2_BUILD_TESTS=OFF
cmake --build build-win -j$(nproc) --target dect2          # build-win/dect2.exe

# the DLLs dect2.exe needs, recursively, from the target sysroot (FFmpeg is delay-loaded: name it explicitly)
$SDK/collect_dlls.sh build-win/dect2.exe "" 'avutil-*.dll' 'swresample-*.dll' 'swscale-*.dll' \
      'avcodec-*.dll' 'avformat-*.dll' 'avdevice-*.dll'
```

Without the environment script, the toolchain file alone does the same:
`cmake ... -DCMAKE_TOOLCHAIN_FILE=$SDK/toolchain-x86_64-w64-mingw32.cmake`. It finds the SDK's tools next to itself,
and points OnAir's `ONAIR_CARGO`/`ONAIR_RUSTC` at the SDK's Rust.

Then copy `build-win/dect2.exe`, all the `*.dll` next to it, and OnAir's data (as its Windows package lays it out) to
a Windows PC. `wine build-win/dect2.exe` is a quick check on Linux.

Notes for OnAir on Windows:

* **Do not use** `-DDECT2_COPY_RUNTIME_DLLS=ON`: it searches the compiler's folder for DLLs, which is only right in a
  native MSYS2 build. Use `collect_dlls.sh` (above), or OnAir's own script:
  `cmake -DEXE=build-win/dect2.exe -DSEARCH_DIR=$WIN_SYSROOT/bin -DOBJDUMP=x86_64-w64-mingw32-objdump -P packaging/windows/copy_runtime_dlls.cmake`.
* Leave out `-DDECT2_WIN_AVX2=ON` and `-march=native`. On a cross build "native" means the build machine's CPU.
* `dect2cli`, `onair-server`, and the tests (`-DDECT2_BUILD_TESTS=ON`) build the same way. Run the tests on Windows or
  with wine (`-DCMAKE_CROSSCOMPILING_EMULATOR=wine`).
* FFmpeg's DLL names (avcodec-63, avutil-61, swscale-10 ...) are those of FFmpeg 9.0, as OnAir's delay-load list
  (`cmake/FfmpegDelayLoad.cmake`) expects.

Windows toolchain options:

| Option | Default | What |
|---|---|---|
| `CMAKE_SYSROOT` | `$WIN_SYSROOT`, else `sysroots/x86_64-w64-mingw32` next to the toolchain file | the target sysroot |
| `WIN_LINKER` | `bfd` | `bfd` = GNU ld (`x86_64-w64-mingw32-ld`), `lld` = LLVM lld (in the SDK; not tested with OnAir) |
| `WIN_STATIC` | `OFF` | `ON` links with `-static`: libgcc, libstdc++, winpthreads and every `-lX` from `libX.a`. Keep `OFF` when C++ DLLs such as SoapySDR's are used: they must share one C++ runtime DLL with the program |

## 3. Build OnAir for Linux

```bash
SDK=~/onair_windows_sysroot/sdk
. $SDK/environment-setup-x86_64-linux-gnu

cd ~/OnAir
cmake --fresh -S . -B build-linux -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build-linux -j$(nproc)
```

Or `-DCMAKE_TOOLCHAIN_FILE=$SDK/toolchain-x86_64-linux-gnu.cmake` without the environment script. The toolchain file:

* compiles with the SDK's `x86_64-linux-gnu-clang` / `x86_64-linux-gnu-clang++`. That is clang 23 run under the target's
  name, so it reads `sysroots/x86_64-sdk-linux/llvm/bin/x86_64-unknown-linux-gnu.cfg`, which gives it the target sysroot
  (relative to the file) and lld. `-DCMAKE_SYSROOT=` or `LINUX_SYSROOT` picks another sysroot;
* lets pkg-config and `find_*` look only in the target sysroot;
* sets `ONAIR_CARGO` / `ONAIR_RUSTC` to the SDK's Rust.

The program runs on Ubuntu 26.04 and newer. GLFW, libusb, OpenSSL, HackRF, SoapySDR, X11/GL are Ubuntu 26.04's shared
libraries, so the target needs their runtime packages (`libglfw3 libusb-1.0-0 libssl3t64 libhackrf0 libsoapysdr0.8 ...`;
`readelf -d build-linux/dect2 | grep NEEDED` lists them). FFmpeg is Ubuntu's 8.0.1 too (`libavcodec62 libavformat62
libavutil60 libswscale9 ...`), so nothing has to be shipped with the program.

## 3a. Build OnAir for the Raspberry Pi 5

```bash
. $SDK/environment-setup-aarch64-linux-gnu          # or -DCMAKE_TOOLCHAIN_FILE=$SDK/toolchain-aarch64-linux-gnu.cmake
cmake --fresh -S . -B build-rpi5 -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build-rpi5 -j$(nproc)
```

The same as Linux x86-64, with Ubuntu 26.04's **arm64** packages (the same package list and archive snapshot, so the
same versions) and the compiler names `aarch64-linux-gnu-clang(++)` (`llvm/bin/aarch64-unknown-linux-gnu.cfg`). The
code is built for the Pi 5's CPU, `-mcpu=cortex-a76`; `-DRPI_CPU=generic` builds for any 64-bit ARM (Pi 4 ...). The
environment script also points cargo at `aarch64-unknown-linux-gnu` with the SDK's linker.

* **The Pi runs Ubuntu 26.04 (64-bit)**, Ubuntu's Raspberry Pi image, with the runtime packages as on x86-64. Raspberry
  Pi OS (Debian 13 "trixie") is **not** a target: its glibc (2.41) and libraries (libusb 1.0.28, FFmpeg 7.1) are older
  than Ubuntu 26.04's, the SDK's minimum, so programs built here do not start there.
* Checked: a C++23 program with GLFW, libusb, OpenSSL, SoapySDR and libavcodec/libavformat/libswscale builds with
  CMake and with `$CXX` directly, and **runs under `qemu-aarch64 -L <sysroot>`** (prints GLFW 3.4.0, libusb 1.0.29,
  OpenSSL 3.5.5, SoapySDR 0.8.1, libavcodec 62.11.100); a Rust program builds with `cargo build`. Not yet run on a Pi.

OnAir's other Linux FFmpeg option, `-DDECT2_FFMPEG_PREFIX=<prefix>` with `tools/package/build_ffmpeg_static.sh`
(a static FFmpeg it builds itself), still works with this SDK: build that FFmpeg with the SDK's compiler.

## 3b. Build OnAir for macOS (arm64 or Intel)

```bash
SDK=~/onair_windows_sysroot/sdk
. $SDK/environment-setup-arm64-apple-darwin          # or environment-setup-x86_64-apple-darwin (Intel)

cd ~/OnAir
cmake --fresh -S . -B build-mac-arm64 -G Ninja -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_BUILD_RPATH=@executable_path/lib -DCMAKE_INSTALL_RPATH=@executable_path/../Frameworks
cmake --build build-mac-arm64 -j$(nproc)

# the dylibs the program needs (conda-forge's libraries and libc++), recursively, into a folder its rpath names
$SDK/collect_dylibs.sh build-mac-arm64/dect2 build-mac-arm64/lib
```

Or `-DCMAKE_TOOLCHAIN_FILE=$SDK/toolchain-arm64-apple-darwin.cmake` without the environment script. Outside CMake,
`arm64-apple-darwin-clang(++)` / `x86_64-apple-darwin-clang(++)` carry everything (`llvm/bin/<triple>.cfg`: sysroot,
deployment target, libc++, ld64.lld). A universal binary: build both and join them with `llvm-lipo -create`.

* **C++ runtime: conda-forge's libc++ 23.1.5**, not the SDK's. The sysroot's C++ libraries (SoapySDR ...) are built
  against it, and SoapySDR's C++ API passes `std::string`/`std::vector` across, so the program must use the same one.
  It is LLVM's libc++ of the same release as clang. The toolchain sets `-stdlib++-isystem <sysroot>/usr/local/include/c++/v1`,
  `-L<sysroot>/usr/local/lib` and `-D_LIBCPP_DISABLE_AVAILABILITY` (the headers' "introduced in macOS 13.3" markings are
  about Apple's system libc++; the shipped one has everything), as conda-forge does. Programs load `@rpath/libc++.1.dylib`.
* **Ship the dylibs**: every conda-forge library has an `@rpath/...` install name. `collect_dylibs.sh` copies what a
  program (and extra dylibs given as globs, e.g. SoapySDR modules) needs; give the program a matching rpath
  (`@executable_path/../Frameworks` in an `.app`). A test program with GLFW, libusb, OpenSSL, SoapySDR and libavcodec
  needs 60 dylibs (most of them FFmpeg's).
* **macOS 12 or newer**: conda-forge's arm64 FFmpeg needs it (through OpenVINO). `macos/macho.py check` verifies every
  dylib in the sysroot against `MACOS_MIN`; the toolchain refuses an older `CMAKE_OSX_DEPLOYMENT_TARGET`.
* **Signing**: ld64.lld gives arm64 programs the ad-hoc signature macOS needs to run them. Changing a binary afterwards
  (`llvm-install-name-tool`, `llvm-strip`) needs a new signature on a Mac (`codesign -s - -f`), and a distributed app
  needs Developer ID signing and notarisation on a Mac. conda-forge's dylibs are not changed by the SDK.
* Not tested yet: running a program built this way on a Mac (no Mac here). The test program above links for both
  architectures and has the expected load commands (`macho.py deps`).

## 4. Change or update the SDK

* **Another Windows library:** add it to `PACKAGES` at the top of `windows/fetch_sysroot.sh` (short MSYS2 names:
  `hamlib`, `libuhd` ...; look them up at <https://packages.msys2.org/>, environment UCRT64).
* **Another Linux library:** add its `-dev` package to `PACKAGES` at the top of `linux/fetch_sysroot.sh`
  (<https://packages.ubuntu.com/resolute/>).
* **Another macOS library:** add its conda-forge name to `PACKAGES` at the top of `macos/fetch_sysroot.sh`
  (<https://conda-forge.org/packages/>, both osx-arm64 and osx-64).
* **Keep their versions in step:** add the library to `MINIMUM` in `linux/fetch_sysroot.sh` and to `LIBRARIES` in
  `common/check_versions.py`.
* Then `./make_sdk.sh --update`: the newest MSYS2 packages, a new Ubuntu snapshot (the same one for x86-64 and the Pi 5),
  the newest Command Line Tools and conda-forge packages, and new lock files. The version check runs at the end.
* **FFmpeg** is a package like the others: `ffmpeg` in `windows/fetch_sysroot.sh` and `macos/fetch_sysroot.sh`
  (`'ffmpeg=*=gpl_*'`; `lgpl_*` for conda-forge's LGPL build), `libav*-dev` in `linux/fetch_sysroot.sh`.
* **Another LLVM or Rust:** change `LLVM_VERSION` / `RUST_VERSION` at the top of `common/fetch_toolchain.sh`, then
  `./make_sdk.sh --update`. The binutils version comes from apt.
* **The same SDK again** (another machine, later): `./make_sdk.sh` with the committed lock files. The Ubuntu packages come
  from the snapshot named in `linux/sysroot.lock` (snapshot.ubuntu.com keeps them). A file that is gone upstream is
  taken from `cache/`. MSYS2 and Apple remove old package versions after a while, so keep
  `cache/` or a copy of `sdk.tar.zst`.
* The parts alone, each with `--help`: `common/fetch_toolchain.sh -o DIR`, `windows/fetch_sysroot.sh -o DIR`,
  `linux/fetch_sysroot.sh [--arch arm64] -o DIR`, `macos/fetch_sysroot.sh --arch arm64|x86_64 -o DIR`.

### How the downloads are checked

| What | From | Checked |
|---|---|---|
| MSYS2 packages | repo.msys2.org/mingw/ucrt64 | `ucrt64.db` GPG signature, each package's sha256 from that db and its own `.sig`. Trusted keys: the 5 MSYS2 **master** keys pinned in `windows/msys2.sh` (MSYS2's `msys2-trusted`), plus the packager keys they certified in the `msys2-keyring` package, minus `msys2-revoked`. That is the same rule pacman uses |
| Ubuntu packages (amd64 and arm64) | snapshot.ubuntu.com/ubuntu/&lt;time&gt; | `InRelease` GPG signature against the Ubuntu Archive Automatic Signing Key (2018), fingerprint pinned in `linux/fetch_sysroot.sh` (F6EC B376 2474 EDA9 D21B 7022 8719 20D1 991B C93C); the `Packages.xz` sha256 from `InRelease`; each .deb's sha256 from `Packages`; all in `linux/sysroot.lock` |
| LLVM | github.com/llvm/llvm-project releases | GPG `.sig` against `releases.llvm.org/release-keys.asc`; sha256 in `common/toolchain.lock` |
| binutils | Ubuntu archive via `apt-get download` | apt checks the signed archive indices; sha256 in `common/toolchain.lock` |
| Apple's macOS SDK | swscan.apple.com catalog, swcdn.apple.com package (Command Line Tools) | the package's xar signature: the sha1 of its table of contents, the RSA signature on it by Apple's "Software Update" certificate, and the chain to **Apple Root CA**, sha256 pinned in `macos/fetch_sysroot.sh` (B0B1 730E CBC7 FF45 0514 2C49 F129 5E6E DA6B CAED 7E2C 68C5 BE91 B5A1 1001 F024); the payload's sha1 from that signed table; sha256 in `macos/sysroot-*.lock` |
| conda-forge packages | conda.anaconda.org/conda-forge (osx-arm64, osx-64, noarch) | sha256 from `repodata.json` over HTTPS (conda-forge publishes **no signatures**); sha256 in `macos/sysroot-*.lock` |
| Rust | static.rust-lang.org | GPG `.asc` against the Rust release key, fingerprint pinned in `common/fetch_toolchain.sh` (108F 6620 5EAE B0AA A8DD 5E1C 85AB 96E6 FA1B E5FE); sha256 in `common/toolchain.lock` |

With a lock file, every file must also have the sha256 written there.

**FFmpeg-Builds (BtbN) is no longer used** (owner, 2026-11-07): FFmpeg comes from each target's own repository, checked
like every other package of that repository.

---

## 5. Context: how this was made and why (for whoever picks this up later)

Made on 2026-11-07 on a Windows 11 PC with WSL2 (Ubuntu 26.04.1, 12 cores) and MSYS2 at `C:\msys64`, for the move to
a native Ubuntu 26.04 build machine. A first version copied the Windows target sysroot out of the local MSYS2
installation. It was replaced by `windows/fetch_sysroot.sh`, which gets the same packages from the MSYS2 repository on
Linux, so Windows is not needed any more. Then the Linux target was added with the same compiler, and the scripts were
split into `common/`, `windows/` and `linux/`.

### 5.1 Decisions

* **Binary packages only, nothing compiled.** Building every package from source for both targets would be a
  distribution's job (about 240 recipes, and each library's security fixes to follow). An intermediate version built
  FFmpeg, GLFW, libusb and OpenSSL from source to give Linux the Windows versions. It was dropped for a simpler rule:
  **Ubuntu 26.04 LTS's versions are the minimum**, Windows may be newer, and `common/check_versions.py` checks it.
  (The other way round, Ubuntu's exact versions on Windows, is not possible from binaries: MSYS2 never had libusb 1.0.29
  or OpenSSL 3.5.5, and its old FFmpeg 8.0.1 package needs DLLs MSYS2 no longer has.)
* **(Replaced 2026-11-07: FFmpeg now comes from MSYS2, Ubuntu and conda-forge, the GPL builds.) Earlier:
  FFmpeg from FFmpeg-Builds, LGPL, the same for both targets.** MSYS2's FFmpeg is the GPLv3 build and Ubuntu's too
  (`--enable-gpl --enable-version3`, x264/x265). The `lgpl-shared` builds are self-contained: the codec libraries are
  linked in, so the Windows sysroot shrank from 141 to 27 MSYS2 packages, and a Windows program needs 16 DLLs instead
  of 118.
* **clang, not GCC, for both targets.** Ubuntu 26.04's mingw-w64 GCC is GCC 13 with **msvcrt**, and it ignores
  `--sysroot` (its header paths are built in). Ubuntu has no UCRT GCC. MSYS2 UCRT64 is GCC 16.2 with UCRT, and its
  libraries need `ucrtbase.dll` and GCC 16's `libstdc++-6.dll`. clang with `--target=x86_64-w64-windows-gnu
  --sysroot=<target sysroot>` uses exactly MSYS2's layout, as clang inside MSYS2 does, and the result has the MSYS2
  UCRT64 ABI. For Linux the same clang uses GCC 16's libstdc++ and crt files from the Ubuntu sysroot
  (`usr/lib/gcc/x86_64-linux-gnu/16`). One compiler for both targets means the same warnings and the same C++ support.
* **LLVM's official release** (23.1.5), not Ubuntu's clang 21: relocatable, newer (a better match for GCC 16's
  headers), and one file. Only the tools a cross build uses are unpacked (`TOOLS` in `common/fetch_toolchain.sh`).
* **The Linux compiler names `x86_64-linux-gnu-clang(++)`** with a clang config file
  (`llvm/bin/x86_64-unknown-linux-gnu.cfg`: `--sysroot=<CFGDIR>/../../../x86_64-linux-gnu`, `-fuse-ld=lld`). clang
  looks for the config file under the normalized triple, next to the real binary. So builds need no path arguments
  (configure scripts that record their command line, such as FFmpeg's, then record no build-machine folders), and the
  SDK can move.
* **Ubuntu packages from snapshot.ubuntu.com**, so a lock file names a fixed archive state and can be replayed later. The
  dependencies are resolved by `linux/ubuntu_index.py`. It uses dpkg's version order (checked against
  `dpkg --compare-versions`), the highest version over release, updates and security, `Depends` and `Pre-Depends`,
  alternatives and `Provides`. Runtime-only packages are left out (`EXCLUDE`: mesa drivers, LLVM, perl, systemd, data
  packages ...). Only headers, libraries, `.pc`/CMake/Wayland-protocol files and the copyright files are kept. The
  merged `/usr` layout is kept (`lib -> usr/lib`), and absolute symlinks become relative.
* **GNU binutils for Windows, downloaded, not built**: Ubuntu's `binutils-mingw-w64-x86-64`, unpacked with `dpkg-deb -x`.
  OnAir's `cmake/FfmpegDelayLoad.cmake` makes delay-import libraries with GNU `dlltool --output-delaylib`, which
  `llvm-dlltool` 23 lacks. GNU ld is the Windows default linker for the same reason; it is named with `--ld-path=`.
  Linux links with lld.
* **Rust** from the standalone tarballs (rustc, cargo, the Linux std and the `x86_64-pc-windows-gnu` std), copied in
  the way their `install.sh` would, without running it. OnAir's Rust code is a `no_std` staticlib with no external
  crates. `bin/cargo` is a wrapper that always sets `RUSTC`/`RUSTDOC` to the SDK's own; without it, cargo took Ubuntu's
  `/usr/bin/rustc` from PATH.
* **Relocatable**: `bin/` holds relative symlinks. The MSYS2 `.pc` files get `prefix=${pcfiledir}/../..`, with other
  absolute ucrt64 paths made `${prefix}`. The Ubuntu `.pc` files
  keep `/usr` and are used with `PKG_CONFIG_SYSROOT_DIR` (pkgconf does not prefix the `${pcfiledir}` paths twice:
  checked).

### 5.2 What was checked

* `make_sdk.sh --update` (both targets): 47 s, 2.3 GB, every download checked; `check_versions.py`: every Windows library
  at or above Ubuntu 26.04's (table above). `make_sdk.sh` again from the lock files into `./sdk`.
* **Linux** test program (C++23 `std::print`, libhackrf, the SoapySDR C++ API, GLFW, libusb, OpenSSL, libavcodec /
  libavformat / libavdevice / libswscale) built with the SDK: it ran on Ubuntu 26.04 and printed hackrf 0.9.2, SoapySDR
  0.8.1, GLFW 3.4.0 (Wayland, X11), libusb 1.0.29, OpenSSL 3.5.5, and FFmpeg n9.0.2-48 "LGPL version 3 or later" with
  the H.264 decoder.
* **Windows** C/C++23 smoke program (FFmpeg incl. libavdevice, GLFW, libhackrf, libusb, SoapySDR, OpenSSL, iconv,
  threads, exceptions, Winsock, a `.rc` resource): built, `collect_dlls.sh` gathered 16 DLLs, and it **ran on Windows**,
  with every library reporting its version (GLFW 3.5.1, libusb 1.0.30, OpenSSL 3.6.5).
* **OnAir for Windows**, with the earlier SDK (MSYS2's FFmpeg): `dect2.exe` (79 MB) and 11 tests in 12 min at `-j8`. On
  Windows, satnogs, packs, datasets, updater, updater_mirror, bandplan, memory_bank, memory_formats, swbc and
  marinevhf_channels pass. `test_specx_idmatrix --quick` gets every identification right but misses 2 timing limits
  (`identify()` 191 ms average against 150, 726 ms worst against 500; without `DECT2_WIN_AVX2`, run through WSL).
* **OnAir for Linux** with an earlier SDK: configure found every library; the build stopped at one clang error in
  OnAir (5.3). OnAir has not been built with this SDK version yet (see `.claude/STATUS.md`).

### 5.5 GPL FFmpeg everywhere, Raspberry Pi 5 (2026-11-07)

* **FFmpeg** (owner: "use the ffmpeg gpl version from the upstream repositories. Do not use btbn anymore, for any
  target"): `ffmpeg` in the MSYS2 list, Ubuntu's `libavcodec-dev libavformat-dev libavutil-dev libswscale-dev
  libswresample-dev libavfilter-dev libavdevice-dev`, conda-forge's `gpl_*` build. `common/fetch_ffmpeg.sh`, its lock
  file and `cache/ffmpeg` were removed. The versions now differ per target: Ubuntu 8.0.1 (libavcodec 62), MSYS2 and
  conda-forge 9.0.2 (63); OnAir's FFmpeg code (and its delay-load list, `avcodec-63.dll` ...) must accept both.
  MSYS2's FFmpeg brings its codec libraries along: the Windows sysroot went from 27 to 141 packages (1.4 GB), and the
  Windows test program needs 101 DLLs (`collect_dlls.sh`), against 16 before. It links with `-lstdc++exp` (std::print).
* **Raspberry Pi 5**: Ubuntu 26.04 arm64 (`linux/fetch_sysroot.sh --arch arm64`), chosen over Raspberry Pi OS because
  the SDK's rule is Ubuntu 26.04's versions as the minimum and Debian 13's are older. Since 26.04 Ubuntu's main archive
  (and snapshot.ubuntu.com/ubuntu) carries arm64; the old ubuntu-ports snapshot path answers 401. `make_sdk.sh --update`
  resolves the Pi with the x86-64 lock's snapshot (`--snapshot`), so both have the same versions; `check_versions.py`
  checks the Pi's minimum lines too. The clang config file is `aarch64-unknown-linux-gnu.cfg` (checked: that is the
  name clang 23 looks for when run as `aarch64-linux-gnu-clang`); Rust's `aarch64-unknown-linux-gnu` std was added.

### 5.4 macOS (added 2026-11-07)

* **Sources.** Homebrew was looked at first: it no longer builds Intel bottles for most packages (no x86_64 OpenSSL,
  SoapySDR, zlib, FFmpeg) and its FFmpeg is GPL. conda-forge builds every library for osx-arm64 and osx-64, keeps old
  packages, and its dylibs use `@rpath` install names, so it is the single macOS source (as MSYS2 is for Windows).
  Apple's SDK comes from Apple's own update server (the Command Line Tools package), not from a third-party SDK mirror.
* **FFmpeg.** No self-contained LGPL macOS build like BtbN's exists: PyAV's `pyav-ffmpeg` macOS builds link x264/x265
  (GPL) while labelling themselves LGPL, so they were not used. conda-forge's `lgpl_*` FFmpeg 9.0.2 is real LGPL but
  pulls in about 75 more packages on arm64 (OpenVINO, libplacebo, Vulkan, SDL, librsvg, GLib ...). The owner chose
  **conda-forge's GPL build for now** (`'ffmpeg=*=gpl_*'` in `PACKAGES`). For LGPL, change it to `'ffmpeg=*=lgpl_*'` and
  run `./make_sdk.sh --target macos --update`. FFmpeg comes first in `PACKAGES`: the solver settles the specs in their
  order, so FFmpeg gets its newest version and decides OpenSSL (3.6.5: conda-forge's FFmpeg needs `openssl <4`).
* **The resolver** (`macos/conda_index.py`) is a small conda solver: conda's version order, match specs, `depends` and
  `constrains`, the virtual package `__osx` (= `MACOS_MIN`), and a backtracking search with conflict-directed
  backjumping (a greedy "newest of each" fails on conda-forge: libharfbuzz 15 and libxml2 wanted different ICUs).
* **Excluded** runtime-only packages: Python (SoapySDR's package has Python bindings), CA certificates, fonts, tzdata.
  OpenSSL and 24 other dylibs keep conda's build prefix compiled in (e.g. OPENSSLDIR): set certificate paths in the
  program if it needs them. The SDK's Swift modules (168 MB) are left out.
* **Licence of Apple's SDK.** The SDK is under Apple's *macOS SDK and Xcode Agreement*, which allows its use only on
  Apple-branded computers and does not allow redistributing it. Using it on Linux (as osxcross and similar tools do) is
  outside that licence; that is the owner's decision. Do not publish `sdk/`, `sdk.tar.zst` or `cache/apple`.
* Apple removes old Command Line Tools from its catalog: keep `cache/apple` to remake an old lock file.

### 5.3 Known issues and things to watch

* **OnAir `main` (25034214) does not compile with clang; partly fixed on branch `fix/clang-json-kv` (4f6a30be).** Five
  small JSON value types (`core/src/channels/memory_json.h`, `engine/updater.cpp`, `net/satnogs.cpp`,
  `packs/datasets.cpp`, `horus/horus_fields.cpp`) hold `std::vector<std::pair<std::string, Self>>`. From C++20 on,
  `std::vector` is constexpr, and clang then needs `std::pair<std::string, Self>` complete inside `Self`. GCC accepts
  it; clang 21 and 23 reject it, for both targets. The portable fix is a key/value struct declared before the type and
  defined after it:
  ```cpp
  struct JKV;
  struct J { ... std::vector<JKV> o; const J* get(const char* k) const; };
  struct JKV { std::string first; J second; };
  inline const J* J::get(const char* k) const { for (const auto& p : o) if (p.first == k) return &p.second; return nullptr; }
  ```
  **Still open** (seen in the Linux test build): `tests/hfdl/test_hfdl_proto_rs.cpp:165` narrows `g() & 0xFFFFF`
  (`unsigned long`) to `uint32_t` in a braced initializer, an error in clang (`-Wc++11-narrowing`), a warning in GCC.
* A **static** FFmpeg linked into a shared object (OnAir's `libSoapyOnAirTest.so` with `DECT2_FFMPEG_PREFIX`) needs
  FFmpeg built with `-fvisibility=hidden`: its x86 CABAC assembly refers to `ff_h264_cabac_tables` PC-relatively, and
  lld/ld stop with `relocation R_X86_64_PC32 cannot be used against symbol 'ff_h264_cabac_tables'`. The SDK's shared
  FFmpeg does not have this problem.
* **winpthreads is linked by default** (`-lpthread` in `CMAKE_<LANG>_STANDARD_LIBRARIES`, set by
  `toolchain-x86_64-w64-mingw32-rules.cmake` through `CMAKE_USER_MAKE_RULES_OVERRIDE`). MSYS2's GCC adds it to every
  link; clang's MinGW driver does not, and libstdc++'s inline `std::mutex` / `std::this_thread` code then fails to link
  (`undefined reference to pthread_mutex_lock`, `nanosleep64`) in targets without `Threads::Threads`. OnAir has six
  such test targets (`fake_plugin`, `fake_plugin_badabi`, `native_fakes`, `test_clips`, `test_latest_slot`,
  `test_fft_bits`). A project that sets its own `CMAKE_USER_MAKE_RULES_OVERRIDE` must add `-lpthread` itself.
* `std::print` / `std::println` need **`-lstdc++exp`** with GCC 16's libstdc++ on MinGW (also in MSYS2). GNU ld then
  prints harmless `libstdc++exp.a(print.o): duplicate section ... has different size` warnings.
* clang compiles against **GCC 16's** libstdc++ headers on both targets. If a header ever uses a GCC builtin clang
  lacks, raise `LLVM_VERSION`.
* SoapySDR's headers include `<ciso646>`, so C++20 builds print a warning about it.
* Ubuntu's `libhackrf.pc` has an empty `Version:`. That is Ubuntu's packaging; `pkg_check_modules(HACKRF libhackrf)`
  works.
* Linux file names are case-sensitive. mingw-w64 headers and import libraries are lower case (`windows.h`,
  `-lws2_32`); `<Windows.h>` or `-lWs2_32` fail (OnAir has none: checked).
* `WIN_LINKER=lld` is in the SDK but untested with OnAir's GNU dlltool delay-load libraries.
* Ship the DLLs and FFmpeg's `.so` files from the **same** sysroot the program was linked against: after `--update`,
  their names can change.
* The binutils come from Ubuntu 26.04 (glibc 2.43): the SDK runs on that Ubuntu or newer. The scripts check that the
  unpacked tools start.
* Windows builds of yantra / yantra-radios are deferred and unrelated to this. This SDK is for OnAir.
