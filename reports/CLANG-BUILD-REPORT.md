# OnAir clang SDK: full build, tests, packages and GCC comparison

2026-11-08. Machine: Xeon W-2145 VM, 16 threads, 31 GB, Ubuntu 26.04. Source: `fix/clang-json-kv` (9f1c9dc0) plus the test fixes in `ffb5606e`.
Compilers: clang 23.1.5 (the SDK) and GCC 15.2 (the system). ccache off in every run: `-DDECT2_CCACHE=OFF`, `CCACHE_DISABLE=1`, and no `ccache` in any `build.ninja`.

## Result

- **All 5 clang targets build completely**, tests included, with 0 failed steps. Your `fix/clang-json-kv` was not enough: 11 test files needed small fixes (below).
- **Clang compiles about 38% faster than GCC** and uses about 42% less CPU and half the peak memory.
- **Tests were run on Linux only.** Clang 1311 of 1342 passed, GCC 1312 of 1342. The test suite runs about 8% faster with clang.
- **Do not release from this yet:** 7 tests fail on clang only, even when run alone, and 4 on GCC only. Their causes are not established. 22 more fail on both compilers.
- Nothing was run on Windows, a Pi or a Mac. For those targets, "builds" means compiled and linked, nothing more.
- **Packages exist for all architectures** (Windows x64, Linux amd64 and arm64, macOS arm64 and x86_64), including real signed macOS disk images, but only the amd64 programs have been started and nothing has run on a Mac. See "Packaging" below.

## SDK cleanup

- All 15 libraries of `cross_deps_windows.sh` are built from source for all 5 targets, at the script's versions, with the 3 patches.
- 86 old downloaded packages of those libraries (135 MB) were deleted from `cache/`. None was named in a lock file.
- `make_sdk.sh` then regenerated the whole SDK from the locks in about 1 minute using the cached library builds (4.5 GB). Nothing needed the deleted files. The libraries were not recompiled, because their build keys still match.
- **Left in place:** 694 other unused files (444 MB) in `cache/`. They are dependencies of the old GPL FFmpeg (x265, libjxl ...), not libraries from the script. Your call.

## Compile speed

Clean build at `-j16`, app and all tests (about 4690 steps).

| Build | Run | Wall | CPU (user + sys) | Peak memory, one process |
|---|---|---|---|---|
| GCC 15.2, Linux | 1 (ran first) | 1464 s | 22664 s | 2.09 GB |
| GCC 15.2, Linux | 2 (ran second) | 1437 s | 22804 s | 2.09 GB |
| clang 23, Linux | 1 (2 steps failed) | 919 s | 13258 s | 1.00 GB |
| clang 23, Linux | 2 (clean) | 885 s | 13241 s | 1.00 GB |

Run order was reversed between rounds and the result held. Means: 1450 s against 902 s.

Other clang targets, first round, not clean, so a few test steps are missing:

| Target | Wall | CPU | Failed steps then |
|---|---|---|---|
| Windows x64 | 880 s | 13045 s | 0 |
| Raspberry Pi 5 | 922 s | 13590 s | 2 |
| macOS arm64 | 841 s | 12916 s | 9 |
| macOS x86_64 | 836 s | 12138 s | 9 |

**Not identical setups:** GCC uses GNU ld and Ubuntu's shared libraries; clang uses lld and the SDK's static ones. Hamlib is missing on this machine, so GCC built without that code. The step counts differ by only one. Clang's speed includes its linker, so this compares the two toolchains, not just the compilers.

## Fixes the build needed (`ffb5606e`)

Local branch `fix/clang-sdk-all-targets`, on top of yours, not pushed. 11 files, tests and test build only.

| Problem | Where | Fix |
|---|---|---|
| Missing includes (libc++ does not bring them along) | 9 test files, on macOS | `<cstdlib>` or `<vector>` |
| Narrowing `unsigned long` to `uint32_t` | `test_hfdl_proto_rs.cpp`, Linux and Pi | Cast |
| lld refuses static FFmpeg inside a shared module | `SoapyOnAirTest`, Linux and Pi | `-Wl,-Bsymbolic`, not on Apple |

