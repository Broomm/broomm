"""Stop only a known disposable emulator, using a pinned kernel identity."""
from pathlib import Path
import os
import select
import signal
import sys

pid = int(sys.argv[1])
root = Path(sys.argv[2]).resolve()
expected = Path(sys.argv[3]).resolve()
assert '/.tool-cache/research/linux-standalone/' in str(root)
try:
    handle = os.pidfd_open(pid)
except ProcessLookupError:
    sys.exit(0)
try:
    allowed_cwd = root / 'home' if expected.name == 'azahar' else root
    if Path(f'/proc/{pid}/cwd').resolve() != allowed_cwd:
        raise RuntimeError('Fixture working directory changed; preserved process')
    if Path(f'/proc/{pid}/exe').resolve() != expected:
        raise RuntimeError('Fixture executable changed; preserved process')
    signal.pidfd_send_signal(handle, signal.SIGTERM)
    if not select.select([handle], [], [], 5)[0]:
        signal.pidfd_send_signal(handle, signal.SIGKILL)
        if not select.select([handle], [], [], 5)[0]:
            raise RuntimeError('Owned fixture did not exit; retained its data')
finally:
    os.close(handle)
