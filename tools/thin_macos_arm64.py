#!/usr/bin/env python3
"""Thin a Godot macOS export zip to its arm64 slice.

    python3 tools/thin_macos_arm64.py ../build/RomanWar-macOS.zip ../build/RomanWar-macOS-arm64.zip

Reads the universal RomanWar-macOS.zip, extracts the arm64 slice of the
Mach-O fat executable inside the .app (exactly what `lipo -thin arm64` does),
verifies the slice still carries its LC_CODE_SIGNATURE load command (the
ad-hoc signature Apple Silicon requires), and writes a new zip that preserves
every other entry byte-for-byte, including unix modes.
"""
import struct, sys, zipfile

FAT_MAGIC = 0xCAFEBABE
CPU_TYPE_ARM64 = 0x0100000C
MH_MAGIC_64 = 0xFEEDFACF
LC_CODE_SIGNATURE = 0x1D


def arm64_slice(fat: bytes) -> bytes:
    magic, nfat = struct.unpack(">II", fat[:8])
    if magic != FAT_MAGIC:
        raise SystemExit("not a fat binary (magic %#x)" % magic)
    for i in range(nfat):
        cputype, cpusub, off, size, align = struct.unpack(">iiIII", fat[8 + i * 20: 28 + i * 20])
        if cputype == CPU_TYPE_ARM64:
            return fat[off: off + size]
    raise SystemExit("no arm64 slice among %d architectures" % nfat)


def has_code_signature(thin: bytes) -> bool:
    magic, cputype, cpusub, filetype, ncmds, sizeofcmds, flags, reserved = struct.unpack("<IiiIIIII", thin[:32])
    if magic != MH_MAGIC_64:
        raise SystemExit("thin slice is not a 64-bit Mach-O (magic %#x)" % magic)
    if cputype != CPU_TYPE_ARM64:
        raise SystemExit("thin slice cputype %#x is not arm64" % cputype)
    pos = 32
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack("<II", thin[pos:pos + 8])
        if cmd == LC_CODE_SIGNATURE:
            return True
        pos += cmdsize
    return False


def main(src: str, dst: str) -> None:
    with zipfile.ZipFile(src) as zin:
        execs = [n for n in zin.namelist() if "/Contents/MacOS/" in n and not n.endswith("/")]
        if len(execs) != 1:
            raise SystemExit("expected one executable under Contents/MacOS, found %r" % execs)
        exe = execs[0]
        with zipfile.ZipFile(dst, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zout:
            for info in zin.infolist():
                data = zin.read(info)
                if info.filename == exe:
                    thin = arm64_slice(data)
                    if not has_code_signature(thin):
                        raise SystemExit("arm64 slice lost LC_CODE_SIGNATURE; refusing to write")
                    print("executable %s: fat %d bytes -> arm64 %d bytes, signature present" % (exe, len(data), len(thin)))
                    data = thin
                out = zipfile.ZipInfo(info.filename, date_time=info.date_time)
                out.external_attr = info.external_attr   # keep unix mode bits (0755 on the executable)
                out.create_system = info.create_system
                out.compress_type = zipfile.ZIP_STORED if info.filename.endswith("/") else zipfile.ZIP_DEFLATED
                zout.writestr(out, data)
    print("wrote", dst)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