The other warnings are mostly `-Wdeprecated-declarations` (187 on both compilers); none was fixed. GCC also gives 77 `-Wformat-truncation` and 46 `-Wstringop-overflow`.

## Tests

Both complete at `-j 10`, in the same order, without `sens_full` (which has its own 10-hour limit; left out at your request).

| | clang 23 | GCC 15.2 |
|---|---|---|
| Passed, of 1342 | 1311 | 1312 |
| Failed | 30 | 29 |
| **Sum of all individual test times** | **36942 s (10.26 h)** | **40229 s (11.17 h)** |
| Sum over the 1304 tests passed on both | 31442 s | 34294 s |
| Wall time | 4516 s | 4806 s |

- Clang's sum is about 8% lower. It was faster in 733 tests, GCC in 571, so this is an average and not true of every test.
- Largest differences: clang wins `atv_radio_sweep` (201 s, GCC 410 s) and `atv_systems` (113 s, 252 s). GCC wins `ofdm_csi` (714 s, clang 1218 s) and `aero_crowded` (481 s, clang 629 s).
- These times are taken under load, and the two builds use different libraries.

### Failed on one compiler, and still fails when run alone

Rerun only on the compiler that failed. The same test passed on the other compiler under the heavier `-j 10` load, so load does not explain these. **Causes below are not established.**

| Fails on | Test | Failure |
|---|---|---|
| clang | `atsc3_synth_options` | "L1-Detail mode 4": 1 frame failed, audio and video too short |
| clang | `dvbc_rx` | 256-QAM with -10 dB echo: no lock |
| clang | `eloran_detect` | 0 dB: 2 stations found, 3 wanted |
| clang | `gnss_qzss_sbas` | S28: 0 SBAS messages in 60 s |
| clang | `dab_audit` | Deep fade: 12.48 cutouts/min, limit 10 |
| clang | `kaal_v4_impair` | Lock time 1.166 |
| clang | `pskdsp_analyse` | Doppler 185.2 Hz/s reported, for 120 Hz/s |
| GCC | `diversity` | Unequal branches, -6 / 1 dB: MRC does not lock |
| GCC | `marine_slow_navtex_snr` | Fading: 4 exact at 6 dB, CER 0.1236 at 0 dB |
| GCC | `atv_switch` | Report count and time; labelled `timing` |
| GCC | `mesh_presets` | Speed: 2.22x real time, limit 3x |

Passed when rerun alone, so load: `iq_modes` (clang); `voice_inversion`, `inmc_slow_rates`, `mesh_rx` (GCC).

Where to look first (leads, not conclusions):

1. **Different code paths.** `core/src/dsp/dsp_compat.cpp` chooses FFT and FMA paths by compiler (`__clang__` at lines 123, 269, 292), and the FFT notes say the multi-stage passes run on clang only. Different floating-point results could push receivers just past a limit. It fits the threshold failures, but it is unproven.
2. **Different FFmpeg.** The SDK's LGPL FFmpeg has no x265: GCC reports "video hevc", clang "video other" in `atsc3_synth_options`. So that test does not exercise the same stream on both.
3. **The real test:** run the 7 clang-only tests on clang with the same libraries as GCC, and with the FFT path forced to match. I did not do this.

### Failed on both (22), not rerun, as you asked

Not caused by the compiler.

**Speed and real-time limits (13), the kind you called incorrectly written:** `atsc3_synth_basic`, `atv_fm`, `dab_gen`, `dab_search`, `gnss_rate20`, `gnss_rates`, `gnss_rx`, `hfdl_speed`, `kaft_engine`, `mesh_rates`, `specx_idmatrix`, `specx_idmatrix_quick`, `tx_quality_b`.
Clang was usually closer to the limit. Only 4 of these 13 carry the `timing` label. `specx_idmatrix` on GCC also has a top-1 accuracy failure, 40.6% against 42%, so it is not purely timing.

