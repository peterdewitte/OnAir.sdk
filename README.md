# OnAir cross SDK

Do you have trouble compiling OnAir or its plugins? Do you want to make your own plugins? Do you want a stable environment to work in?

This project provides all of that, plus:

* the same compiler for all platforms
* the same compiled software dependencies for all platforms

So all platforms are built the same way and behave as alike as possible.

There is one self-contained tarball per platform, used on Linux x86-64: `windows`, `linux_amd64`, `linux_arm64`, `macos_amd64`, `macos_arm64`.

## 1. Make an SDK

The script guides you through the available choices and gives the option to start building. It is made on Ubuntu 26.04, but for stability reasons, the option to build it in Docker is provided.

```bash
./build_sdk.sh                          # asks what to build
```

The SDKs are made in `build/out`. When the script ends, the finished `sdk_<platform>.tar.gz` files are moved to this folder.

The script can also build OnAir and its installers for these SDKs right away: it asks, or use `--build-onair`. The installers end up in `installers/`.

For Windows users: please consider using Linux in WSL2 ([how to install Ubuntu 26.04 in WSL2](docs/WSL2.md)).

On Windows, you can also use the untested `build_sdk.bat`.

With Docker you need only Docker. Without it, on Ubuntu 26.04, the script checks the host tools first and tells you which packages to install with `apt`.

## 2. Install an SDK

On Linux x86-64 (Ubuntu 26.04, WSL or a container):

```bash
sudo apt install cmake ninja-build pkgconf git python3

tar xzf sdk_windows.tar.gz
. ./environment_windows.sh
```

The `environment_windows.sh` script configures the session for a Windows compilation. Do not forget the "." at the start of the command. It actually matters.

The script has now configured the shell for the SDK.

## 3. Build OnAir and make the installers

Work in the shell from step 2. For now, the patches for this SDK are on a temporary branch: [peterdewitte/OnAir, `clang_and_packaging`](https://github.com/peterdewitte/OnAir/tree/clang_and_packaging).

```bash
git clone -b clang_and_packaging https://github.com/peterdewitte/OnAir.git OnAir
cmake -S OnAir -B build -G Ninja -DCMAKE_BUILD_TYPE=Release
cmake --build build                    # OnAir and its tests
cmake --build build --target package   # the installer, in build/packages
```

This builds up to the installer. This is the same process for all platforms. It does not matter if you build for macOS or Windows. The process is the same and you do not need to worry about the details of compilation and packaging software.

| SDK | Installer |
|---|---|
| `windows` | `OnAir-<v>-windows-x64-setup.exe` and `.zip` |
| `linux_amd64` | `onair_<v>_amd64.deb` |
| `linux_arm64` | `onair_<v>_arm64.deb` (add `-DRPI_CPU=generic` to the first command for any 64-bit ARM) |
| `macos_amd64` | `OnAir-<v>-macos-x86_64.dmg` |
| `macos_arm64` | `OnAir-<v>-macos-arm64.dmg` |

## 4. More

See [docs/](docs/): [USAGE.md](docs/USAGE.md) (all options, using each SDK, what you may share), [WSL2.md](docs/WSL2.md), [WHY-CLANG.md](docs/WHY-CLANG.md), [DETAILS.md](docs/DETAILS.md) and [reports/](docs/reports/).
