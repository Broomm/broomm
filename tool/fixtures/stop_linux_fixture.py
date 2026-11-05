"""Stop only a known disposable emulator, using a pinned kernel identity."""
from pathlib import Path
import os
import select
import signal
import sys

pid = int(sys.argv[1])
root = Path(sys.argv[2]).resolve()
expected = Path(sys.argv[3]).resolve()
assert any(part in str(root) for part in ['/.tool-cache/research/linux-standalone/', '/.tool-cache/arm64-standalone/'])
try:
    handle = os.pidfd_open(pid)
except ProcessLookupError:
    sys.exit(0)
try:
    allowed_cwd = root / 'home' if expected.name in ['azahar', 'eden'] else root
    if Path(f'/proc/{pid}/cwd').resolve() != allowed_cwd:
        raise RuntimeError('Fixture working directory changed; preserved process')
    # A nested development mount namespace can report another path for the
    # same file. Compare its kernel identity, never accept a name-only match.
    actual = os.stat(f'/proc/{pid}/exe')
    wanted = expected.stat()
    if (actual.st_dev, actual.st_ino) != (wanted.st_dev, wanted.st_ino):
        raise RuntimeError('Fixture executable changed; preserved process')
    signal.pidfd_send_signal(handle, signal.SIGTERM)
    if not select.select([handle], [], [], 5)[0]:
        signal.pidfd_send_signal(handle, signal.SIGKILL)
        if not select.select([handle], [], [], 5)[0]:
            raise RuntimeError('Owned fixture did not exit; retained its data')
finally:
    os.close(handle)
