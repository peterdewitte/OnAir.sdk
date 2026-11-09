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
#   --build-onair       afterwards, check out OnAir and build its installers with these SDKs, into installers/ (a status table every 10 seconds)
#   --dry-run           print what would happen, build nothing
#   -h, --help          this text
#
# cache/ (the downloaded packages and sources, the built libraries) is never deleted. To limit the CPUs, run it under taskset: a Docker build
# takes over the same CPUs.
set -Eeuo pipefail
export LC_ALL=C
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
BUILD="$ROOT/build" IMAGE=onair-sdk-builder
ALL=(windows linux_amd64 linux_arm64 macos_amd64 macos_arm64)
DESC=("Windows x64" "Linux x86-64 (Ubuntu 26.04)" "Linux arm64 (Ubuntu 26.04, Raspberry Pi)" "macOS Intel" "macOS Apple silicon")
CHOSEN=() DOCKER=0 KEEP_SOURCES=0 KEEP_BUILD=0 DRY=0 IN_DOCKER=0 ASKED_DOCKER=0 BUILD_ONAIR=0
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
    -h|--help) usage; exit 0;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2;;
  esac
  shift
done

# Ubuntu 26.04 is what the SDK is made on, also in WSL: there the Docker question defaults to no, everywhere else to yes
on_ubuntu_2604() { [ "$(uname -s)" = Linux ] && [ -r /etc/os-release ] && ( . /etc/os-release; [ "${ID:-}" = ubuntu ] && [ "${VERSION_ID:-}" = 26.04 ] ); }

ask_yes() {   # <question> <default y|n>
  local a hint='[y/N]'; [ "$2" = y ] && hint='[Y/n]'
  read -r -p "$1 $hint " a || a=
  a=${a:-$2}; case "$a" in y|Y|yes|YES) return 0;; *) return 1;; esac
}

if [ ${#CHOSEN[@]} -eq 0 ]; then
  [ "$IN_DOCKER" = 0 ] || die "--in-docker needs the SDKs"
  [ -t 0 ] || [ "$DRY" = 1 ] || die "no terminal to ask on: name the SDKs (see --help)"
  echo "Which SDKs do you want to build?"
  for i in "${!ALL[@]}"; do printf '  %d) %-12s %s\n' $((i + 1)) "${ALL[$i]}" "${DESC[$i]}"; done
  echo "  a) all of them"
  while :; do
    read -r -p "Numbers separated by spaces, or a: " answer || die "no answer"
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
    if ask_yes "Build in the Docker \"safe build\"?" "$default"; then DOCKER=1; fi
  fi
  if [ "$KEEP_BUILD" = 0 ] && ask_yes "Keep the build artifacts of the SDK packages?" n; then KEEP_BUILD=1; fi
  if [ "$BUILD_ONAIR" = 0 ] && ask_yes "Do you want to build OnAir for these SDKs, after they are made?" n; then BUILD_ONAIR=1; fi
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

if [ "$DOCKER" = 0 ] && [ "$IN_DOCKER" = 0 ]; then
  [ "$(uname -s)" = Linux ] || die "on $(uname -s) the SDK is made in Docker: use --docker"
  [ "$DRY" = 1 ] || command -v apt-get >/dev/null || die "this Linux has no apt-get, which the SDK's scripts use: use --docker"
fi
if [ "$DOCKER" = 0 ] && [ "$DRY" = 0 ]; then check_host; fi

sha256() { if command -v sha256sum >/dev/null; then sha256sum "$@"; else shasum -a 256 "$@"; fi; }
finish() {   # the tarballs into this folder, with their checksums
  mkdir -p "$BUILD/out"
  local t; for t in "$BUILD"/out/sdk_*.tar.gz; do if [ -f "$t" ]; then mv -f "$t" "$ROOT/"; fi; done
  if ls "$ROOT"/sdk_*.tar.gz >/dev/null 2>&1; then (cd "$ROOT" && sha256 sdk_*.tar.gz > SHA256SUMS && cat SHA256SUMS); fi
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
  build=(docker build --platform linux/amd64 --build-arg "UID=$(id -u)" --build-arg "GID=$(id -g)" -t "$IMAGE" "$ROOT")
  # no root and no capabilities; this folder read-only, except what the build has to write. --platform: the SDK's tools run on Linux x86-64
  run=(docker run --rm --init --platform linux/amd64 --cap-drop=ALL --security-opt=no-new-privileges
       -v "$ROOT":/work:ro -v "$ROOT/cache":/work/cache -v "$BUILD":/work/build)
  [ "$KEEP_SOURCES" = 0 ] || run+=(-v "$ROOT/kept_sources":/work/kept_sources)
  [ "$BUILD_ONAIR" = 0 ] || run+=(-v "$ROOT/installers":/work/installers)
  # in the foreground, attached to this terminal: the status stays in view, and Ctrl-C stops the build
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

# ---- OnAir with these SDKs: each from its tarball, as a user would, with a status table ------------------------------------
ONAIR=$BUILD/onair
onair_name() { case "$1" in windows) echo "Windows";; linux_amd64) echo "Linux amd64";; linux_arm64) echo "Linux arm64";; macos_arm64) echo "macOS arm64";; macos_amd64) echo "macOS x86_64";; esac; }
onair_set() { local f=$ONAIR/status/$1; shift; printf '%s\n' "$@" > "$f.new"; mv "$f.new" "$f"; }   # result, installer, start, end
onair_cmd() { printf '  $ %s\n' "${2//$ROOT\//}" >> "$ONAIR/status/.commands"; }   # <arch> <command>: what ran, shown under the table
onair_show() { onair_table "$@"; if [ -s "$ONAIR/status/.commands" ]; then echo; echo "Commands:"; cat "$ONAIR/status/.commands"; fi; }
size_mb() { echo "$(( ($(stat -c %s "$1") + 524288) / 1048576 )) MB"; }

