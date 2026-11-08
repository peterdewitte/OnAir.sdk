#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# example_build.sh - build OnAir with this SDK for every target: Windows x64, Linux x86-64, Raspberry Pi 5,
# macOS arm64 and macOS Intel. Follows README.md sections 2, 3, 3a and 3b. Each target is built in its own subshell
# that sources the target's environment-setup-* script, so the targets never see each other's settings.
#
# Usage:  ./example_build.sh [options] [target ...]
#   targets      windows linux rpi5 macos-arm64 macos-x86_64 (default: all of them); 'macos' = both macOS targets
#   --sdk DIR    the SDK (default: $SDK, else ./sdk next to this script)
#   --onair DIR  the OnAir source tree (default: ../OnAir next to this script)
#   --tests      also build the tests, tools and benchmarks (-DDECT2_BUILD_TESTS=ON; default OFF)
#   --type T     CMAKE_BUILD_TYPE (default: Release)
#   -j N         parallel jobs (default: nproc)
#   -k           keep going: build the next target when one fails, report at the end
#   --no-fresh   reuse an existing build folder's cache (default: cmake --fresh)
#
# Output, in the OnAir tree:  build-win/  build-linux/  build-rpi5/  build-mac-arm64/  build-mac-x86_64/
#   build-win:      dect2.exe ... with the DLLs it needs next to it (collect_dlls.sh; the radio DLLs OnAir loads by name too)
#   build-mac-*:    dect2 ... with the dylibs it needs in lib/ (collect_dylibs.sh, the radio dylibs too; rpath @executable_path/lib)
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SDK=${SDK:-$HERE/sdk}
ONAIR=$HERE/../OnAir
TESTS=OFF
BUILD_TYPE=Release
JOBS=$(nproc)
KEEP_GOING=0
FRESH=--fresh
ALL_TARGETS=(windows linux rpi5 macos-arm64 macos-x86_64)
TARGETS=()

usage() { sed -n '4,20p' "$0" | sed 's/^# \{0,1\}//'; }
while [ $# -gt 0 ]; do
  case "$1" in
    --sdk) SDK=$2; shift 2;;
    --onair) ONAIR=$2; shift 2;;
    --tests) TESTS=ON; shift;;
    --type) BUILD_TYPE=$2; shift 2;;
    -j) JOBS=$2; shift 2;;
    -j*) JOBS=${1#-j}; shift;;
    -k) KEEP_GOING=1; shift;;
    --no-fresh) FRESH=; shift;;
    -h|--help) usage; exit 0;;
    all) TARGETS+=("${ALL_TARGETS[@]}"); shift;;
    macos) TARGETS+=(macos-arm64 macos-x86_64); shift;;
    windows|linux|rpi5|macos-arm64|macos-x86_64) TARGETS+=("$1"); shift;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2;;
  esac
