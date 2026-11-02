#!/usr/bin/env python3
"""Original battery-backed NROM test program; no commercial ROM contents."""
from pathlib import Path
import sys


def image():
    code, labels, patches = bytearray(), {}, []

    def emit(*values):
        code.extend(values)

    def label(name):
        labels[name] = 0x8000 + len(code)

    def branch(op, name):
        emit(op, 0)
        patches.append((len(code) - 1, name, True))

    def jump(name):
        emit(0x4C, 0, 0)
        patches.append((len(code) - 2, name, False))

    emit(0x78, 0xD8, 0xA2, 0xFF, 0x9A)  # SEI CLD LDX #$ff TXS
    emit(0xA9, 0, 0x8D, 0, 0x20, 0x8D, 1, 0x20, 0x8D, 0x10, 0x40)
    emit(0xAD, 0, 0x60, 0xC9, 0xB7)
    branch(0xF0, "retained")
    emit(0xA9, 0, 0xA2, 0)
    label("clear")
    emit(0x9D, 0, 0x60, 0xE8)
    branch(0xD0, "clear")
    emit(0xA9, 0xB7, 0x8D, 0, 0x60)
    label("retained")
    emit(0xEE, 1, 0x60)  # Boot count survives native battery save/restore.
    label("frame")
    emit(0x2C, 2, 0x20)
    branch(0x10, "frame")  # Wait for vblank; rendering need not be enabled.
    emit(0xEE, 0x10, 0x60)
    emit(0xA9, 1, 0x8D, 0x16, 0x40, 0xA9, 0, 0x8D, 0x16, 0x40, 0xA2, 0)
    label("buttons")
    emit(0xAD, 0x16, 0x40, 0x29, 1, 0x9D, 0x20, 0x60)
    branch(0xF0, "next")
    emit(0xFE, 0x30, 0x60)  # Per-button pressed-frame count.
    label("next")
    emit(0xE8, 0xE0, 8)
    branch(0xD0, "buttons")
    jump("frame")
    label("interrupt")
    emit(0x40)
    for offset, name, relative in patches:
        target = labels[name]
        if relative:
            delta = target - (0x8000 + offset + 1)
            assert -128 <= delta <= 127
            code[offset] = delta & 255
        else:
            code[offset:offset + 2] = target.to_bytes(2, "little")
    prg = code + bytes(16384 - len(code))
    prg[-6:] = (labels["interrupt"].to_bytes(2, "little") +
                (0x8000).to_bytes(2, "little") +
                labels["interrupt"].to_bytes(2, "little"))
    return b"NES\x1a" + bytes([1, 1, 2, 0]) + bytes(8) + prg + bytes(8192)


if __name__ == "__main__":
    Path(sys.argv[1]).write_bytes(image())
