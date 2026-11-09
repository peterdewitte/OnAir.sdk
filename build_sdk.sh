#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# build_sdk.sh - make the cross SDKs. Each platform is made on its own, with its own compiler, into sdk_<arch>.tar.gz in this folder:
# sysroot_<arch>/ and environment_<arch>.sh. Without arguments it asks what to build.
#
#   --windows --linux_amd64 --linux_arm64 --macos_amd64 --macos_arm64    the SDKs to make
#   --docker            build in the "safe" container: no root, no capabilities, this folder read-only except cache/ and build/
#   --keep-sources      keep unpacked copies of the libraries' sources in kept_sources/ (default: no)
#   --keep-build-artif  keep the build folders in build/ and cache/work/ (default: each is deleted as soon as it is done with)
#   --build-onair       afterwards, check out OnAir and build its installers with these SDKs, into installers/
#   --dry-run           print what would happen, build nothing
#   -h, --help          this text
#
# An SDK whose tarball is already here, with the right checksum, need not be made again: on a terminal it asks. cache/ (the downloaded packages and sources, the built libraries) is never deleted. To limit the CPUs, run it under taskset: a Docker build
# takes over the same CPUs.
set -Eeuo pipefail
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
BUILD="$ROOT/build" IMAGE=onair-sdk-builder
ALL=(windows linux_amd64 linux_arm64 macos_amd64 macos_arm64)
DESC=("Windows x64" "Linux x86-64 (Ubuntu 26.04)" "Linux arm64 (Ubuntu 26.04, Raspberry Pi)" "macOS Intel" "macOS Apple silicon")
CHOSEN=() DOCKER=0 KEEP_SOURCES=0 KEEP_BUILD=0 DRY=0 IN_DOCKER=0 ASKED_DOCKER=0 BUILD_ONAIR=0 SKIP_SDK=()
ONAIR_URL=${ONAIR_URL:-https://github.com/peterdewitte/OnAir.git} ONAIR_BRANCH=${ONAIR_BRANCH:-clang_and_packaging}   # (temporary: the patches for this SDK)

usage() { sed -n '4,16p' "$0" | sed 's/^# \{0,1\}//'; }
die() { echo "error: $*" >&2; exit 1; }
while [ $# -gt 0 ]; do
  case "$1" in
    --windows|--linux_amd64|--linux_arm64|--macos_amd64|--macos_arm64) CHOSEN+=("${1#--}");;
    --docker) DOCKER=1; ASKED_DOCKER=1;;
    --keep-sources) KEEP_SOURCES=1;;
    --keep-build-artif) KEEP_BUILD=1;;
    --build-onair) BUILD_ONAIR=1;;
    --dry-run) DRY=1;;
    --in-docker) IN_DOCKER=1;;   # (the container's own run)
    --skip-sdk) SKIP_SDK+=("$2"); shift;;   # (from the outer run to the container)
    -h|--help) usage; exit 0;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2;;
  esac
  shift
done

# Ubuntu 26.04 is what the SDK is made on, also in WSL: there the Docker question defaults to no, everywhere else to yes
on_ubuntu_2604() { [ "$(uname -s)" = Linux ] && [ -r /etc/os-release ] && ( . /etc/os-release; [ "${ID:-}" = ubuntu ] && [ "${VERSION_ID:-}" = 26.04 ] ); }

ask_yes() {   # <question> <default y|n> <explanation, shown for ?>
  local a hint='[y/N/?]'; [ "$2" = y ] && hint='[Y/n/?]'
  while :; do
    read -r -p "$1 $hint " a || a=
    a=${a:-$2}
    case "$a" in
      y|Y|yes|YES) return 0;;
      n|N|no|NO) return 1;;
      '?') printf '%s\n' "$3" | sed 's/^/  /';;
      *) echo "  Please answer y or n, or ? for an explanation.";;
    esac
  done
}

