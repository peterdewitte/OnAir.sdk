# Install Ubuntu 26.04 in WSL2 on Windows

WSL2 runs a real Linux on Windows. The SDKs run on Linux x86-64, so this is the recommended way to make and use them on Windows. These steps have not been tried with this SDK yet.

You need Windows 10 (version 2004 or newer) or Windows 11, on an x86-64 PC, with virtualization enabled in the BIOS. Plan for at least 20 GB of free disk space, and more if you make several SDKs.

## 1. Install WSL

Open PowerShell as administrator:

```powershell
wsl --install --no-distribution
```

Restart Windows, then in PowerShell again:

```powershell
wsl --update
wsl --set-default-version 2
```

## 2. Install Ubuntu 26.04

See which names are available, and use the exact name from the list:

```powershell
wsl --list --online
wsl --install -d Ubuntu-26.04
```

Windows asks for a Linux user name and password the first time. If the install hangs at 0%, try `wsl --install --web-download -d Ubuntu-26.04`.

**If Ubuntu 26.04 is not in the list**, download the WSL image from [Ubuntu's WSL documentation](https://documentation.ubuntu.com/wsl/latest/howto/install-ubuntu-wsl2/) and import it:

```powershell
wsl --import Ubuntu-26.04 C:\WSL\Ubuntu-26.04 C:\path\to\the-downloaded-image.wsl --version 2
wsl -d Ubuntu-26.04
```

An imported Ubuntu may log you in as root. Create a normal user and work as that user: the SDK's scripts should not be run as root.

## 3. Check it

In PowerShell:

```powershell
wsl --list --verbose
```

The `VERSION` column must say 2. In Ubuntu:

```bash
lsb_release -ds     # Ubuntu 26.04
uname -m            # x86_64
sudo apt update && sudo apt upgrade
```

## 4. Work inside Linux

Keep this repository in your Linux home folder, not under `/mnt/c`. Building on the Windows disk is much slower, and file permissions and line endings can break the scripts.

```bash
cd ~
git clone git@github.com:peterdewitte/OnAir.sdk.git
cd OnAir.sdk
./build_sdk.sh
```

The script tells you which packages are missing. From here, follow the [README](../README.md) as on any Linux.

## Optional

* **Limit memory or CPUs:** a large build can fill the PC. Create `C:\Users\<you>\.wslconfig`, then run `wsl --shutdown`:

  ```ini
  [wsl2]
  memory=16GB
  processors=8
  ```

* **Docker in WSL:** the `--docker` option needs Docker to be available inside Ubuntu. Docker Desktop provides this through its WSL integration setting, or you can install Docker in Ubuntu itself.

## Sources

* [Microsoft: install WSL](https://learn.microsoft.com/windows/wsl/install)
* [Ubuntu: install Ubuntu on WSL2](https://documentation.ubuntu.com/wsl/latest/howto/install-ubuntu-wsl2/)
