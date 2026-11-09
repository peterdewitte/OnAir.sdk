#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# build_pkgtools.sh - add the tools that make the packages to the SDK's native sysroot, from common/pkgtools.lock:
#
#   makensis                    the Windows installer (Ubuntu's nsis, nsis-common: unpacked, not installed)
#   mkfs.hfsplus, fsck.hfsplus  the macOS disk image's volume (Ubuntu's hfsprogs: unpacked, not installed)
#   hfsplus, dmg                fill that volume, make the compressed disk image (Mozilla's libdmg-hfsplus, built from source)
#   rcodesign                   ad-hoc or Developer ID signing of a macOS app (apple-codesign, built from source with the SDK's cargo)
#
# The result goes into <native sysroot>/pkgtools with links in bin/, and is kept in cache/built/pkgtools-<key>.tar.zst; the key
# is the sha256 of this script and the lock file. A separate lock file, so that a new version of these tools does not rebuild
# OnAir's libraries (their key includes toolchain.lock).
#
# Usage:  build_pkgtools.sh -o <native sysroot> [--cache DIR]
# Needs:  gcc (cc), cmake, make, zlib1g-dev, liblzma-dev; the downloads: apt-get, curl, and crates.io for rcodesign.
set -Eeuo pipefail
export LC_ALL=C
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(dirname "$SCRIPT_DIR")"
OUT="" CACHE="$ROOT/cache"
while [ $# -gt 0 ]; do
  case "$1" in
    -o) OUT="$2"; shift 2;;
    --cache) CACHE="$2"; shift 2;;
    -h|--help) sed -n '2,/^set -E/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0;;
    *) echo "unknown argument $1 (see --help)" >&2; exit 2;;
  esac
done
die() { echo "error: $*" >&2; exit 1; }
say() { echo "==> $*"; }
[ -n "$OUT" ] && [ -x "$OUT/bin/cargo" ] || die "-o <native sysroot>: the folder fetch_toolchain.sh made (with bin/cargo)"
OUT="$(cd "$OUT" && pwd)"
LOCK="$SCRIPT_DIR/pkgtools.lock"
KEY=$(cat "$0" "$LOCK" | sha256sum | cut -c1-16)
BUILT="$CACHE/built/pkgtools-$KEY.tar.zst"

links() {   # bin/: relative links, and makensis through a script that says where its stubs are, so the folder can move
  for t in hfsplus dmg rcodesign mkfs.hfsplus fsck.hfsplus; do ln -sf "../pkgtools/bin/$t" "$OUT/bin/$t"; done
  cat > "$OUT/bin/makensis" <<'SH'
#!/bin/sh
d=$(dirname "$(readlink -f "$0")")/../pkgtools
NSISDIR="$d/share/nsis" exec "$d/bin/makensis" "$@"
SH
  chmod 755 "$OUT/bin/makensis"
}

if [ -f "$BUILT" ]; then
  say "packaging tools, from $BUILT"
  rm -rf "$OUT/pkgtools"; tar -I zstd -xf "$BUILT" -C "$OUT"; links; exit 0
fi

mkdir -p "$CACHE/work"
WORK=$(mktemp -d "$CACHE/work/pkgtools.XXXXXX"); trap 'rm -rf "$WORK"' EXIT
P="$WORK/pkgtools"; mkdir -p "$P/bin" "$P/share/licenses" "$CACHE/deb" "$CACHE/src"
UNPACK="$WORK/debs"; mkdir -p "$UNPACK"
while read -r kind name ver file rest; do
  case "$kind" in
    deb)
      f="$CACHE/deb/$file"
      if [ ! -f "$f" ]; then
        say "downloading $name $ver"
        (cd "$CACHE/deb" && apt-get download -q "$name=$ver" >/dev/null) || die "apt-get download $name=$ver failed (no longer in the archive?)"
      fi
      [ "$(sha256sum "$f" | cut -d' ' -f1)" = "$rest" ] || die "$f: sha256 is not the one in $LOCK"
      dpkg-deb -x "$f" "$UNPACK";;
    src)   # name, commit, archive name, "url sha256"
      read -r url sha <<<"$rest"
      f="$CACHE/src/$file"
      [ -f "$f" ] || { say "downloading $name $ver"; curl -fsSL --retry 6 --retry-delay 5 --retry-all-errors --connect-timeout 30 -o "$f.part" "$url" && mv "$f.part" "$f"; }
      [ "$(sha256sum "$f" | cut -d' ' -f1)" = "$sha" ] || die "$f: sha256 is not the one in $LOCK"
      mkdir -p "$WORK/$name"; tar -xf "$f" -C "$WORK/$name" --strip-components=1;;
    crate) RC_VERSION=$ver;;
  esac