if [ ${#CHOSEN[@]} -eq 0 ]; then
  [ "$IN_DOCKER" = 0 ] || die "--in-docker needs the SDKs"
  [ -t 0 ] || [ "$DRY" = 1 ] || die "no terminal to ask on: name the SDKs (see --help)"
  echo "Which SDKs do you want to build?"
  for i in "${!ALL[@]}"; do printf '  %d) %-12s %s\n' $((i + 1)) "${ALL[$i]}" "${DESC[$i]}"; done
  echo "  a) all of them"
  while :; do
    read -r -p "Numbers separated by spaces, a for all, ? for an explanation: " answer || die "no answer"
    if [ "$answer" = '?' ]; then
      cat <<'HELP' | sed 's/^/  /'
An SDK holds a compiler and libraries to build OnAir for one target platform. All of them run on Linux x86-64.
Each one takes about 5 minutes the first time plus its downloads, and about 1 minute once cache/ is filled.
Each tarball is about 800 MB. For example, 1 3 makes the Windows and the Linux arm64 SDK.
HELP
      continue
    fi
    CHOSEN=(); ok=1
    for w in ${answer//,/ }; do
      case "$w" in
        a|A|all) CHOSEN=("${ALL[@]}");;
        [1-5]) CHOSEN+=("${ALL[$((w - 1))]}");;
        *) echo "  not a choice: $w"; ok=0;;
      esac
    done
    [ "$ok" = 1 ] && [ ${#CHOSEN[@]} -gt 0 ] && break
  done
  if [ "$ASKED_DOCKER" = 0 ]; then
    default=y; if on_ubuntu_2604; then default=n; fi
    if ask_yes "Build in the Docker \"safe build\"?" "$default" "Builds in a container: Ubuntu 26.04, no root, and this folder read-only except what the build writes.
You need only Docker, on any system, and nothing is installed on this machine.
No: builds directly here, which needs Ubuntu 26.04 and its packages (the script checks them first)."; then DOCKER=1; fi
  fi
  if [ "$KEEP_BUILD" = 0 ] && ask_yes "Keep the build artifacts of the SDK packages?" n "Yes keeps the unpacked SDKs in build/, and the build folders of libraries compiled in this run in cache/work/. Useful for finding out why a build failed.
They take several GB per SDK. No deletes each one as soon as it is done with.
The downloads and built libraries in cache/ and the tarballs always stay."; then KEEP_BUILD=1; fi
  if [ "$BUILD_ONAIR" = 0 ] && ask_yes "Do you want to build OnAir for these SDKs, after they are made?" n "Yes checks out OnAir's $ONAIR_BRANCH branch and builds its installers with each SDK, into installers/.
It takes about 15 to 20 minutes per platform on 8 CPUs, and it logs the commands and progress.
No makes only the SDKs. You can build OnAir with them later: see README.md."; then BUILD_ONAIR=1; fi
fi
# each once, in the usual order
ORDERED=()
for a in "${ALL[@]}"; do for c in "${CHOSEN[@]}"; do [ "$c" != "$a" ] || { ORDERED+=("$a"); break; }; done; done

# ---- the host tools: all at once, and what to install for them ------------------------------------------------------------
check_host() {
  local missing=() c
  need() { command -v "$1" >/dev/null || missing+=("$2"); }
  need_file() { [ -e "$1" ] || missing+=("$2"); }
  need cmake cmake; need ninja ninja-build; need pkg-config pkgconf
  need curl curl; need_file /etc/ssl/certs/ca-certificates.crt ca-certificates
  need zstd zstd; need xz xz-utils; need bzip2 bzip2; need unzip unzip; need pigz pigz
  need gpg gpg; need gpg-agent gpg-agent; need gpgv gpgv
  need python3 python3; need make make; need perl perl; need nasm nasm; need patch patch
  need wayland-scanner libwayland-bin
  [ "$BUILD_ONAIR" = 0 ] || need git git
  need gcc gcc; need g++ g++; need_file /usr/include/stdio.h libc6-dev; need_file /usr/include/zlib.h zlib1g-dev; need_file /usr/include/lzma.h liblzma-dev
  if [ ${#missing[@]} -gt 0 ]; then
    echo "error: this machine lacks host tools to make the SDK. Install them with:" >&2
    echo "  sudo apt install ${missing[*]}" >&2
    echo "Or build in the container, where you need only Docker: ./build_sdk.sh --docker" >&2
    exit 1
  fi
  echo "host tools: ok"
}

# ---- SDKs that are already made: ask, on a terminal ------------------------------------------------------------------------
tarball_ok() { [ -f "$ROOT/sdk_$1.tar.gz" ] && [ -f "$ROOT/SHA256SUMS" ] && (cd "$ROOT" && grep -E "[ *]sdk_$1\.tar\.gz\$" SHA256SUMS | { command -v sha256sum >/dev/null && sha256sum -c --status - || shasum -a 256 -c --status -; }); }
is_skipped() { local s; for s in ${SKIP_SDK[@]+"${SKIP_SDK[@]}"}; do [ "$s" != "$1" ] || return 0; done; return 1; }
if [ "$IN_DOCKER" = 0 ] && [ -t 0 ]; then
  for a in "${ORDERED[@]}"; do
    if tarball_ok "$a"; then
      if ask_yes "sdk_$a.tar.gz is already made. Skip building it?" y "Its checksum is correct, so it is complete. Yes keeps it, and building OnAir uses it.
No makes it again, for example after you changed the SDK's scripts or lock files: this script cannot see if the tarball is out of date."; then SKIP_SDK+=("$a"); fi
    elif [ -f "$ROOT/sdk_$a.tar.gz" ]; then
      echo "sdk_$a.tar.gz does not match SHA256SUMS: making it again"
    fi
  done
fi

if [ "$DOCKER" = 0 ] && [ "$IN_DOCKER" = 0 ]; then
  [ "$(uname -s)" = Linux ] || die "on $(uname -s) the SDK is made in Docker: use --docker"
  [ "$DRY" = 1 ] || command -v apt-get >/dev/null || die "this Linux has no apt-get, which the SDK's scripts use: use --docker"
fi
if [ "$DOCKER" = 0 ] && [ "$DRY" = 0 ]; then check_host; fi

sha256() { if command -v sha256sum >/dev/null; then sha256sum "$@"; else shasum -a 256 "$@"; fi; }
finish() {   # the tarballs into this folder, with their checksums
  mkdir -p "$BUILD/out"
  local t; for t in "$BUILD"/out/sdk_*.tar.gz; do if [ -f "$t" ]; then mv -f "$t" "$ROOT/"; fi; done
  if ls "$ROOT"/sdk_*.tar.gz >/dev/null 2>&1; then (cd "$ROOT" && sha256 sdk_*.tar.gz > SHA256SUMS.new && mv SHA256SUMS.new SHA256SUMS && cat SHA256SUMS); fi
  if [ "$KEEP_BUILD" = 0 ]; then rm -rf "$BUILD"; fi
}

# also when something fails: what is finished stays, and the half-made SDK goes
on_exit() {
  local rc=$?
  trap - EXIT
  [ "$DRY" = 1 ] && exit "$rc"
  if [ "$KEEP_BUILD" = 0 ]; then rm -rf "$BUILD"/sdk_* "$BUILD/onair"; fi
  if [ "$IN_DOCKER" = 0 ]; then finish; fi
  exit "$rc"
}
trap on_exit EXIT

# ---- the safe build: the same script in a container ----------------------------------------------------------------------
if [ "$DOCKER" = 1 ] && [ "$IN_DOCKER" = 0 ]; then
  args=(--in-docker); for a in "${ORDERED[@]}"; do args+=("--$a"); done
  [ "$KEEP_SOURCES" = 0 ] || args+=(--keep-sources)
  [ "$KEEP_BUILD" = 0 ] || args+=(--keep-build-artif)
  [ "$BUILD_ONAIR" = 0 ] || args+=(--build-onair)
  for a in ${SKIP_SDK[@]+"${SKIP_SDK[@]}"}; do args+=(--skip-sdk "$a"); done
  build=(docker build --platform linux/amd64 --build-arg "UID=$(id -u)" --build-arg "GID=$(id -g)" -t "$IMAGE" "$ROOT")
  # no root and no capabilities; this folder read-only, except what the build has to write. --platform: the SDK's tools run on Linux x86-64
  run=(docker run --rm --init --platform linux/amd64 --cap-drop=ALL --security-opt=no-new-privileges
       -v "$ROOT":/work:ro -v "$ROOT/cache":/work/cache -v "$BUILD":/work/build)
  [ "$KEEP_SOURCES" = 0 ] || run+=(-v "$ROOT/kept_sources":/work/kept_sources)
  [ "$BUILD_ONAIR" = 0 ] || run+=(-v "$ROOT/installers":/work/installers)
  # in the foreground, attached to this terminal: the log stays in view, and Ctrl-C stops the build
  [ ! -t 1 ] || run+=(-t); [ ! -t 0 ] || run+=(-i)
  cpus=$(sed -n 's/^Cpus_allowed_list:[[:space:]]*//p' /proc/self/status 2>/dev/null || true)
  [ -z "$cpus" ] || run+=("--cpuset-cpus=$cpus")   # (taskset's CPUs)
  run+=("$IMAGE" bash /work/build_sdk.sh "${args[@]}")
  echo "SDKs: ${ORDERED[*]} (in Docker)"
  if [ "$DRY" = 1 ]; then printf '%q ' "${build[@]}"; echo; printf '%q ' "${run[@]}"; echo; exit 0; fi
  command -v docker >/dev/null || die "docker is not installed"
  docker info >/dev/null 2>&1 || die "cannot reach Docker. Is it running, and are you in the docker group? (sudo usermod -aG docker \$USER, then log in again)"
  mkdir -p "$ROOT/cache" "$BUILD"; [ "$KEEP_SOURCES" = 0 ] || mkdir -p "$ROOT/kept_sources"; [ "$BUILD_ONAIR" = 0 ] || mkdir -p "$ROOT/installers"
  "${build[@]}"
  "${run[@]}"
  exit 0
fi

# ---- one SDK ------------------------------------------------------------------------------------------------------------

make_one() {
  local arch=$1 target triple dir tarball start=$SECONDS
  case "$arch" in
    windows)     target=windows      triple=x86_64-w64-mingw32;;
    linux_amd64) target=linux        triple=x86_64-linux-gnu;;
    linux_arm64) target=rpi5         triple=aarch64-linux-gnu;;
    macos_amd64) target=macos-x86_64 triple=x86_64-apple-darwin;;
    macos_arm64) target=macos-arm64  triple=arm64-apple-darwin;;
  esac
  dir=$BUILD/sdk_$arch/sysroot_$arch
  tarball=$BUILD/out/sdk_$arch.tar.gz
  printf '\n==== %s: SDK %s\n' "$(date +%H:%M:%S)" "$arch"
  if [ "$DRY" = 1 ]; then echo "common/make_sdk.sh -o $dir --target $target; tar -> sdk_$arch.tar.gz"; return; fi
  rm -rf "$BUILD/sdk_$arch"; mkdir -p "$BUILD/sdk_$arch" "$BUILD/out"
  local keep=(); [ "$KEEP_BUILD" = 0 ] || keep=(--keep-work)
  "$ROOT/common/make_sdk.sh" -o "$dir" --target "$target" "${keep[@]}"
  rm -f "$dir/.made-by-make_sdk"
  cat > "$BUILD/sdk_$arch/environment_$arch.sh" <<ENV
