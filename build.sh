#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# build.sh - everything from nothing: OnAir's source, the SDK, then each platform built and packaged, one after the other.
# The result: ./packages (OnAir installers and SHA256SUMS). Each platform is written out below: it sources that SDK's
# environment, configures and builds OnAir, then packages it. Each runs in its own subshell, so targets never see each other's settings.
#
#   ./build.sh                    every step, in this order
#   ./build.sh <step> ...         only those steps: checkout sdk windows linux-amd64 linux-arm64 macos-arm64 macos-x86_64 collect
#   ./build.sh clean              remove OnAir/, sdk/ and packages/; cache/ stays, so downloads and built libraries are reused
#
#   JOBS   parallel jobs (default: all threads but two)
#
# The tests are configured but not built here: only the programs that are shipped. To build and run them, see README.md.
set -Eeuo pipefail
export LC_ALL=C.UTF-8
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SDK="$ROOT/sdk" ONAIR="$ROOT/OnAir" PACKAGES="$ROOT/packages"
JOBS=${JOBS:-$(( $(nproc) > 2 ? $(nproc) - 2 : 1 ))}
PROGRAMS=(dect2 dect2cli dect2scan onair-server)
# what OnAir's tools/package/sdk scripts read
export SDK JOBS OUT="$ONAIR/packages"
trap 'echo "error: build.sh line $LINENO: $BASH_COMMAND" >&2' ERR

say() { printf '\n==== %s: %s\n' "$(date +%H:%M:%S)" "$*"; }
onair_options() {   # the options every platform shares (the same ones the package scripts use, so they find the build done)
  local v; v=$(grep -m1 'project(' "$ONAIR/CMakeLists.txt" | sed -E 's/.*VERSION ([0-9.]+).*/\1/')
  export VERSION=$v
  OPTIONS=(-G Ninja -DCMAKE_BUILD_TYPE=Release -DDECT2_BUILD_APP=ON -DDECT2_BUILD_TESTS=ON -DDECT2_CCACHE=OFF
           -DDECT2_HAVE_HAMLIB=ON -DDECT2_WITH_TLS=ON -DOPENSSL_USE_STATIC_LIBS=TRUE "-DONAIR_VERSION=$v" -DCMAKE_SKIP_INSTALL_ALL_DEPENDENCY=ON)
}

# ---- 1. OnAir's source: ./OnAir -------------------------------------------------------------------------------------------
step_checkout() {
  say "OnAir's source"
  "$ROOT/checkout_onair.sh"
}

# ---- 2. the SDK: ./sdk (clang, a sysroot per target, the libraries, the packaging tools); kept downloads and builds: ./cache --
step_sdk() {
  say "the SDK"
  "$ROOT/make_sdk.sh" -o "$SDK"
}

# ---- 3. Windows x64: OnAir-<v>-windows-x64-setup.exe and .zip ---------------------------------------------------------------
step_windows() (
  say "Windows x64"
  . "$SDK/environment-setup-x86_64-w64-mingw32"
  onair_options; cd "$ONAIR"
  cmake -S . -B build-pkg-win "${OPTIONS[@]}"
  cmake --build build-pkg-win -j"$JOBS" --target "${PROGRAMS[@]}"
  tools/package/sdk/windows.sh
)

# ---- 4. Linux x86-64: onair_<v>_amd64.deb ------------------------------------------------------------------------------------
step_linux_amd64() (
  say "Linux x86-64"
  . "$SDK/environment-setup-x86_64-linux-gnu"
  onair_options; cd "$ONAIR"
  cmake -S . -B build-pkg-amd64 "${OPTIONS[@]}" -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_INSTALL_LIBDIR=lib "-DDECT2_RADIO_LIB_DIR=$ONAIR/build-pkg-amd64-radiolibs"
  cmake --build build-pkg-amd64 -j"$JOBS" --target "${PROGRAMS[@]}"
  tools/package/sdk/deb.sh amd64
)

# ---- 5. Linux arm64 (any 64-bit ARM: Raspberry Pi 4, 5 ...): onair_<v>_arm64.deb --------------------------------------------
step_linux_arm64() (
  say "Linux arm64"
  . "$SDK/environment-setup-aarch64-linux-gnu"
  onair_options; cd "$ONAIR"
  cmake -S . -B build-pkg-arm64 "${OPTIONS[@]}" -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_INSTALL_LIBDIR=lib "-DDECT2_RADIO_LIB_DIR=$ONAIR/build-pkg-arm64-radiolibs" -DRPI_CPU=generic
  cmake --build build-pkg-arm64 -j"$JOBS" --target "${PROGRAMS[@]}"
  tools/package/sdk/deb.sh arm64
)

# ---- 6. macOS Apple silicon: OnAir-<v>-macos-arm64.dmg ----------------------------------------------------------------------
step_macos_arm64() (
  say "macOS arm64"
  . "$SDK/environment-setup-arm64-apple-darwin"
  onair_options; cd "$ONAIR"
  cmake -S . -B build-pkg-mac-arm64 "${OPTIONS[@]}" -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON -DCMAKE_INSTALL_RPATH=@executable_path/../Frameworks
  cmake --build build-pkg-mac-arm64 -j"$JOBS" --target "${PROGRAMS[@]}"
  tools/package/sdk/dmg.sh arm64
)

# ---- 7. macOS Intel: OnAir-<v>-macos-x86_64.dmg ------------------------------------------------------------------------------
step_macos_x86_64() (
  say "macOS x86_64"
  . "$SDK/environment-setup-x86_64-apple-darwin"
  onair_options; cd "$ONAIR"
  cmake -S . -B build-pkg-mac-x86_64 "${OPTIONS[@]}" -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON -DCMAKE_INSTALL_RPATH=@executable_path/../Frameworks
  cmake --build build-pkg-mac-x86_64 -j"$JOBS" --target "${PROGRAMS[@]}"
  tools/package/sdk/dmg.sh x86_64
)

# ---- 8. every package into ./packages, with their checksums ----------------------------------------------------------------
step_collect() {
  say "packages"
  rm -rf "$PACKAGES"; mkdir -p "$PACKAGES"
  local expected=(windows-x64-setup.exe windows-x64.zip amd64.deb arm64.deb macos-arm64.dmg macos-x86_64.dmg) e
  for e in "${expected[@]}"; do
    compgen -G "$OUT/*$e" >/dev/null || { echo "error: no *$e in $OUT" >&2; exit 1; }
    cp "$OUT"/*"$e" "$PACKAGES/"
  done
  (cd "$PACKAGES" && sha256sum -- * > SHA256SUMS && cat SHA256SUMS)
  ls -la "$PACKAGES"
}

step_clean() {
  say "removing OnAir/, sdk/ and packages/ (cache/ stays)"
  rm -rf "$ONAIR" "$SDK" "$PACKAGES" "$ROOT/cache/work"
  mkdir -p "$ROOT/cache/work"
}

ALL=(checkout sdk windows linux-amd64 linux-arm64 macos-arm64 macos-x86_64 collect)
[ $# -gt 0 ] || set -- "${ALL[@]}"
for s in "$@"; do
  case "$s" in checkout|sdk|windows|linux-amd64|linux-arm64|macos-arm64|macos-x86_64|collect|clean) ;; *) sed -n '4,14p' "$0" | sed 's/^# \{0,1\}//'; echo "unknown step: $s" >&2; exit 2;; esac
done
START=$SECONDS
for s in "$@"; do
  t=$SECONDS
  "step_${s//-/_}"
  echo "---- $s: $((SECONDS - t)) s"
done
say "done in $((SECONDS - START)) s"
