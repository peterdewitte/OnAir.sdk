# SPDX-License-Identifier: GPL-3.0-or-later
#
# CMake toolchain file: cross-compile for macOS on x86_64 (Intel) on Linux with clang and ld64.lld, against the
# target sysroot sysroots/x86_64-apple-darwin (macos/fetch_sysroot.sh --arch x86_64).
#
#   cmake -S <src> -B <build> -G Ninja -DCMAKE_TOOLCHAIN_FILE=<this file> [-DCMAKE_OSX_SYSROOT=<sysroot>] ...
#
# Everything else is in toolchain-apple-darwin-common.cmake (next to this file).
set(MACOS_ARCH x86_64)
include("${CMAKE_CURRENT_LIST_DIR}/toolchain-apple-darwin-common.cmake")