**Other reasons (9), which do not look like timing:**

| Test | Failure |
|---|---|
| `sarsat_rx` | Cannot open `tests/data/sarsat/epirbsignal_223.wav`; a data file problem in this tree |
| `audio_engine` | FT8 from a sound card: 0 stations |
| `gain` | Winner is not the best SNR |
| `gnss_engine` | No fix |
| `kaal_chain` | 33 failures, same first line on both |
| `marine_slow_dsc_snr` | VHF 6 dB: 2 calls with a good ECC but wrong fields |
| `native` | Tone value is an absurdly large number; looks like uninitialised or invalid data |
| `web_server` | Fails in 4 s with no output |
| `hfdig_ft8` | Hit the 1500 s limit, 0 FAIL lines |

These may be this machine (a VM with no sound or radio hardware) or real bugs. I did not look into them.

## Why a sysroot is preferable

A sysroot is a folder that holds everything a target system offers a compiler: headers, libraries and start-up files. The compiler is told to use that folder instead of the machine it runs on (`--sysroot=...`). In this SDK there is one per target, under `sdk/sysroots/`.

| Way to build | Problem | What a sysroot changes |
|---|---|---|
| Native build on each OS, as releases do now | Needs a Mac and a Windows machine or runner; each has its own compiler and library versions | One Linux machine built all 5 targets, about 15 minutes each |
| Packages from `apt`, Homebrew, MSYS2 at build time | Versions change without warning, and CI and your own machine can drift apart | Exact package versions and sha256 sums in lock files |
| The build machine's own libraries | Results depend on what happens to be installed. Your own build shows it: GCC here silently built without Hamlib | The toolchain looks only in the sysroot, so nothing from the machine leaks in |
| Docker containers | Still one image per architecture; a foreign architecture needs slow emulation, as `make_deb.sh` warns | No emulation: clang generates code for any target directly |
| `~/onair-win-prefix`, hand-built and machine-specific | Exists only on the maintainer's machines, so the CI job for it is off by default | `make_sdk.sh` regenerates it from the locks; it took about 1 minute with the library builds cached |

Other benefits:

- **Safe to move:** the SDK needs no root and installs nothing, and it can be moved or carried to another machine as one folder.
- **Several at once:** targets cannot affect each other.
- **Old base systems:** a sysroot could also target an older system than the build machine. That is the way to lower the Ubuntu 26.04 minimum later, if you want to.

What it costs or does not solve:

- **It cannot run what it builds.** You still need the real Windows, Pi or Mac to test on.
- **Someone has to maintain it:** 4.5 GB of SDK, 2.9 GB of cache, and lock-file updates.
- **Licences:** Apple's SDK terms apply, and redistributing the SDK itself is not yet licence-compliant (`STATUS.md`). Sharing the scripts is fine.
- **A new toolchain can change behaviour.** See the 7 clang-only failures above.

## Windows build by hand

### Smallest example

Tested today. It proves the whole chain: compiler, sysroot, a library built from source, and the DLL collector.

```bash
SDK=~/onair/onair_windows_sysroot/sdk
. $SDK/environment-setup-x86_64-w64-mingw32    # sets CC, CXX, PATH, pkg-config to look in the sysroot only

cat > hello.cpp <<'CODE'
#include <hackrf.h>
#include <cstdio>
int main() { printf("libhackrf %s\n", hackrf_library_version()); }
CODE

$CXX hello.cpp -o hello.exe $(pkg-config --cflags --libs libhackrf) -lpthread
file hello.exe                 # PE32+ executable for MS Windows, x86-64
$SDK/collect_dlls.sh hello.exe # copies the 1 DLL it needs: libwinpthread-1.dll
```

`$CXX` is `clang++ --target=x86_64-w64-windows-gnu --sysroot=$SDK/sysroots/x86_64-w64-mingw32 ...`.

`-lpthread` is needed by hand because clang's MinGW driver does not link winpthreads by itself. CMake builds get it from the SDK's toolchain file. `libhackrf.pc` should really list it, a small SDK fix still to do.

