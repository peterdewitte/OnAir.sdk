# Why clang

Full figures and test results: [reports/CLANG-BUILD-REPORT.md](reports/CLANG-BUILD-REPORT.md). Packaging plan: [reports/SDK-PACKAGING.md](reports/SDK-PACKAGING.md).

* **Reproducible across architectures.** One compiler and one pinned set of libraries for all 5 targets, built on one machine, where a native build has a different compiler and library versions on each platform. Building OnAir's `onair-server` twice gave a bit-for-bit identical program on Linux. Windows differed in 6 bytes of 75.8 MB and macOS arm64 in 484 of 58.1 MB, so those are close but not there yet.
* **Speed.** A clean Linux build of OnAir and all tests took about 900 s with clang against about 1450 s with GCC (`-j16`, no ccache): 38% less time, 42% less CPU, half the peak memory. The test suite's summed run time was about 8% lower. These runs compare toolchains, including the linker and libraries, not just the compilers.
* **Code safety checks.** Clang rejected code that GCC accepted, such as a narrowing conversion and missing includes. It brings the sanitizers and `clang-tidy`, one of the C/C++ tools Codacy can run. In OnAir's current Codacy setup `clang-tidy` is off (Flawfinder, Cppcheck, Opengrep and Lizard run), so a clean clang build is a separate check for now, not the Codacy gate.

**Not settled yet:** in those runs, 7 OnAir tests failed on clang only, also when run alone, with no cause established (4 failed on GCC only). See the report before releasing from this.