onair_one() {   # <arch>: never stops the others
  local arch=$1 d=$ONAIR/$1 start extra=() log=$ONAIR/$1.log rc=0
  start=$(date +%s)
  onair_set "$arch" Unpacking "" "$start" ""
  rm -rf "$d"; mkdir -p "$d"
  [ "$arch" != linux_arm64 ] || extra=(-DRPI_CPU=generic)   # any 64-bit ARM
  printf '%s:\n' "$(onair_name "$arch")" >> "$ONAIR/status/.commands"
  onair_cmd "$arch" "tar xzf $BUILD/out/sdk_$arch.tar.gz -C $d"
  tar xzf "$BUILD/out/sdk_$arch.tar.gz" -C "$d" > "$log" 2>&1 || rc=$?
  if [ "$rc" = 0 ]; then
    onair_set "$arch" Configuring "" "$start" ""
    (
      # the steps of the README, in a shell of their own
      onair_cmd "$arch" ". $d/environment_$arch.sh"
      . "$d/environment_$arch.sh" >> "$log" 2>&1 || exit 1
      export CCACHE_DISABLE=1
      onair_cmd "$arch" "cmake -S $ONAIR/src -B $d/build -G Ninja -DCMAKE_BUILD_TYPE=Release${extra[*]:+ ${extra[*]}}"
      cmake -S "$ONAIR/src" -B "$d/build" -G Ninja -DCMAKE_BUILD_TYPE=Release "${extra[@]}" >> "$log" 2>&1 || exit 1
      onair_set "$arch" Compiling "" "$start" ""
      onair_cmd "$arch" "cmake --build $d/build --target package   # builds the programs, then packages them"
      cmake --build "$d/build" --target package >> "$log" 2>&1
    ) || rc=$?
  fi
  local inst="" f
  if [ "$rc" = 0 ]; then
    mkdir -p "$ROOT/installers"
    for f in "$d/build/packages"/*.exe "$d/build/packages"/*.zip "$d/build/packages"/*.deb "$d/build/packages"/*.dmg; do
      [ -f "$f" ] || continue
      cp "$f" "$ROOT/installers/"
      case "$f" in
        *-setup.exe) inst+="${inst:+, }setup.exe $(size_mb "$f")";;
        *.zip)       inst+="${inst:+, }zip $(size_mb "$f")";;
        *.deb)       inst+="${inst:+, }deb $(size_mb "$f")";;
        *.dmg)       inst+="${inst:+, }dmg $(size_mb "$f")";;
      esac
    done
    [ -n "$inst" ] || rc=1
  fi
  if [ "$rc" = 0 ]; then
    onair_cmd "$arch" "cp $d/build/packages/* $ROOT/installers/"
    onair_set "$arch" Passed "$inst" "$start" "$(date +%s)"
  else
    mkdir -p "$ROOT/installers"; cp "$log" "$ROOT/installers/$arch-failed.log" 2>/dev/null || true
    onair_set "$arch" Failed "see installers/$arch-failed.log" "$start" "$(date +%s)"
    echo 1 >> "$ONAIR/status/.failed"
  fi
  if [ "$KEEP_BUILD" = 0 ]; then rm -rf "$d"; fi   # as soon as the installers are out
}

onair_table() {   # <arch...>
  local a result inst start end t step w1=14 w2=21 w3=45 w4=8 line
  rule() { local l=$1 m=$2 r=$3 c; printf '%s' "$l"; for c in $w1 $w2 $w3 $w4; do printf '─%.0s' $(seq 1 $((c + 2))); [ "$c" = "$w4" ] && printf '%s\n' "$r" || printf '%s' "$m"; done; }
  rule ┌ ┬ ┐
  printf '│ %-*s │ %-*s │ %-*s │ %-*s │\n' $w1 Platform $w2 Result $w3 Installer $w4 Time
  for a in "$@"; do
    rule ├ ┼ ┤
    { read -r result; read -r inst; read -r start; read -r end; } < "$ONAIR/status/$a"
    t=""
    if [ -n "$start" ]; then
      t=$(( ${end:-$(date +%s)} - start ))
      if [ "$t" -ge 60 ]; then t="$((t / 60)) min"; else t="$t s"; fi
    fi
    if [ "$result" = Compiling ]; then
      step=$(tail -c 4096 "$ONAIR/$a.log" 2>/dev/null | grep -oE '^\[[0-9]+/[0-9]+\]' | tail -1 | tr -d '[]' || true)
      if [ -n "$step" ]; then
        if [ "${step%/*}" = "${step#*/}" ]; then result=Packaging; else result="Compiling $step"; fi
      fi
    fi
    printf '│ %-*s │ %-*s │ %-*s │ %-*s │\n' $w1 "$(onair_name "$a")" $w2 "$result" $w3 "$inst" $w4 "$t"
  done
  rule └ ┴ ┘
}

