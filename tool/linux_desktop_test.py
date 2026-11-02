#!/usr/bin/env python3
"""Use an explicitly authorized Broomm desktop connection in memory only.

Run with the existing Broomm PID and a literal test command. Values are never
printed or stored; command output is redacted before being returned to the caller.
"""
import os
from pathlib import Path
import subprocess
import sys

pid = int(sys.argv[1])
process = Path(f"/proc/{pid}")
executable = (process / "exe").resolve(strict=True)
if process.stat().st_uid != os.getuid() or executable.name != "broomm":
    raise RuntimeError("The authorized Broomm desktop process changed.")
allowed = {"DISPLAY", "WAYLAND_DISPLAY", "XDG_RUNTIME_DIR", "XAUTHORITY",
           "DBUS_SESSION_BUS_ADDRESS", "XDG_SESSION_TYPE"}
connection = {}
for item in (process / "environ").read_bytes().split(b"\0"):
    key, _, value = item.partition(b"=")
    name = key.decode(errors="replace")
    if name in allowed:
        connection[name] = value.decode()
if not ({"DISPLAY", "WAYLAND_DISPLAY"} & connection.keys()):
    raise RuntimeError("Broomm has no available desktop connection.")
child = subprocess.Popen(sys.argv[2:], env={**os.environ, **connection},
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
try:
    for line in iter(child.stdout.readline, b""):
        text = line.decode(errors="replace")
        for value in sorted(connection.values(), key=len, reverse=True):
            if value:
                text = text.replace(value, "[desktop connection]")
        print(text, end="", flush=True)
finally:
    connection.clear()
sys.exit(child.wait())
