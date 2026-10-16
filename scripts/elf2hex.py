#!/usr/bin/env python3
"""Convert an RV32 ELF into a $readmemh image and look up symbols.

    elf2hex.py prog.elf prog.hex                 # write hex image
    elf2hex.py prog.elf --sym tohost             # print symbol address (hex)
    elf2hex.py prog.elf prog.hex --sym tohost --sym begin_signature

No external toolchain is needed. Word 0 of the image corresponds to --base.
"""
import argparse
import struct
import sys


def read_elf(path):
    with open(path, "rb") as f:
        data = f.read()
    if data[:4] != b"\x7fELF" or data[4] != 1 or data[5] != 1:
        sys.exit(f"{path}: not a little-endian ELF32 file")
    return data


def load_segments(data):
    (e_phoff,) = struct.unpack_from("<I", data, 0x1C)
    e_phentsize, e_phnum = struct.unpack_from("<HH", data, 0x2A)
    segs = []
    for i in range(e_phnum):
        p_type, p_offset, _vaddr, p_paddr, p_filesz, p_memsz, _flags, _align = \
            struct.unpack_from("<8I", data, e_phoff + i * e_phentsize)
        if p_type == 1 and p_memsz:  # PT_LOAD
            body = data[p_offset:p_offset + p_filesz] + b"\0" * (p_memsz - p_filesz)
            segs.append((p_paddr, body))
    return segs


def symbols(data):
    (e_shoff,) = struct.unpack_from("<I", data, 0x20)
    e_shentsize, e_shnum = struct.unpack_from("<HH", data, 0x2E)
    shdrs = [struct.unpack_from("<10I", data, e_shoff + i * e_shentsize) for i in range(e_shnum)]
    syms = {}
    for sh in shdrs:
        if sh[1] != 2:  # SHT_SYMTAB
            continue
        strtab = shdrs[sh[6]]
        str_off = strtab[4]
        off, size, entsize = sh[4], sh[5], sh[9]
        for j in range(size // entsize):
            st_name, st_value = struct.unpack_from("<II", data, off + j * entsize)
            end = data.index(b"\0", str_off + st_name)
            name = data[str_off + st_name:end].decode()
            if name:
                syms[name] = st_value
    return syms


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("elf")
    ap.add_argument("hex", nargs="?")
    ap.add_argument("--base", type=lambda s: int(s, 0), default=0x80000000)
    ap.add_argument("--sym", action="append", default=[])
    args = ap.parse_args()

    data = read_elf(args.elf)

    if args.hex:
        segs = [(a, b) for a, b in load_segments(data) if a >= args.base]
        top = max(a + len(b) for a, b in segs)
        image = bytearray(top - args.base)
        for addr, body in segs:
            image[addr - args.base:addr - args.base + len(body)] = body
        image += b"\0" * (-len(image) % 4)
        with open(args.hex, "w") as f:
            for i in range(0, len(image), 4):
                f.write("%08x\n" % struct.unpack_from("<I", image, i))

    if args.sym:
        syms = symbols(data)
        for name in args.sym:
            if name not in syms:
                sys.exit(f"symbol '{name}' not found")
            print("%08x" % syms[name])


if __name__ == "__main__":
    main()
