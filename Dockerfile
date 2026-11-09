# SPDX-License-Identifier: GPL-3.0-or-later
#
# The build machine as an image: Ubuntu 26.04 with what make_sdk.sh and build.sh need. The scripts and results stay in this folder,
# which is mounted at /work, so ./cache is kept between runs.
#
#   docker build --build-arg UID=$(id -u) --build-arg GID=$(id -g) -t onair-sdk .
#   docker run --rm --init -v "$PWD":/work onair-sdk
#
# See README.md, "Build everything in Docker".
FROM ubuntu:26.04

ARG UID=1000
ARG GID=1000

# The package lists stay in the image: the SDK's scripts use apt-get download and apt-cache for pinned packages that are not in ./cache yet.
#   git ca-certificates                checkout_onair.sh
#   cmake ninja-build pkgconf          the builds
#   curl zstd xz-utils bzip2 unzip gpg gpg-agent gpgv   make_sdk.sh: download, unpack, check signatures
#   python3                            make_sdk.sh: the dependency resolver and the checks; the package scripts
#   make perl nasm patch               sources/build_sources.sh: configure scripts, FFmpeg
#   libwayland-bin                     wayland-scanner, for GLFW's Wayland support (Linux targets)
#   gcc g++ libc6-dev zlib1g-dev liblzma-dev   common/build_pkgtools.sh: libdmg-hfsplus and rcodesign run on the build machine
#   binutils file zip                  OnAir's package scripts: readelf, strings, file type checks, the Windows zip
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      git ca-certificates \
      cmake ninja-build pkgconf \
      curl zstd xz-utils bzip2 unzip gpg gpg-agent gpgv \
      python3 \
      make perl nasm patch \
      libwayland-bin \
      gcc g++ libc6-dev zlib1g-dev liblzma-dev \
      binutils file zip

# Not root, and the user's own ids so the files in the mounted folder stay theirs. Not root also because OnAir's scrub_paths.py replaces the
# build user's name in every shipped program: the name "root" occurs in real strings and would corrupt them, so the name here is one that does not.
RUN groupadd -o -g "$GID" onairbld && useradd -o -m -u "$UID" -g "$GID" onairbld
USER onairbld
ENV HOME=/home/onairbld USER=onairbld LOGNAME=onairbld
WORKDIR /work

CMD ["./build.sh"]
