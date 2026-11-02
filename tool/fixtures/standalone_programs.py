"""Original tiny guest loops for opt-in native emulator lifecycle tests.

No commercial ROM code, graphics SDK, save data or console identity is included.
These test CPU launch/pause boundaries; they are not gameplay compatibility tests.
"""
from pathlib import Path
import struct
import sys

root = Path(sys.argv[1])
root.mkdir(parents=True, exist_ok=True)
# GameCube DOL: one PowerPC text segment, a branch to its own address.
b = bytearray(0x120)
for offset, value in [(0, 0x100), (0x48, 0x80004000), (0x90, 32),
                      (0xE0, 0x80004000), (0x100, 0x48000000)]:
    struct.pack_into('>I', b, offset, value)
(root / 'gc.dol').write_bytes(b)
# The unexecuted HID4 instruction identifies a Wii DOL to Dolphin's loader.
struct.pack_into('>I', b, 0x104, 0x7C13FBA6)
(root / 'wii.dol').write_bytes(b)
# 3DSX: three empty relocation tables, one ARM branch-to-self instruction.
b = struct.pack('<4sHHIIIIII', b'3DSX', 32, 8, 0, 0, 4, 0, 0, 0)
b += bytes(24) + struct.pack('<I', 0xEAFFFFFE)
(root / '3ds.3dsx').write_bytes(b)
# PS-X EXE: original MIPS self-branch and its delay-slot nop.
b = bytearray(0x1000)
b[:8] = b'PS-X EXE'
struct.pack_into('<IIII', b, 0x10, 0x80010000, 0, 0x80010000, 0x800)
struct.pack_into('<II', b, 0x800, 0x1000FFFF, 0)
(root / 'psx.exe').write_bytes(b)
# PS2 ELF32, MIPS little-endian, one loadable segment with the same loop.
b = bytearray(0x1008)
b[:16] = b'\x7fELF\x01\x01\x01' + bytes(9)
struct.pack_into('<HHIIIIIHHHHHH', b, 16, 2, 8, 1, 0x100000, 52, 0,
                 0x20924001, 52, 32, 1, 0, 0, 0)
struct.pack_into('<IIIIIIII', b, 52, 1, 0x1000, 0x100000, 0x100000, 8, 8, 7, 0x1000)
struct.pack_into('<II', b, 0x1000, 0x1000FFFF, 0)
(root / 'ps2.elf').write_bytes(b)
# Nintendo DS direct-boot header and separate original ARM9/ARM7 loops.
b = bytearray(0x1000)
b[:12] = b'BROOMM TEST\0'
b[12:16] = b'BRTS'
struct.pack_into('<IIII', b, 0x20, 0x200, 0x02000000, 0x02000000, 4)
struct.pack_into('<IIII', b, 0x30, 0x204, 0x02380000, 0x02380000, 4)
struct.pack_into('<II', b, 0x80, len(b), 0x200)
struct.pack_into('<II', b, 0x200, 0xEAFFFFFE, 0xEAFFFFFE)
crc = 0xFFFF
for byte in b[:0x15E]:
    crc ^= byte
    for _ in range(8):
        crc = (crc >> 1) ^ (0xA001 if crc & 1 else 0)
struct.pack_into('<H', b, 0x15E, crc)
(root / 'ds.nds').write_bytes(b)