# Source this file, in bash or zsh, to build for $arch in this shell:  . ./environment_$arch.sh
if [ -n "\${BASH_SOURCE:-}" ]; then _sdk_self=\${BASH_SOURCE[0]}; elif [ -n "\${ZSH_VERSION:-}" ]; then _sdk_self=\${(%):-%x}; else _sdk_self=\$0; fi
. "\$(cd "\$(dirname "\$_sdk_self")" && pwd)/sysroot_$arch/environment-setup-$triple"
unset _sdk_self
ENV
  chmod 644 "$BUILD/sdk_$arch/environment_$arch.sh"
  local gz=gzip; command -v pigz >/dev/null && gz=pigz
  tar -C "$BUILD/sdk_$arch" -I "$gz" -cf "$tarball.part" "sysroot_$arch" "environment_$arch.sh"
  mv "$tarball.part" "$tarball"
  if [ "$KEEP_BUILD" = 0 ]; then rm -rf "$BUILD/sdk_$arch"; fi   # as soon as it is in the tarball
  echo "---- $arch: sdk_$arch.tar.gz, $(du -h "$tarball" | cut -f1), $((SECONDS - start)) s"
}

keep_sources() {   # unpacked as downloaded: the patches and what the build changes are in sources/ and sources/build_sources.sh
  local kind name ver file rest d
  while read -r kind name ver file rest; do
    [ "$kind" = src ] || continue
    d=$ROOT/kept_sources/$name; rm -rf "$d"; mkdir -p "$d"
    case "$file" in
      *.zip) unzip -q "$ROOT/cache/src/$file" -d "$d";;
      *) tar -xf "$ROOT/cache/src/$file" -C "$d" --strip-components=1;;
    esac
  done < "$ROOT/sources/sources.lock"
  cp -R "$ROOT/sources/patches" "$ROOT/kept_sources/"
  echo "sources kept in kept_sources/"
}

