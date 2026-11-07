# SPDX-License-Identifier: GPL-3.0-or-later
"""macos/macho.py - read Mach-O load commands on Linux (no Apple tools needed).

    python3 -I macho.py check SYSROOT MACOS_MIN     check the sysroot's libraries (macos/fetch_sysroot.sh runs it)
    python3 -I macho.py deps FILE                   print the dylibs FILE loads, one per line
    python3 -I macho.py collect FILE DEST SYSROOT [EXTRA ...]   copy the dylibs FILE needs (collect_dylibs.sh)

check: every Mach-O file under SYSROOT/usr/local/lib must be built for a macOS no newer than MACOS_MIN
(LC_BUILD_VERSION / LC_VERSION_MIN_MACOSX), and every dylib it loads must be found: @rpath/<name> in usr/local/lib
(conda-forge's libraries all use @rpath install names), /usr/lib/... and /System/Library/... as a .tbd stub in the
Apple SDK, @loader_path/... next to the file. Prints what is wrong and exits 1.
"""
import fnmatch
import os
import shutil
import struct
import sys

LC_REQ_DYLD = 0x80000000
LOADS = {0xC, 0x18 | LC_REQ_DYLD, 0x1F | LC_REQ_DYLD, 0x20, 0x23 | LC_REQ_DYLD}   # load, weak, reexport, lazy, upward
WEAK = 0x18 | LC_REQ_DYLD
LC_ID_DYLIB, LC_RPATH, LC_BUILD_VERSION, LC_VERSION_MIN_MACOSX = 0xD, 0x1C | LC_REQ_DYLD, 0x32, 0x24


def _ver(v):
    return f"{v >> 16}.{(v >> 8) & 0xFF}" + (f".{v & 0xFF}" if v & 0xFF else "")


def parse(path):
    """-> list of slices: dict(cpu, id, loads[(name, weak)], rpaths, minos) or None when not a Mach-O file"""
    with open(path, "rb") as f:
        head = f.read(8)
        if len(head) < 8:
            return None
        magic = struct.unpack(">I", head[:4])[0]
        offsets = []
        if magic in (0xCAFEBABE, 0xCAFEBABF):
            n = struct.unpack(">I", head[4:8])[0]
            if n > 30:          # a Java class file has the same magic
                return None
            for i in range(n):
                if magic == 0xCAFEBABE:
                    f.seek(8 + 20 * i)
                    _cpu, _sub, off, _size, _align = struct.unpack(">IIIII", f.read(20))
                else:
                    f.seek(8 + 32 * i)
                    _cpu, _sub, off, _size, _align, _r = struct.unpack(">IIQQII", f.read(32))
                offsets.append(off)
        elif struct.unpack("<I", head[:4])[0] in (0xFEEDFACF, 0xFEEDFACE):
            offsets.append(0)
        else:
            return None
        out = []
        for base in offsets:
            f.seek(base)
            m = struct.unpack("<I", f.read(4))[0]
            if m not in (0xFEEDFACF, 0xFEEDFACE):
                continue
            is64 = m == 0xFEEDFACF
            cpu, _sub, ftype, ncmds, _size, _flags = struct.unpack("<iiIIII", f.read(24))
            pos = base + (32 if is64 else 28)
            sl = {"cpu": cpu, "type": ftype, "id": None, "loads": [], "rpaths": [], "minos": None}
            for _ in range(ncmds):
                f.seek(pos)
                cmd, size = struct.unpack("<II", f.read(8))
                body = f.read(size - 8)
                if cmd in LOADS or cmd == LC_ID_DYLIB or cmd == LC_RPATH:
                    off = struct.unpack("<I", body[:4])[0] - 8
                    s = body[off:].split(b"\0", 1)[0].decode()
                    if cmd == LC_ID_DYLIB:
                        sl["id"] = s
                    elif cmd == LC_RPATH:
                        sl["rpaths"].append(s)
                    else:
                        sl["loads"].append((s, cmd == WEAK))
                elif cmd == LC_BUILD_VERSION:
                    platform, minos = struct.unpack("<II", body[:8])
                    if platform == 1:     # macOS
                        sl["minos"] = _ver(minos)
                elif cmd == LC_VERSION_MIN_MACOSX:
                    sl["minos"] = _ver(struct.unpack("<I", body[:4])[0])
                pos += size
            out.append(sl)
        return out


