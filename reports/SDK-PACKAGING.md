# Packaging OnAir from the clang SDK: Windows installer, macOS dmg, Linux debs

**Update, later on 2026-11-08: now implemented. See "Packaging" in `CLANG-BUILD-REPORT.md`, which uses `dpkg-deb` instead of CPack and has a provisional macOS image.**

Written as a plan (2026-11-08). Based on reading OnAir `main` 25034214, the `fix/clang-json-kv` diff and the SDK in
`~/onair/onair_windows_sysroot`. No package was built and nothing was run on Windows, a Mac or a Pi. Effort figures are rough estimates.

## Short answer

| Package | Difficulty | Plan | Blocking question |
|---|---|---|---|
| Windows `setup.exe` | Low | Keep `onair.nsi` as it is; new staging script fed from the SDK; `makensis` from Ubuntu's `nsis` | None |
| Linux `.deb` (amd64, arm64) | Medium | Keep the CMake/CPack rules; replace `dpkg-shlibdeps`; fix what a bundled SoapySDR and static GLFW break | Ubuntu 26.04 as minimum (decision 1) |
| macOS `.dmg` (arm64, x86_64) | High | Build and assemble the `.app` on Linux; sign with `rcodesign`; make the dmg on Linux only if it passes on a real Mac, otherwise on a macOS runner | Apple SDK licence (decision 2) |

## How it works today

| | Windows | macOS | Linux |
|---|---|---|---|
| Script | `tools/package/make_windows_cross.sh` | `make_dmg.sh` + `bundle_macos.py` | `make_deb.sh`, or `release.yml` directly |
| Built on | A maintainer's machine or the private `adswill/OnAir-ci`; the job in `release.yml` is off by default | GitHub `macos-15` and `macos-15-intel` | GitHub `ubuntu-22.04` and `ubuntu-22.04-arm` |
| Compiler | mingw-w64 GCC | Apple clang | GCC |
| Libraries | `~/onair-win-prefix` (`cross_deps_windows.sh`) | Homebrew; static LGPL FFmpeg | Ubuntu packages (`collect_radio_libs_linux.sh`); RTL-SDR Blog and static FFmpeg from source |
| Package tool | NSIS (`packaging/windows/onair.nsi`) | `codesign -s -` (ad hoc), `hdiutil` | CPack DEB with `dpkg-shlibdeps` |
| Runs on | Windows 10/11 | macOS 15+ | Ubuntu 22.04+ |
| Signed | No | Ad hoc, not notarised | No |

Also relevant:

- The updater depends on the file names (`core/src/engine/updater.cpp:269-273`): `*windows*-setup.exe`, `*macos*<arch>*.dmg`, `*.deb` with
  `amd64`/`arm64`. It runs the Windows setup with `/S`, and opens the dmg with `hdiutil attach` and copies the app with `ditto`. So the names stay,
  and a macOS zip is not an option without changing the updater.
- `release.yml` also builds a portable tar.gz, an AppImage and a Docker image from the Linux build. They are outside this report but are affected
  (see decision 1).

## What the SDK already gives, and what is missing

Already there: clang 23, a sysroot and toolchain file per target; all 15 libraries from source, with LGPL FFmpeg and licence files in
`share/licenses/<name>`; `SOURCES-FILES.txt` per sysroot (exactly which files are ours); `collect_dlls.sh`, `collect_dylibs.sh`, `macho.py`;
`x86_64-w64-mingw32-objdump` and `-strip`, `llvm-otool`, `llvm-install-name-tool`.

Missing on this machine and in the SDK: `makensis`, `rcodesign`, a dmg writer, `lintian`. `dpkg-deb`, `xorrisofs`, `genisoimage` and `docker` are present.
Ubuntu has candidates for `nsis` (3.10), `osslsigncode`, `xorriso`, `hfsprogs` and `lintian`, but none for `libdmg-hfsplus`.

Proposal: add the packaging tools to the SDK the way the mingw binutils are added now (`DEBS=` in `common/fetch_toolchain.sh`, pinned in
`toolchain.lock`), so no root and no system install is needed. `makensis` then needs `NSISDIR` pointed at its unpacked `share/nsis`.

## Shape of the implementation

New scripts in OnAir, next to the current ones, which stay until each target has been proven:

```
tools/package/sdk/windows.sh   SDK=... VERSION=...  -> OnAir-<v>-windows-x64.zip, -setup.exe
tools/package/sdk/deb.sh       --arch amd64|arm64   -> onair_<v>_<arch>.deb
tools/package/sdk/dmg.sh       --arch arm64|x86_64  -> OnAir-<v>-macos-<arch>.dmg
tools/package/sdk/all.sh       the five builds, SHA256SUMS
```

Every script: source `environment-setup-<triple>`, configure with `-DDECT2_BUILD_TESTS=ON` (the install rule for `dect2cli`/`dect2scan` needs it) and
`-DONAIR_VERSION=<v>`, build only the shipped targets, stage, run the checks, package. `add_license_files.sh`, `scrub_paths.py`, `check_win_dlls.sh` and
`check_lgpl_bundle.sh` are reused.

## Windows installer

The easiest: it is already a cross build, and `onair.nsi` needs only `VERSION`, `SRC`, `ICON`, `OUTFILE`. Steps:

1. Build `dect2 dect2cli dect2scan onair-server` with the SDK toolchain, `DECT2_WITH_TLS=ON`, `DECT2_HAVE_HAMLIB=ON`.
2. Stage as `make_windows_cross.sh:33-89` does, with these changes:
   - `$P/bin` becomes `$WIN_SYSROOT/bin`; the `redist/` folder and `x86_64-w64-mingw32-g++ -print-file-name` go. `libstdc++-6`, `libgcc_s_seh-1` and
     `libwinpthread-1` come from the sysroot through `collect_dlls.sh`, as does anything else imported (zlib ...).
   - Radio DLLs as extra names to `collect_dlls.sh`; `lib/SoapySDR/modules0.8/libremoteSupport.dll`; `FTD3XX.dll` stays unstripped (FTDI's signature).
   - Licences: copy `share/licenses/<name>` only for what is shipped. The sysroot also holds binutils, gettext and others that are not.
   - No `libusb-1.0.dll` any more: libusb is static or inside each DLL.
3. `check_win_dlls.sh` with `OBJDUMP` from the SDK, `check_lgpl_bundle.sh`, zip, `makensis`.

To add while there, both small: `-DONAIR_VERSION` (the current script does not pass it, so a Windows beta appears to report the plain version, while
`CMakeLists.txt:516` says the updater needs the beta string), and `SetCompressor /SOLID lzma` in `onair.nsi` for a smaller setup.

Optional, needs a code-signing certificate: `osslsigncode` on the exe and DLL files before `makensis`, and the `!finalize` / `!uninstfinalize` hooks of NSIS for
the setup and uninstaller. Without it, SmartScreen warnings stay as today.

Test on a real Windows PC: install, upgrade over a release (`/S` as the updater does), start, radio enumeration, uninstall. About 1 day, plus the test.

Watch out: the FFT notes say #448 (`feat/ffmpeg-dynamic`, in 3.8-rc) delay-loads FFmpeg on Windows. The SDK has FFmpeg static only, so check how that branch behaves with it before 3.8 goes this way.

## Linux debs

The CMake rules (`CMakeLists.txt:2596-2680`) stay, including the udev rules, blacklists, `postinst`, `postrm`. `cpack -G DEB` needs no container. What has to change:

**1. Dependencies: `dpkg-shlibdeps` cannot be used.** It reads the build machine's package state, and the sysroot has no dpkg database. CMake's own issue
[#24173](https://gitlab.kitware.com/cmake/cmake/-/issues/24173) describes this case: even once it ran, the sysroot packages were missing from the result.
Proposal: `CPACK_DEBIAN_PACKAGE_SHLIBDEPS=OFF` and `CPACK_DEBIAN_PACKAGE_DEPENDS` written by a new SDK script:
read `NEEDED` from every ELF file in the stage (`llvm-readobj`), drop what is bundled, map each soname through the `shlibs` file of the pinned `.deb`s in
`cache/ubuntu` (checked: `libstdc++6` has one), and use the version from the lock file as the minimum. An unmapped soname fails the build.

**2. Static GLFW hides the graphics dependencies.** Today `libglfw3` is a shared dependency, which brings in GL and X11. GLFW now loads them at run time, so `NEEDED` will not show them.
They must be listed by hand (`libgl1`, Wayland and xkbcommon libraries), or OnAir could install on a machine where it cannot open a window. (Correction after the real build: the clang `dect2` does list `libX11.so.6` in `NEEDED`, so that one is found automatically. It also carries a RUNPATH of `/usr/local/lib`, which must be replaced by `/usr/lib/onair`.)

**3. `onair-server` would not find its libraries.** `CMakeLists.txt:2623` sets the rpath for `dect2 dect2cli dect2scan` only. `onair-server` links `dect2core`, which
links SoapySDR publicly, and SoapySDR now lives in `/usr/lib/onair` rather than coming from Ubuntu. Add `onair-server` (and check `onair-plugin-host`). Found by reading CMake, not by running it.

**4. The SoapyRemote module would not be found.** The SDK's SoapySDR has prefix `/usr/local`, and `soapyLocateModules()` (`source_soapy.cpp:49`) has branches for Windows and macOS only.
Add a Linux branch that sets `SOAPY_SDR_PLUGIN_PATH` to `../lib/onair/SoapySDR/modules0.8`. Then remove `soapysdr-module-remote` from Recommends, because it would pull in Ubuntu's SoapySDR next to ours.
The Suggests line (`hackrf, librtlsdr0, ...`) can go as well.

Smaller items:

- **Architecture:** set `CPACK_DEBIAN_PACKAGE_ARCHITECTURE` explicitly. [The default is the build machine's](https://cmake.org/cmake/help/v3.20/cpack_gen/deb.html), which would label the Pi package `amd64`.
- **Radio folder:** a new step builds `DECT2_RADIO_LIB_DIR` from `SOURCES-FILES.txt` (versioned `.so` files and their links, plus the module), replacing `collect_radio_libs_linux.sh`, which uses `ldd` and `patchelf`.
- **Paths:** pass `-DCMAKE_INSTALL_LIBDIR=lib`. Some rules hard-code `lib/onair`, others use the variable, and the variable's value can differ in a cross build.
- **Host leaks:** `CMakeLists.txt:2652` reads `/usr/share/doc/libhamlib2/copyright` from the build machine. Use the sysroot's `share/licenses/hamlib`. Check `find_library(HAMLIB_BUNDLE_LIB)` too, because the toolchain re-roots searches into the sysroot.
- **arm64 CPU:** build the deb with `-DRPI_CPU=generic`. The SDK's default is `-mcpu=cortex-a76`, and the updater offers the one arm64 deb to every arm64 machine, so a Pi 4 could crash on an illegal instruction.
- **Test:** `lintian`, plus installing in a clean Ubuntu 26.04 container for amd64. arm64 needs a real Pi, since there is no qemu here.

About 2-3 days.

## macOS dmg

Every tool in `make_dmg.sh` is Apple's or Homebrew's (`brew`, `otool`, `install_name_tool`, `codesign`, `hdiutil`), so this is a rewrite. Steps:

1. **Build** with `CMAKE_INSTALL_RPATH=@executable_path/../Frameworks` and `CMAKE_BUILD_WITH_INSTALL_RPATH=ON`.
2. **Bundle:** `.app` layout, Info.plist, icon, web, licences and firmware as now. `collect_dylibs.sh` replaces `bundle_macos.py`. The SDK's dylibs have `@rpath` names, so they need no rewriting, which also means less re-signing.
   OnAir already looks in `../Frameworks` (`native_common.h:210`) and tries `lib<stem>.<version>.dylib`, which matches the SDK's names.
   The module goes to `Frameworks/SoapySDR/modules/`, the folder `source_soapy.cpp:78` expects.
3. **Checks:** `macho.py check` replaces `check_macos_target.py`, which calls `otool`.
   **`check_lgpl_bundle.sh` must change:** line 15 calls `otool`. On Linux that fails silently, the list stays empty, and the check passes without having looked. Use `llvm-otool` and treat a tool failure as a failure.
4. **FFmpeg notice:** `make_dmg.sh:71-77` describes `build_ffmpeg_static.sh`; it must describe `build_sources.sh` and its configure line. Same for `docs/LICENSE-NOTICES-BINARIES.md`. The Homebrew licence loop goes.
5. **Signing:** `rcodesign` [signs `.app` bundles on Linux and can notarise and staple](https://gregoryszorc.com/docs/apple-codesign/main/apple_codesign_rcodesign_notarizing.html). What I could not confirm from its docs is the ad-hoc mode without a certificate, which is what OnAir uses now. Test this first, because it is required: arm64 Macs refuse unsigned code, and the SDK README already says LLVM's re-signing was "not checked on a Mac".
6. **The dmg itself** is the weakest part. `hdiutil` has no Linux equivalent. Candidates are `libdmg-hfsplus` with `genisoimage`/`xorrisofs` (not in Ubuntu, several forks, and [Mozilla's bug](https://bugzil.la/935237) reports images failing to mount with "Invalid checksum" with one of them) or `mkfs.hfsplus`, which [was used on a loop mount](https://bugzilla.cendio.com/show_bug.cgi?id=4329), so it needs root and gives no compression.

**Recommendation:** split it. Do steps 1-5 on Linux and pack the `.app` in a tar. Try `libdmg-hfsplus` for one day, with this test on a real Mac: `hdiutil verify`, double-click mount with symlinks intact, Gatekeeper first start, and an update through OnAir's updater. If that fails, a small macOS runner job makes the dmg from the tar with the existing `hdiutil create` line. That job needs no compiler and is a few lines of CI, and the macOS tests need a Mac anyway.

**Also changes:** the minimum goes from macOS 15 to 12 (`LSMinimumSystemVersion` follows it), which is better but unproven. The SDK build ships conda-forge's libc++ inside the app.

**Notarisation** is optional and separate: it needs an Apple Developer account, the hardened runtime, and an entitlement for loading libraries that users install themselves (SDRplay, Fobos).

About 3-5 days, including the Mac test. Nothing can be proven without a Mac.

## Decisions for you

1. **Ubuntu 26.04 as the minimum for debs.** This follows your SDK decision, but it is a big step from today's 22.04: Ubuntu 22.04 and 24.04 users lose the package, and so does Raspberry Pi OS. `packaging/docker/Dockerfile` installs the deb on `ubuntunoble` (24.04), which would stop working until its base image moves. The portable tar.gz and AppImage get the same minimum if they move too.
   Recommendation: accept it only if you are fine losing those users; otherwise add a second, older Linux sysroot, which keeps the same scripts.
2. **Apple SDK licence.** The SDK's own manifest records Apple's terms: "for use on Apple-branded computers". Building official macOS releases on Linux with it may conflict with that. This is a question for you or the project owner, not one I can settle.
   If it is a problem, the whole macOS package stays on a macOS runner, using the SDK's libraries or the current scripts.
3. **UHD.** Today's Linux and macOS packages ship it (`bundle_macos.py` even requires it); the SDK leaves it out. Windows already relies on the Ettus installer.
   Recommendation: stop shipping it everywhere and tell USRP users to install UHD themselves, with `Suggests: libuhd` on the deb.
4. **FFmpeg size.** Releases on macOS and Linux use the reduced build of `build_ffmpeg_static.sh`; the SDK uses the fuller configure of `cross_deps_windows.sh`. Packages will probably grow. Measure once, then decide whether the SDK should use the reduced one.

## Order

1. Windows: lowest risk, and it proves the staging approach.
2. Linux debs, once decision 1 is made.
3. macOS, once decision 2 is made, starting with an ad-hoc `rcodesign` test on a Mac.
4. `all.sh`, then compare with a current release (file list and size) before anything replaces the old scripts. CI stays untouched until then.

## Sources

- [rcodesign: notarizing and stapling](https://gregoryszorc.com/docs/apple-codesign/main/apple_codesign_rcodesign_notarizing.html), [apple-codesign README](https://docs.rs/crate/apple-codesign/latest/source/README.md)
- [Mozilla bug on making dmgs on Linux](https://bugzil.la/935237), [Cendio bug: mkfs.hfsplus route](https://bugzilla.cendio.com/show_bug.cgi?id=4329), [libdmg-hfsplus fork](https://github.com/symbioquine/libdmg-hfsplus)
- [CMake issue 24173: dpkg-shlibdeps with a sysroot](https://gitlab.kitware.com/cmake/cmake/-/issues/24173), [CPack DEB generator](https://cmake.org/cmake/help/v3.20/cpack_gen/deb.html)
