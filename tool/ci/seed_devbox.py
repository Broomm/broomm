#!/usr/bin/env python3
"""Seed the pinned launcher's CI cache through GitHub's release-asset API.

The existing action still installs Nix, selects Devbox and checks its version.
This does not install an SDK, change a tool version or execute downloaded code.
"""
import fcntl
import hashlib
import io
import json
import os
from pathlib import Path
import re
import secrets
import stat
import tarfile
import urllib.error
import urllib.parse
import urllib.request

VERSION = "0.18.4"
PLATFORMS = {("Linux", "X64"): "linux_amd64", ("Linux", "ARM64"): "linux_arm64",
             ("macOS", "X64"): "darwin_amd64", ("macOS", "ARM64"): "darwin_arm64"}


def validate_record(record):
    if (type(record["asset_id"]) is not int or record["asset_id"] < 1 or
            type(record["archive_bytes"]) is not int or not 1 <= record["archive_bytes"] <= 16 * 1024 * 1024 or
            type(record["binary_bytes"]) is not int or not 1 <= record["binary_bytes"] <= 32 * 1024 * 1024 or
            not all(re.fullmatch("[a-f0-9]{64}", record[k]) for k in ["archive_sha256", "binary_sha256"])):
        raise RuntimeError("Invalid pinned Devbox artifact record")


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def download(record, token, open_request=None):
    """Only the initial API request receives the ephemeral GitHub credential."""
    validate_record(record)
    open_request = open_request or urllib.request.build_opener(NoRedirect).open
    request = urllib.request.Request(
        "https://api.github.com/repos/jetify-com/devbox/releases/assets/" + str(record["asset_id"]),
        headers={"Accept": "application/octet-stream", "Authorization": "Bearer " + token,
                 "User-Agent": "Broomm-pinned-Devbox"})
    try:
        try:
            response = open_request(request, timeout=30)
        except urllib.error.HTTPError as error:
            if error.code != 302:
                raise RuntimeError("Devbox asset API returned HTTP " + str(error.code)) from None
            location = error.headers.get("Location", "")
            parsed = urllib.parse.urlparse(location)
            if (parsed.scheme != "https" or parsed.username or parsed.password or
                    not (parsed.hostname or "").endswith((".githubusercontent.com", ".blob.core.windows.net"))):
                raise RuntimeError("Devbox asset API returned an unexpected download host")
            # The signed storage URL receives no Authorization header and is
            # never logged. Refuse another redirect rather than forwarding it.
            response = open_request(urllib.request.Request(location, headers={
                "User-Agent": "Broomm-pinned-Devbox"}), timeout=30)
        with response:
            if response.headers.get_content_type() == "application/json":
                raise RuntimeError("Devbox asset API returned metadata instead of the pinned archive")
            return response.read(record["archive_bytes"] + 1)
    except (urllib.error.URLError, TimeoutError, OSError):
        raise RuntimeError("Network failure downloading the pinned Devbox archive") from None


def binary_from_archive(data, record):
    validate_record(record)
    if (len(data) != record["archive_bytes"] or
            hashlib.sha256(data).hexdigest() != record["archive_sha256"]):
        raise RuntimeError("Pinned Devbox archive size/checksum mismatch")
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
        entries = archive.getmembers()
        if (len(entries) != 1 or entries[0].name != "devbox" or
                not entries[0].isfile() or entries[0].size != record["binary_bytes"]):
            raise RuntimeError("Unexpected pinned Devbox archive inventory")
        binary = archive.extractfile(entries[0]).read(record["binary_bytes"] + 1)
    if (len(binary) != record["binary_bytes"] or
            hashlib.sha256(binary).hexdigest() != record["binary_sha256"]):
        raise RuntimeError("Pinned Devbox binary size/checksum mismatch")
    return binary


def owned_directory(path):
    path.mkdir(mode=0o700, exist_ok=True)
    info = path.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o022:
        raise RuntimeError("Devbox cache directory is linked or has another owner")


