@echo off
rem SPDX-License-Identifier: GPL-3.0-or-later
rem build_sdk.bat - make the cross SDKs from Windows, in Docker ("safe build") or in WSL. Each platform is made on its own, with its own
rem compiler, into sdk_<arch>.tar.gz in this folder. Without arguments it asks what to build.
rem
rem   --windows --linux_amd64 --linux_arm64 --macos_amd64 --macos_arm64    the SDKs to make
rem   --docker            build in the "safe" container (the only choice without WSL)
rem   --keep-sources      keep unpacked copies of the libraries' sources in kept_sources\ (default: no)
rem   --keep-build-artif  keep the build folders (default: each is deleted as soon as it is done with)
rem   --build-onair       afterwards, check out OnAir and build its installers with these SDKs, into installers\
rem
rem The SDKs themselves run on Linux x86-64: use them in WSL or a Linux machine. cache\ is never deleted.
setlocal EnableDelayedExpansion
set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
set "SDKS="
set "DOCKER=0"
set "ASKED_DOCKER=0"
set "OPTIONS="
set "KEEP_SOURCES=0"
set "BUILD_ONAIR=0"

:args
if "%~1"=="" goto args_done
set "A=%~1"
if /I "!A!"=="--windows"     ( set "SDKS=!SDKS! --windows"     & shift & goto args )
if /I "!A!"=="--linux_amd64" ( set "SDKS=!SDKS! --linux_amd64" & shift & goto args )
if /I "!A!"=="--linux_arm64" ( set "SDKS=!SDKS! --linux_arm64" & shift & goto args )
if /I "!A!"=="--macos_amd64" ( set "SDKS=!SDKS! --macos_amd64" & shift & goto args )
if /I "!A!"=="--macos_arm64" ( set "SDKS=!SDKS! --macos_arm64" & shift & goto args )
if /I "!A!"=="--docker"      ( set "DOCKER=1" & set "ASKED_DOCKER=1" & shift & goto args )
if /I "!A!"=="--keep-sources" ( set "KEEP_SOURCES=1" & shift & goto args )
if /I "!A!"=="--keep-build-artif" ( set "OPTIONS=!OPTIONS! --keep-build-artif" & shift & goto args )
if /I "!A!"=="--build-onair" ( set "BUILD_ONAIR=1" & shift & goto args )
if /I "!A!"=="--help" goto usage
if /I "!A!"=="-h" goto usage
echo unknown argument: !A!
goto usage_fail
:args_done

if not "!SDKS!"=="" goto chosen
echo Which SDKs do you want to build?
echo   1) windows      Windows x64
echo   2) linux_amd64  Linux x86-64 (Ubuntu 26.04)
echo   3) linux_arm64  Linux arm64 (Ubuntu 26.04, Raspberry Pi)
echo   4) macos_amd64  macOS Intel
echo   5) macos_arm64  macOS Apple silicon
echo   a) all of them
:ask_sdks
set "SDKS="
set "ANSWER="
set /P "ANSWER=Numbers separated by spaces, or a: "
if "!ANSWER!"=="" goto ask_sdks
for %%w in (!ANSWER!) do (
  if /I "%%w"=="a"   set "SDKS=--windows --linux_amd64 --linux_arm64 --macos_amd64 --macos_arm64"
  if "%%w"=="1" set "SDKS=!SDKS! --windows"
  if "%%w"=="2" set "SDKS=!SDKS! --linux_amd64"
  if "%%w"=="3" set "SDKS=!SDKS! --linux_arm64"
  if "%%w"=="4" set "SDKS=!SDKS! --macos_amd64"
  if "%%w"=="5" set "SDKS=!SDKS! --macos_arm64"
)
if "!SDKS!"=="" ( echo   not a choice & goto ask_sdks )
if "!ASKED_DOCKER!"=="1" goto ask_sources
echo This is not a native Linux system, so the SDK has to be made in a container or in WSL.
set "ANSWER="
set /P "ANSWER=Use the Docker "safe build"? [Y/n] "
if /I not "!ANSWER!"=="n" if /I not "!ANSWER!"=="no" set "DOCKER=1"
:ask_sources
if "!KEEP_SOURCES!"=="1" goto chosen
set "ANSWER="
set /P "ANSWER=Keep the sources of the built packages? [y/N] "
if /I "!ANSWER!"=="y" set "KEEP_SOURCES=1"
if /I "!ANSWER!"=="yes" set "KEEP_SOURCES=1"
set "ANSWER="
set /P "ANSWER=Do you want to build OnAir for these SDKs, after they are made? [y/N] "
if /I "!ANSWER!"=="y" set "BUILD_ONAIR=1"
if /I "!ANSWER!"=="yes" set "BUILD_ONAIR=1"
:chosen
if "!KEEP_SOURCES!"=="1" set "OPTIONS=!OPTIONS! --keep-sources"
if "!BUILD_ONAIR!"=="1" set "OPTIONS=!OPTIONS! --build-onair"

if "!DOCKER!"=="1" goto docker
rem ---- in WSL: the Linux script, there
where wsl >nul 2>nul || ( echo error: neither --docker nor WSL: install one of them & exit /B 1 )
for /F "usebackq delims=" %%p in (`wsl wslpath -a "%ROOT%"`) do set "WSLROOT=%%p"
wsl bash "!WSLROOT!/build_sdk.sh" !SDKS! !OPTIONS!
exit /B !ERRORLEVEL!

:docker
rem ---- the safe build: no root, no capabilities, this folder read-only except cache\ and build\
where docker >nul 2>nul || ( echo error: docker is not installed & exit /B 1 )
docker info >nul 2>nul || ( echo error: cannot reach Docker: is Docker Desktop running? & exit /B 1 )
if not exist "%ROOT%\cache" mkdir "%ROOT%\cache"
if not exist "%ROOT%\build" mkdir "%ROOT%\build"
if not exist "%ROOT%\kept_sources" mkdir "%ROOT%\kept_sources"
if not exist "%ROOT%\installers" mkdir "%ROOT%\installers"
docker build --platform linux/amd64 -t onair-sdk-builder "%ROOT%" || exit /B 1
docker run --rm --init --platform linux/amd64 --cap-drop=ALL --security-opt=no-new-privileges -v "%ROOT%":/work:ro -v "%ROOT%\cache":/work/cache -v "%ROOT%\build":/work/build -v "%ROOT%\kept_sources":/work/kept_sources -v "%ROOT%\installers":/work/installers -it onair-sdk-builder bash /work/build_sdk.sh --in-docker !SDKS! !OPTIONS! || exit /B 1
rem ---- the tarballs into this folder
move /Y "%ROOT%\build\out\sdk_*.tar.gz" "%ROOT%\" >nul
pushd "%ROOT%"
for %%f in (sdk_*.tar.gz) do echo %%f
popd
echo !OPTIONS! | findstr /C:"--keep-build-artif" >nul || rmdir /S /Q "%ROOT%\build"
dir /B "%ROOT%\kept_sources" 2>nul | findstr "^" >nul || rmdir "%ROOT%\kept_sources"
dir /B "%ROOT%\installers" 2>nul | findstr "^" >nul || rmdir "%ROOT%\installers"
exit /B 0

:usage
for /F "tokens=1,* delims= " %%a in ('findstr /B /C:"rem " "%~f0"') do echo %%b
exit /B 0
:usage_fail
exit /B 2