build_onair() {
  local order=() a worker rc=0 n=0
  for a in windows linux_amd64 linux_arm64 macos_arm64 macos_amd64; do
    for c in "${ORDERED[@]}"; do [ "$c" != "$a" ] || order+=("$a"); done
  done
  printf '\n==== %s: OnAir (%s) with these SDKs\n' "$(date +%H:%M:%S)" "$ONAIR_BRANCH"
  rm -rf "$ONAIR"; mkdir -p "$ONAIR/status"
  printf 'OnAir:\n' >> "$ONAIR/status/.commands"
  onair_cmd "" "git clone --depth 1 --branch $ONAIR_BRANCH $ONAIR_URL $ONAIR/src"
  git clone -q --depth 1 --single-branch --branch "$ONAIR_BRANCH" "$ONAIR_URL" "$ONAIR/src" || die "cannot check out $ONAIR_BRANCH of $ONAIR_URL"
  grep -q ONAIR_SDK_PLATFORM "$ONAIR/src/CMakeLists.txt" || die "$ONAIR_BRANCH of $ONAIR_URL has no package target for this SDK yet"
  for a in "${order[@]}"; do onair_set "$a" Queued "" "" ""; done
  ( for a in "${order[@]}"; do onair_one "$a"; done ) &
  worker=$!
  local i
  while kill -0 "$worker" 2>/dev/null; do
    # on a terminal the table stays at the top of the screen; otherwise, in a log, one table after the other
    [ ! -t 1 ] || printf '\033[H\033[2J'
    onair_show "${order[@]}"
    for i in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$worker" 2>/dev/null || break; sleep 1; done
  done
  wait "$worker" || rc=$?
  [ ! -t 1 ] || printf '\033[H\033[2J'
  onair_show "${order[@]}"
  (cd "$ROOT/installers" && for f in *.exe *.zip *.deb *.dmg; do [ -f "$f" ] && echo "$f"; done | xargs -r sha256sum > SHA256SUMS) || true
  if [ -s "$ONAIR/status/.failed" ]; then die "OnAir failed on some platforms: see the logs in installers/"; fi
  [ "$rc" = 0 ] || die "the OnAir build stopped"
  echo "Installers: $ROOT/installers"
}

mkdir -p "$BUILD" "$ROOT/cache"
for a in "${ORDERED[@]}"; do make_one "$a"; done
[ "$DRY" = 1 ] && exit 0
if [ "$KEEP_SOURCES" = 1 ]; then keep_sources; fi
if [ "$BUILD_ONAIR" = 1 ]; then build_onair; fi