done
[ ${#TARGETS[@]} -gt 0 ] || TARGETS=("${ALL_TARGETS[@]}")

[ -d "$SDK" ] || { echo "no SDK at $SDK: run ./make_sdk.sh first, or give --sdk DIR" >&2; exit 1; }
[ -d "$ONAIR" ] || { echo "no OnAir tree at $ONAIR: give --onair DIR" >&2; exit 1; }
SDK=$(cd "$SDK" && pwd); ONAIR=$(cd "$ONAIR" && pwd)
[ -f "$ONAIR/CMakeLists.txt" ] || { echo "$ONAIR is not the OnAir source tree (no CMakeLists.txt)" >&2; exit 1; }
for t in cmake ninja pkg-config; do
  command -v "$t" >/dev/null || { echo "$t not found: sudo apt install cmake ninja-build pkgconf" >&2; exit 1; }
done

say() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

# configure + build one target; $1 = environment-setup suffix, $2 = build folder, rest = extra cmake arguments
configure_and_build() {
  local triple=$1 dir=$2; shift 2
  [ -f "$SDK/environment-setup-$triple" ] || { echo "the SDK has no $triple target: ./make_sdk.sh --target ..." >&2; return 1; }
  # shellcheck disable=SC1090
  . "$SDK/environment-setup-$triple"
  cd "$ONAIR"
  cmake $FRESH -S . -B "$dir" -G Ninja \
        -DCMAKE_BUILD_TYPE="$BUILD_TYPE" -DDECT2_BUILD_APP=ON -DDECT2_BUILD_TESTS="$TESTS" "$@"
  cmake --build "$dir" -j"$JOBS"
}

build_windows() {
  # no -DDECT2_COPY_RUNTIME_DLLS (searches the compiler's folder) and no -DDECT2_WIN_AVX2 / -march=native (README 2)
  configure_and_build x86_64-w64-mingw32 build-win
  # the DLLs every .exe needs, recursively, and the radio DLLs OnAir's native drivers load by name (FFmpeg, GLFW,
  # libusb, OpenSSL, libhackrf are linked in statically)
  local exe
  for exe in "$ONAIR"/build-win/*.exe; do
    [ -e "$exe" ] || continue
    "$SDK/collect_dlls.sh" "$exe" "" 'librtlsdr.dll' 'libairspy.dll' 'libairspyhf.dll' 'libbladeRF.dll' 'libiio.dll' \
        'libLimeSuite.dll' 'libhamlib-*.dll'
  done
}

build_linux() { configure_and_build x86_64-linux-gnu build-linux; }

build_rpi5()  { configure_and_build aarch64-linux-gnu build-rpi5; }   # -mcpu=cortex-a76; add -DRPI_CPU=generic for a Pi 4

build_macos() {   # $1 = arm64 | x86_64
  local arch=$1 dir=build-mac-$1 prog
  configure_and_build "$arch-apple-darwin" "$dir" \
      -DCMAKE_BUILD_RPATH=@executable_path/lib -DCMAKE_INSTALL_RPATH=@executable_path/../Frameworks
  # the dylibs (libc++, SoapySDR ...) every program needs, and the radio dylibs OnAir loads by name, into the folder its
  # build rpath names
  for prog in "$ONAIR/$dir"/*; do
    [ -f "$prog" ] && [ -x "$prog" ] || continue
    case $(head -c4 "$prog" | od -An -tx1 | tr -d ' \n') in cffaedfe|cefaedfe) ;; *) continue;; esac   # Mach-O
    "$SDK/collect_dylibs.sh" "$prog" "$ONAIR/$dir/lib" "$SDK/sysroots/$arch-apple-darwin" 'librtlsdr.0.dylib' 'libairspy.0.dylib' \
        'libairspyhf.0.dylib' 'libbladeRF.2.dylib' 'libiio.0.dylib' 'libLimeSuite.*.dylib' 'libhamlib.4.dylib'
  done
}

declare -A RESULT
failed=0
for target in "${TARGETS[@]}"; do
  say "OnAir for $target  (SDK $SDK, $BUILD_TYPE, tests $TESTS, -j$JOBS)"
  start=$SECONDS
  # a plain subshell (not inside && / ||, where bash ignores set -e), so the first failing step stops the target
  set +e
  (
    set -e
    case "$target" in
      windows)      build_windows ;;
      linux)        build_linux ;;
      rpi5)         build_rpi5 ;;
      macos-arm64)  build_macos arm64 ;;
      macos-x86_64) build_macos x86_64 ;;
    esac
  )
  rc=$?
  set -e
  if [ $rc -eq 0 ]; then
    RESULT[$target]="ok      $((SECONDS - start)) s"
  else
    RESULT[$target]="FAILED  $((SECONDS - start)) s"; failed=1
    [ $KEEP_GOING -eq 1 ] || break
  fi
done

say "Summary"
for target in "${TARGETS[@]}"; do printf '  %-14s %s\n' "$target" "${RESULT[$target]:-not built}"; done
exit $failed