done < <(grep -v '^#' "$LOCK")

# NSIS and the HFS+ tools: only what is used
cp "$UNPACK/usr/bin/makensis" "$P/bin/"; cp -R "$UNPACK/usr/share/nsis" "$P/share/"
cp "$UNPACK/usr/sbin/mkfs.hfsplus" "$UNPACK/usr/sbin/fsck.hfsplus" "$P/bin/"
for n in nsis hfsprogs; do mkdir -p "$P/share/licenses/$n"; cp "$UNPACK/usr/share/doc/$n/copyright" "$P/share/licenses/$n/"; done

say "libdmg-hfsplus"
BZ=$(find "$UNPACK" -name libbz2.a -print -quit); [ -n "$BZ" ] || die "no libbz2.a in libbz2-dev"
# OpenSSL only decrypts images, which these packages do not use; the sources say -lbz2, so the folder goes to the linker as well
cmake -S "$WORK/libdmg-hfsplus" -B "$WORK/dmg-build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_DISABLE_FIND_PACKAGE_OpenSSL=ON \
  "-DBZIP2_INCLUDE_DIR=$UNPACK/usr/include" "-DBZIP2_LIBRARY_RELEASE=$BZ" "-DCMAKE_EXE_LINKER_FLAGS=-L$(dirname "$BZ")" >/dev/null
cmake --build "$WORK/dmg-build" -j"$(nproc)" --target dmg-bin hfsplus >/dev/null
cp "$WORK/dmg-build/dmg/dmg" "$WORK/dmg-build/hfs/hfsplus" "$P/bin/"
mkdir -p "$P/share/licenses/libdmg-hfsplus"; cp "$WORK/libdmg-hfsplus/LICENSE" "$P/share/licenses/libdmg-hfsplus/"

say "rcodesign (apple-codesign $RC_VERSION)"
# --locked: the versions of the crate's own Cargo.lock; cargo checks each crate against the registry's checksum
CARGO_HOME="$CACHE/cargo" CARGO_TARGET_DIR="$WORK/rc-build" "$OUT/bin/cargo" install apple-codesign --version "$RC_VERSION" --locked --no-default-features --root "$WORK/rc" --quiet
cp "$WORK/rc/bin/rcodesign" "$P/bin/"
mkdir -p "$P/share/licenses/apple-codesign"
cp "$(find "$CACHE/cargo/registry/src" -maxdepth 2 -type d -name "apple-codesign-$RC_VERSION" -print -quit)"/LICENSE* "$P/share/licenses/apple-codesign/" 2>/dev/null || \
  echo "MPL-2.0: https://github.com/indygreg/apple-platform-rs" > "$P/share/licenses/apple-codesign/LICENSE.txt"

for t in hfsplus dmg rcodesign makensis mkfs.hfsplus; do [ -x "$P/bin/$t" ] || die "$t was not made"; done
mkdir -p "$CACHE/built"; rm -f "$CACHE"/built/pkgtools-*.tar.zst
tar -C "$WORK" -I 'zstd -T0 -10' -cf "$BUILT.part" pkgtools && mv "$BUILT.part" "$BUILT"
rm -rf "$OUT/pkgtools"; cp -R "$P" "$OUT/pkgtools"; links
say "packaging tools made, kept in $BUILT"