def vtuple(v):
    return tuple(int(x) for x in v.split("."))


def sdk_has(sysroot, name):
    """a /usr/lib or /System/Library path in the Apple SDK (as a .tbd stub, or the file itself)"""
    p = os.path.join(sysroot, name.lstrip("/"))
    base, ext = os.path.splitext(p)
    cands = [p, base + ".tbd", p + ".tbd"]
    if ".framework/" in name:   # /System/Library/Frameworks/X.framework/Versions/A/X -> X.framework/X.tbd too
        fw = name[:name.index(".framework/") + len(".framework")]
        leaf = os.path.basename(fw)[:-len(".framework")]
        cands.append(os.path.join(sysroot, fw.lstrip("/"), leaf + ".tbd"))
    return any(os.path.lexists(c) for c in cands)


def check(sysroot, macos_min):
    lib = os.path.join(sysroot, "usr", "local", "lib")
    have = set(os.listdir(lib))
    bad, n = [], 0
    for root, _dirs, files in os.walk(lib):
        for fn in files:
            p = os.path.join(root, fn)
            if os.path.islink(p) or not (fn.endswith((".dylib", ".so")) or fnmatch.fnmatch(fn, "*.dylib.*")):
                continue
            slices = parse(p)
            if not slices:
                continue
            n += 1
            rel = os.path.relpath(p, sysroot)
            for sl in slices:
                if sl["minos"] and vtuple(sl["minos"]) > vtuple(macos_min):
                    bad.append(f"{rel}: built for macOS {sl['minos']}, newer than the minimum {macos_min}")
                for name, weak in sl["loads"]:
                    if name.startswith("@rpath/"):
                        ok = name[7:] in have or os.path.lexists(os.path.join(root, name[7:]))
                    elif name.startswith("@loader_path/"):
                        ok = os.path.lexists(os.path.join(root, name[13:]))
                    elif name.startswith(("/usr/lib/", "/System/Library/")):
                        ok = sdk_has(sysroot, name)
                    else:
                        ok = False
                    if not ok and not weak:
                        bad.append(f"{rel}: loads {name}, which is not in the sysroot")
    for b in bad:
        print("  " + b)
    print(f"==> {n} Mach-O libraries checked: {'all fine' if not bad else str(len(bad)) + ' problems'}")
    if bad:
        sys.exit(1)


def collect(exe, dest, sysroot, extra):
    """copy every @rpath dylib exe needs (recursively) from sysroot/usr/local/lib to dest"""
    lib = os.path.join(sysroot, "usr", "local", "lib")
    os.makedirs(dest, exist_ok=True)
    todo, done = [exe], set()
    for pat in extra:
        todo += [os.path.join(lib, f) for f in sorted(os.listdir(lib)) if fnmatch.fnmatch(f, pat)]
    copied = 0
    while todo:
        p = todo.pop()
        for sl in parse(p) or []:
            for name, _weak in sl["loads"]:
                if not name.startswith("@rpath/"):
                    continue
                leaf = name[7:]
                if leaf in done:
                    continue
                done.add(leaf)
                src = os.path.join(lib, leaf)
                if not os.path.exists(src):
                    print(f"warning: {os.path.basename(p)} needs {leaf}, which is not in {lib}", file=sys.stderr)
                    continue
                shutil.copy2(os.path.realpath(src), os.path.join(dest, leaf))
                copied += 1
                todo.append(src)
        if p != exe and os.path.basename(p) not in done:
            done.add(os.path.basename(p))
            shutil.copy2(os.path.realpath(p), os.path.join(dest, os.path.basename(p)))
            copied += 1
    print(f"{copied} dylibs copied to {dest}")


def main():
    a = sys.argv[1:]
    if a[:1] == ["check"] and len(a) == 3:
        check(a[1], a[2])
    elif a[:1] == ["deps"] and len(a) == 2:
        for sl in parse(a[1]) or []:
            for name, weak in sl["loads"]:
                print(name + (" (weak)" if weak else ""))
    elif a[:1] == ["collect"] and len(a) >= 4:
        collect(a[1], a[2], a[3], a[4:])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