# ---- OnAir with these SDKs: each from its tarball, as a user would. Logged like the SDK: the compilers' output goes to a log, an error stops everything ------
ONAIR=$BUILD/onair
size_mb() { echo "$(( ($(stat -c %s "$1") + 524288) / 1048576 )) MB"; }
show() { printf '  $ %s\n' "${1//$ROOT\//}"; }
onair_failed() {   # <arch> <log>
  mkdir -p "$ROOT/installers"; cp "$2" "$ROOT/installers/$1-failed.log" 2>/dev/null || true
  echo "---- the end of the log (all of it: installers/$1-failed.log):" >&2; tail -40 "$2" >&2
  die "OnAir failed for $1"
}
progress() { awk '/^\[[0-9]+\/[0-9]+\]/ { split(substr($1, 2, length($1) - 2), n, "/"); if (n[2] < 10) next; p = int(n[1] * 10 / n[2]) * 10; if (p > last) { last = p; printf "    %d%% (%d of %d)\n", p, n[1], n[2]; fflush() } }'; }

onair_one() {   # <arch>
  local arch=$1 d=$ONAIR/$1 log=$ONAIR/$1.log start=$SECONDS extra=() sdk=$BUILD/out/sdk_$1.tar.gz
  [ -f "$sdk" ] || sdk=$ROOT/sdk_$arch.tar.gz
  [ -f "$sdk" ] || die "no sdk_$arch.tar.gz"
  [ "$arch" != linux_arm64 ] || extra=(-DRPI_CPU=generic)   # any 64-bit ARM
  printf '\n==== %s: OnAir for %s\n' "$(date +%H:%M:%S)" "$arch"
  rm -rf "$d"; mkdir -p "$d"; : > "$log"; rm -f "$ROOT/installers/$arch-failed.log"
  show "tar xzf $sdk -C $d"
  tar xzf "$sdk" -C "$d" >> "$log" 2>&1 || onair_failed "$arch" "$log"
  (
    # the steps of the README, in a shell of their own
    show ". $d/environment_$arch.sh"
    . "$d/environment_$arch.sh" >> "$log" 2>&1
    export CCACHE_DISABLE=1
    show "cmake -S $ONAIR/src -B $d/build -G Ninja -DCMAKE_BUILD_TYPE=Release${extra[*]:+ ${extra[*]}}"
    cmake -S "$ONAIR/src" -B "$d/build" -G Ninja -DCMAKE_BUILD_TYPE=Release "${extra[@]}" >> "$log" 2>&1
    show "cmake --build $d/build --target package"
    cmake --build "$d/build" --target package 2>&1 | tee -a "$log" | progress
  ) || onair_failed "$arch" "$log"
  local inst="" f
  mkdir -p "$ROOT/installers"
  for f in "$d/build/packages"/*.exe "$d/build/packages"/*.zip "$d/build/packages"/*.deb "$d/build/packages"/*.dmg; do
    [ -f "$f" ] || continue
    show "cp $f $ROOT/installers/"
    cp "$f" "$ROOT/installers/"
    inst+="${inst:+, }$(basename "$f") $(size_mb "$f")"
  done
  [ -n "$inst" ] || onair_failed "$arch" "$log"
  if [ "$KEEP_BUILD" = 0 ]; then rm -rf "$d"; fi   # as soon as the installers are out
  echo "---- $arch: $inst, $(( (SECONDS - start) / 60 )) min"
}

build_onair() {
  local a f
  printf '\n==== %s: OnAir (%s)\n' "$(date +%H:%M:%S)" "$ONAIR_BRANCH"
  rm -rf "$ONAIR"; mkdir -p "$ONAIR"
  show "git clone --depth 1 --branch $ONAIR_BRANCH $ONAIR_URL $ONAIR/src"
  git clone -q --depth 1 --single-branch --branch "$ONAIR_BRANCH" "$ONAIR_URL" "$ONAIR/src" || die "cannot check out $ONAIR_BRANCH of $ONAIR_URL"
  grep -q ONAIR_SDK_PLATFORM "$ONAIR/src/CMakeLists.txt" || die "$ONAIR_BRANCH of $ONAIR_URL has no package target for this SDK yet"
  for a in "${ORDERED[@]}"; do onair_one "$a"; done
  (cd "$ROOT/installers" && for f in *.exe *.zip *.deb *.dmg; do if [ -f "$f" ]; then sha256 "$f"; fi; done > SHA256SUMS.new && mv SHA256SUMS.new SHA256SUMS)
  printf '\nInstallers: %s\n' "$ROOT/installers"
}

[ "$DRY" = 1 ] || mkdir -p "$BUILD" "$ROOT/cache"
for a in "${ORDERED[@]}"; do
  if is_skipped "$a"; then printf '
==== SDK %s: already made, skipped
' "$a"; else make_one "$a"; fi
done
[ "$DRY" = 1 ] && exit 0
if [ "$KEEP_SOURCES" = 1 ]; then keep_sources; fi
if [ "$BUILD_ONAIR" = 1 ]; then build_onair; fi