### OnAir itself, by hand

These are the steps `tools/package/sdk/windows.sh` runs.

```bash
SDK=~/onair/onair_windows_sysroot/sdk
. $SDK/environment-setup-x86_64-w64-mingw32
cd <OnAir source>

# 1. configure
cmake --fresh -S . -B build-win -G Ninja -DCMAKE_BUILD_TYPE=Release \
      -DDECT2_BUILD_APP=ON -DDECT2_BUILD_TESTS=ON -DDECT2_HAVE_HAMLIB=ON \
      -DDECT2_WITH_TLS=ON -DOPENSSL_USE_STATIC_LIBS=TRUE -DONAIR_VERSION=3.6.0

# 2. build the programs (leave out --target to build all tests too)
cmake --build build-win -j14 --target dect2 dect2cli dect2scan onair-server

# 3. a folder with the programs and the DLLs they need
S=build-win/OnAir-3.6.0-windows-x64; mkdir -p $S
x86_64-w64-mingw32-strip -o $S/OnAir.exe build-win/dect2.exe
x86_64-w64-mingw32-strip -o $S/onair-server.exe build-win/onair-server.exe   # likewise onair-cli.exe, onair-scan.exe
$SDK/collect_dlls.sh $S/OnAir.exe "$WIN_SYSROOT" librtlsdr.dll libairspy.dll libairspyhf.dll \
      libbladeRF.dll libiio.dll libLimeSuite.dll 'libhamlib-*.dll' FTD3XX.dll
cp build-win/libcodec2.dll $S/

# 4. check: every imported DLL and function exists, FFmpeg is the LGPL build
OBJDUMP=x86_64-w64-mingw32-objdump tools/package/check_win_dlls.sh $S
tools/package/check_lgpl_bundle.sh $S/OnAir.exe

# 5. the installer (web pages, licences and firmware must be in the folder first: see windows.sh)
makensis -DVERSION=3.6.0 -DSRC=$PWD/$S -DICON=$PWD/packaging/windows/OnAir.ico \
         -DOUTFILE=$PWD/OnAir-3.6.0-windows-x64-setup.exe packaging/windows/onair.nsi
```

Or all of it in one go: `MAKENSIS=makensis tools/package/sdk/windows.sh`.

## Benefits of reproducible builds across platforms

Reproducible here means the same compiler, library versions and scripts for every target, all pinned by lock files.

1. **A bug belongs to the code, not the build.** A failure can no longer be "that machine had another FFmpeg". Today each platform has its own compiler and library set.
2. **One machine builds everything.** All 5 targets build on one Linux machine. The macOS compile failures in this job were found without a Mac.
3. **Old versions can be rebuilt.** Homebrew and MSYS2 move on; a lock file records exactly what a release was built from, as long as the pinned downloads stay available.
4. **Licences can be proven.** The FFmpeg configure line, versions and hashes are recorded per target, so "this release is LGPL" can be checked. That also supports the LGPL source offer.
5. **Supply-chain checking.** Inputs are pinned by hash, and if the output is bit-for-bit identical, someone else can rebuild a release and confirm it matches.
6. **Upgrades happen on purpose.** Nothing changes because a runner image was updated overnight; a library upgrade is one line in a lock file that you can test on its own.
7. **Simpler CI.** A cached SDK and one script replace `brew install`, `apt-get` and private vendor tarballs.

**It does not remove real platform differences:** CPUs, operating systems and runtimes still differ, and binaries still need running on the real system.

### Measured: is the output really identical?

`onair-server` was built twice, in two clean folders with the same settings, and the results compared.

| Target | Result | Differing bytes |
|---|---|---|
| Linux x86-64 | **Identical** | 0 of 70.8 MB |
| Windows x64 | Nearly | 6 of 75.8 MB |
| macOS arm64 | Nearly | 484 of 58.1 MB |

