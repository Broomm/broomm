#!/usr/bin/env python3
"""Seed the unchanged Gradle wrapper's private CI ZIP cache, without extraction."""
import fcntl
import hashlib
import os
from pathlib import Path
import secrets
import shutil
import stat
import time
import urllib.error
import urllib.parse
import urllib.request

from seed_devbox import NoRedirect, owned_directory

VERSION = "9.3.1"
ARCHIVE_BYTES = 234893460
ARCHIVE_SHA256 = "17f277867f6914d61b1aa02efab1ba7bb439ad652ca485cd8ca6842fccec6e43"
ASSET_ID = 347704195
WRAPPER_SHA256 = "16caeaf66d57a0d1d2087fef6a97efa62de8da69afa5b908f40db35afc4342da"
DISTRIBUTION = "https://services.gradle.org/distributions/gradle-9.3.1-all.zip"


def flutter_wrapper():
    executable = shutil.which("flutter")
    if executable is None:
        raise RuntimeError("The pinned Flutter environment is required before Gradle preparation")
    wrapper = (Path(executable).resolve().parent.parent /
               "bin/cache/artifacts/gradle_wrapper/gradle/wrapper/gradle-wrapper.jar")
    if hashlib.sha256(wrapper.read_bytes()).hexdigest() != WRAPPER_SHA256:
        raise RuntimeError("Flutter's generated Gradle wrapper changed; review its cache/lock pins")
    return wrapper


def cache_parts():
    # PathAssembler in Flutter's supplied wrapper: positive MD5(uri) in base 36.
    # This is only the wrapper's directory key; SHA-256 verifies the artifact.
    value = int.from_bytes(hashlib.md5(DISTRIBUTION.encode()).digest(), "big")
    key = ""
    while value:
        value, digit = divmod(value, 36)
        key = "0123456789abcdefghijklmnopqrstuvwxyz"[digit] + key
    return ["wrapper", "dists", "gradle-" + VERSION + "-all", key]


def asset_response(token):
    opener = urllib.request.build_opener(NoRedirect)
    request = urllib.request.Request(
        "https://api.github.com/repos/gradle/gradle-distributions/releases/assets/" + str(ASSET_ID),
        headers={"Accept": "application/octet-stream", "Authorization": "Bearer " + token,
                 "User-Agent": "Broomm-pinned-Gradle"})
    try:
        response = opener.open(request, timeout=30)
    except urllib.error.HTTPError as error:
        if error.code != 302:
            raise RuntimeError("Gradle asset API returned HTTP " + str(error.code)) from None
        location = error.headers.get("Location", "")
        parsed = urllib.parse.urlparse(location)
        if (parsed.scheme != "https" or parsed.username or parsed.password or
                not (parsed.hostname or "").endswith((".githubusercontent.com", ".blob.core.windows.net"))):
            raise RuntimeError("Gradle asset API returned an unexpected download host")
        response = opener.open(urllib.request.Request(location, headers={
            "User-Agent": "Broomm-pinned-Gradle"}), timeout=30)
    if response.headers.get_content_type() == "application/json":
        response.close()
        raise RuntimeError("Gradle asset API returned metadata instead of the archive")
    return response


def verify(path, expected_bytes, expected_sha256):
    with os.fdopen(os.open(path, os.O_RDONLY | os.O_NOFOLLOW), "rb") as stream:
        before = os.fstat(stream.fileno())
        if (not stat.S_ISREG(before.st_mode) or before.st_uid != os.getuid() or
                before.st_nlink != 1 or before.st_size != expected_bytes or before.st_mode & 0o022):
            raise RuntimeError("Unexpected Gradle cache ownership, size, links or mode; cache kept")
        digest = hashlib.sha256()
        count = 0
        while chunk := stream.read(min(1024 * 1024, expected_bytes - count + 1)):
            count += len(chunk)
            if count > expected_bytes:
                raise RuntimeError("Gradle cache changed while verifying; cache kept")
            digest.update(chunk)
        after = os.fstat(stream.fileno())
        identity = lambda s: (s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_ctime_ns, s.st_nlink, s.st_uid, s.st_mode)
        if identity(before) != identity(after) or identity(after) != identity(path.lstat()) or digest.hexdigest() != expected_sha256:
            raise RuntimeError("Gradle cache checksum/identity mismatch; cache kept")