def verify_binary(path, record):
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(descriptor, "rb") as stream:
        before = os.fstat(stream.fileno())
        if (not stat.S_ISREG(before.st_mode) or before.st_uid != os.getuid() or
                before.st_nlink != 1 or before.st_size != record["binary_bytes"] or
                before.st_mode & 0o022 or not before.st_mode & stat.S_IXUSR):
            raise RuntimeError("Existing Devbox cache has unexpected ownership, links or permissions")
        value = stream.read(record["binary_bytes"] + 1)
        after = os.fstat(stream.fileno())
        identity = lambda s: (s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_ctime_ns, s.st_nlink, s.st_uid, s.st_mode)
        if (identity(before) != identity(after) or
                identity(after) != identity(path.lstat()) or len(value) != record["binary_bytes"] or
                hashlib.sha256(value).hexdigest() != record["binary_sha256"]):
            raise RuntimeError("Existing Devbox cache differs from the pinned binary; it was kept")


def seed(runner_home, platform, record, fetch):
    validate_record(record)
    if platform not in PLATFORMS.values():
        raise RuntimeError("Unsupported CI Devbox host")
    info = runner_home.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
        raise RuntimeError("CI home is linked or has another owner")
    current = runner_home
    for component in [".cache", "devbox", "bin", VERSION + "_" + platform]:
        current = current / component
        owned_directory(current)
    lock = os.open(current / ".broomm-seed.lock", os.O_WRONLY | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    try:
        lock_info = os.fstat(lock)
        if not stat.S_ISREG(lock_info.st_mode) or lock_info.st_uid != os.getuid() or lock_info.st_nlink != 1:
            raise RuntimeError("Invalid CI Devbox cache lock")
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError("Another runner process is preparing this Devbox cache") from None
        target = current / "devbox"
        if os.path.lexists(target):
            verify_binary(target, record)
            return record["binary_sha256"]
        binary = binary_from_archive(fetch(), record)
        stage = current / (".broomm-incoming-" + secrets.token_hex(16))
        descriptor = os.open(stage, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o700)
        try:
            with os.fdopen(descriptor, "wb") as stream:
                stream.write(binary)
                os.fchmod(stream.fileno(), 0o755)
                os.fsync(stream.fileno())
            # An exclusive publication failure never replaces an existing file.
            os.link(stage, target)
        finally:
            stage.unlink()
        directory = os.open(current, os.O_RDONLY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
        verify_binary(target, record)
        return record["binary_sha256"]
    finally:
        os.close(lock)


def main():
    if os.environ.get("GITHUB_ACTIONS") != "true":
        raise RuntimeError("This cache seed is only for the disposable GitHub Actions runner")
    platform = PLATFORMS.get((os.environ.get("RUNNER_OS"), os.environ.get("RUNNER_ARCH")))
    if platform is None:
        raise RuntimeError("Unsupported CI Devbox host")
    pins = json.loads(Path(__file__).with_name("devbox-0.18.4.json").read_text())
    if pins["version"] != VERSION:
        raise RuntimeError("Devbox bootstrap version differs from its pins")
    token = os.environ.get("GITHUB_TOKEN", "")
    if not token:
        raise RuntimeError("The Devbox release-asset API requires the ephemeral CI GitHub token")
    record = pins["platforms"][platform]
    print("Verifying pinned Devbox " + VERSION + " for " + platform, flush=True)
    digest = seed(Path.home().resolve(), platform, record, lambda: download(record, token))
    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        output.write("binary_sha256=" + digest + "\n")
    print("Verified pinned Devbox archive/binary and seeded the launcher's versioned cache", flush=True)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        # Never print HTTP response bodies or signed URLs in bootstrap errors.
        message = str(error) if isinstance(error, RuntimeError) else type(error).__name__
        raise SystemExit("Devbox cache seed failed: " + message)