- **Linux** is fully reproducible for this program.
- **Windows:** the small difference fits PE and COFF time stamps, and all 400 sampled object files differ too. I expect `--no-insert-timestamp` (and a matching compiler option) would fix it, but neither the cause nor that fix has been tested.
- **macOS:** the object files are identical, so the difference comes from the link step. It fits the code signature or UUID, or the second folder's name. Not investigated.
- Whole packages were not compared. They also contain file dates (the deb, zip and images) that would need `SOURCE_DATE_EPOCH` or similar.

So today: same inputs on all targets, and bit-for-bit identical on Linux only.

## Packaging: the options and what was built

### Options

| Platform | Options | Chosen, and why |
|---|---|---|
| Windows | NSIS `setup.exe`, plain zip, MSI | NSIS plus zip: already in OnAir, the updater needs `-setup.exe` and runs it with `/S`, and `makensis` runs on Linux |
| Linux | `.deb`, AppImage or portable tar.gz, CPack or `dpkg-deb` directly | `.deb`, built from the CMake install rules with `dpkg-deb` |
| macOS | Compressed dmg (`hdiutil` on a Mac, or `libdmg-hfsplus` on Linux), ISO-format image, zip | Compressed dmg made on Linux with `libdmg-hfsplus`, app signed ad hoc with `rcodesign`, as releases are signed now with Apple's `codesign` |

**One change from my packaging report:** I used `dpkg-deb` directly instead of CPack. It needs no changes to the CPack settings and gave the same result with less risk. The macOS route also changed: `mkfs.hfsplus` works on a plain file, without root, together with `libdmg-hfsplus`, the route Firefox's cross builds use.

### Built: all architectures

Version 3.6.0, source `feature_sdk_packaging`. In `~/onair/OnAir/.claude/worktrees/clang-sdk-build/packages/`, with `SHA256SUMS`, built by `tools/package/sdk/all.sh` at `-j14` using only tools from the SDK.

| File | Target | Size | State |
|---|---|---|---|
| `OnAir-3.6.0-windows-x64-setup.exe` | Windows 10/11 x64 | 91 MB | Complete, not code-signed |
| `OnAir-3.6.0-windows-x64.zip` | Windows 10/11 x64 | 125 MB | Complete |
| `onair_3.6.0_amd64.deb` | Ubuntu 26.04+ x86-64 | 100 MB | Complete |
| `onair_3.6.0_arm64.deb` | Ubuntu 26.04+ arm64, any CPU (Pi 4, Pi 5 ...) | 96 MB | Complete |
| `OnAir-3.6.0-macos-arm64.dmg` | macOS 12+ Apple silicon | 68 MB | Complete, signed ad hoc, not notarised |
| `OnAir-3.6.0-macos-x86_64.dmg` | macOS 12+ Intel | 71 MB | Complete, signed ad hoc, not notarised |

### What was checked

| Check | Windows | amd64 deb | arm64 deb | macOS (both) |
|---|---|---|---|---|
| Imports and libraries complete | Yes, `check_win_dlls.sh` | Yes, `ldd` | Dependency script only | Loads only from the app and the system |
| LGPL FFmpeg, no GPL libraries | Yes | Yes | Yes | Yes |
| Correct CPU and paths | Yes | RUNPATH `/usr/lib/onair` | AArch64, `-mcpu=generic` | rpath into `Frameworks`, minimum macOS 12 |
| Dependencies accepted by apt | | Yes, simulated | | |
| Signatures | | | | All 14 Mach-O files match their page hashes; 85 files match the bundle seal |
| Disk image | | | | Volume passes `fsck`; image gives the volume back byte for byte, with Apple's `koly` trailer; all 86 files equal the signed app |
| Build-machine paths | Scrubbed | Scrubbed | Scrubbed | Scrubbed before signing, 0 left in the programs |
| **Started for real** | No | `onair-server --version` and `onair-cli` run from the unpacked deb | No | No |

### Not checked, so do not ship yet