def seed(gradle_home, fetch, expected_bytes=ARCHIVE_BYTES, expected_sha256=ARCHIVE_SHA256):
    owned_directory(gradle_home)
    directory = gradle_home
    for component in cache_parts():
        directory /= component
        owned_directory(directory)
    target = directory / ("gradle-" + VERSION + "-all.zip")
    # Match Java FileChannel's POSIX record lock, including other processes.
    lock = os.open(str(target) + ".lck", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    try:
        info = os.fstat(lock)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_nlink != 1:
            raise RuntimeError("Invalid Gradle distribution lock")
        try:
            fcntl.lockf(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError("Another process holds the Gradle distribution lock") from None
        if os.path.lexists(target):
            verify(target, expected_bytes, expected_sha256)
            return target
        # Refuse unexplained extraction/partial-download leftovers. The wrapper
        # owns extraction only after the verified archive is published.
        if any(p.name != target.name + ".lck" for p in directory.iterdir()):
            raise RuntimeError("Gradle distribution cache is incomplete or foreign; contents kept")
        stage = directory / (".broomm-incoming-" + secrets.token_hex(16))
        descriptor = os.open(stage, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
        try:
            digest = hashlib.sha256()
            count = 0
            deadline = time.monotonic() + 180
            with os.fdopen(descriptor, "wb") as output, fetch() as source:
                while chunk := source.read(min(1024 * 1024, expected_bytes - count + 1)):
                    count += len(chunk)
                    if count > expected_bytes or time.monotonic() > deadline:
                        raise RuntimeError("Gradle archive exceeds its size/time limit")
                    digest.update(chunk)
                    output.write(chunk)
                if count != expected_bytes or digest.hexdigest() != expected_sha256:
                    raise RuntimeError("Gradle archive size/checksum mismatch")
                os.fsync(output.fileno())
            os.link(stage, target)
        finally:
            stage.unlink()
        fd = os.open(directory, os.O_RDONLY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)
        verify(target, expected_bytes, expected_sha256)
        return target
    finally:
        os.close(lock)


def main():
    if os.environ.get("GITHUB_ACTIONS") != "true":
        raise RuntimeError("Gradle cache seeding is limited to disposable CI runners")
    root = Path(__file__).resolve().parents[2]
    properties = root / "android/gradle/wrapper/gradle-wrapper.properties"
    flutter_wrapper()
    generated = properties.with_name("gradle-wrapper.jar")
    if generated.exists() and hashlib.sha256(generated.read_bytes()).hexdigest() != WRAPPER_SHA256:
        raise RuntimeError("The generated project wrapper differs from Flutter's verified artifact")
    values = dict(line.split("=", 1) for line in properties.read_text().splitlines() if "=" in line)
    if values != {"distributionBase": "GRADLE_USER_HOME", "distributionPath": "wrapper/dists",
                  "zipStoreBase": "GRADLE_USER_HOME", "zipStorePath": "wrapper/dists",
                  "distributionUrl": DISTRIBUTION.replace(":", "\\:")}:
        raise RuntimeError("Gradle wrapper configuration changed; review its archive/cache pins")
    token = os.environ.get("GITHUB_TOKEN", "")
    if not token:
        raise RuntimeError("The ephemeral CI GitHub token is required")
    destination = root / ".tool-cache/android/gradle"
    if Path(os.environ.get("GRADLE_USER_HOME", "")).resolve() != destination:
        raise RuntimeError("Gradle home differs from the private project cache")
    target = seed(destination, lambda: asset_response(token))
    print("Verified official Gradle " + VERSION + " ZIP in " + str(target.relative_to(root)), flush=True)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        message = str(error) if isinstance(error, RuntimeError) else type(error).__name__
        raise SystemExit("Gradle cache seed failed: " + message)