- **Nothing has run on Windows, a Pi or a Mac,** and the installer has never been run. The amd64 deb was not really installed, since Docker and root are not available to this user, and the GUI was not started.
- **`lintian` was not run,** because it would need root to install its dependencies.
- **The tests were not rerun on the packaging branch.** The code changed slightly after the test runs (the SoapySDR module search on Linux and the rpath), and the same unexplained test failures still apply to these binaries.
- **The dmgs have not been opened on a Mac.** The checks above are all done on Linux. `rcodesign verify` cannot read ad-hoc signatures, so `macho.py bundlecheck` recomputes the hashes instead, which is my own check and not Apple's. Mounting, Gatekeeper and starting the app still need a real Mac.
- **Expected on a Mac:** the same first-start prompt as today's ad-hoc signed releases, and not notarised.

### Assumptions, since those questions are still open

- **Ubuntu 26.04 minimum:** Ubuntu 22.04 and 24.04 and Raspberry Pi OS cannot install these debs, and the Docker image on 24.04 would break.
- **UHD is not shipped.** The deb has `Suggests: libuhd4.9.0`.
- **Apple's SDK licence:** these are local test builds, not published. Whether official macOS releases may be built this way is still your or the project owner's call.

### Tools added to the SDK

`common/build_pkgtools.sh` and `common/pkgtools.lock`, called by `make_sdk.sh`: `makensis`, `mkfs.hfsplus`, `fsck.hfsplus` (Ubuntu packages, unpacked), `hfsplus`, `dmg` (libdmg-hfsplus e18579b, built from source) and `rcodesign` 0.29.0 (MPL-2.0, built with the SDK's cargo). They are in `sysroots/x86_64-sdk-linux/bin`.

- A separate lock file, so that a change to these tools does not rebuild OnAir's libraries.
- Generating the SDK now takes about 2 minutes the first time, and the tools are cached.
- The first build needs `gcc`, `zlib1g-dev` and `liblzma-dev` on the build machine.

## Packaging commits

`feature_sdk_packaging`, on top of `fix/clang-sdk-all-targets`, local only:

- `tools/package/sdk/`: `common.sh`, `windows.sh`, `deb.sh`, `deb_depends.py`, `dmg.sh`, `all.sh`
- `source_soapy.cpp`: Linux finds the module in `../lib/onair/SoapySDR/modules0.8`
- `CMakeLists.txt`: rpath for `onair-server` and `onair-plugin-host`
- `check_lgpl_bundle.sh`: no longer passes a Mach-O file when `otool` is missing
- `onair.nsi`: `SetCompressor /SOLID lzma`

The old scripts were not changed. The SDK folder holds its own changes, uncommitted like the rest of that repo.

## What was not done

- `sens_full` and the rest of the first clang `-j4` run were stopped at your request. `session_bench`, `session_soak_10min` and `dvbt_usb_drops` ran in the `-j 10` runs instead.
- Tests on Windows, Pi and macOS, at your request.
- The summed times are from one run per compiler.
- The sysroot repo is still uncommitted, as the previous session left it. `.claude/STATUS.md` there is now updated. `toolchain-x86_64-linux-gnu.cmake` also still says FFmpeg comes from Ubuntu in its header comment, which is out of date.

## Where things are

- Build logs, per-test results (`*.ctest.xml`), `failed-*.txt`: `~/onair/OnAir/.claude/worktrees/clang-sdk-build/report/` (uncommitted).
- Builds: the same worktree, `build-pkg-*` (the packages) and `build-gcc`, `build-linux`, `build-win`, `build-rpi5`, `build-mac-arm64`, `build-mac-x86_64`, 124 GB in total.

## Recommended next steps

1. Decide whether to push `fix/clang-sdk-all-targets` or fold it into `fix/clang-json-kv`.
2. Investigate the 7 clang-only failures, starting from the two leads above.
3. Look at the 9 non-timing failures on both compilers; `native` and `web_server` first.
4. Rewrite or relabel the 13 speed tests: only 4 have the `timing` label, so CI cannot treat the rest separately.
5. Remove the build folders when you no longer need them.
