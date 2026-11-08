import fcntl
import hashlib
from http.client import HTTPMessage
import io
import os
from pathlib import Path
import tarfile
import tempfile
import unittest
import urllib.error

import seed_devbox as bootstrap


def artifact(name="devbox", symlink=False):
    binary = b"pinned tool fixture\n"
    output = io.BytesIO()
    with tarfile.open(fileobj=output, mode="w:gz") as archive:
        entry = tarfile.TarInfo(name)
        entry.mode = 0o755
        if symlink:
            entry.type = tarfile.SYMTYPE
            entry.linkname = "outside"
            archive.addfile(entry)
        else:
            entry.size = len(binary)
            archive.addfile(entry, io.BytesIO(binary))
    data = output.getvalue()
    record = {"asset_id": 1, "archive_bytes": len(data),
              "archive_sha256": hashlib.sha256(data).hexdigest(),
              "binary_bytes": len(binary), "binary_sha256": hashlib.sha256(binary).hexdigest()}
    return data, binary, record


class Response(io.BytesIO):
    def __init__(self, data, kind="application/octet-stream"):
        super().__init__(data)
        self.headers = HTTPMessage()
        self.headers["Content-Type"] = kind


class BootstrapTests(unittest.TestCase):
    def test_asset_redirect_drops_credential_and_refuses_unexpected_hosts(self):
        data, _, record = artifact()
        requests = []

        def open_request(request, timeout):
            requests.append(request)
            if len(requests) == 1:
                headers = HTTPMessage()
                headers["Location"] = "https://release-assets.githubusercontent.com/pinned?signature=fixture"
                raise urllib.error.HTTPError(request.full_url, 302, "Redirect", headers, None)
            return Response(data)

        self.assertEqual(bootstrap.download(record, "fixture-credential", open_request), data)
        self.assertEqual(requests[0].get_header("Authorization"), "Bearer fixture-credential")
        self.assertIsNone(requests[1].get_header("Authorization"))

        def foreign(request, timeout):
            headers = HTTPMessage()
            headers["Location"] = "https://githubusercontent.com.foreign.invalid/archive"
            raise urllib.error.HTTPError(request.full_url, 302, "Redirect", headers, None)

        with self.assertRaisesRegex(RuntimeError, "unexpected download host"):
            bootstrap.download(record, "fixture-credential", foreign)
        with self.assertRaisesRegex(RuntimeError, "metadata instead"):
            bootstrap.download(record, "fixture-credential", lambda *a, **k: Response(b"{}", "application/json"))

    def test_verified_cache_replays_offline_and_never_replaces_a_foreign_binary(self):
        data, binary, record = artifact()
        with tempfile.TemporaryDirectory() as temporary:
            runner_home = Path(temporary).resolve()
            result = bootstrap.seed(runner_home, "linux_amd64", record, lambda: data)
            target = runner_home / ".cache/devbox/bin/0.18.4_linux_amd64/devbox"
            self.assertEqual(result, record["binary_sha256"])
            self.assertEqual(target.read_bytes(), binary)
            before = target.stat()

            def no_download():
                self.fail("A verified pinned cache should not need the network")

            bootstrap.seed(runner_home, "linux_amd64", record, no_download)
            self.assertEqual(target.stat().st_ino, before.st_ino)
            self.assertEqual(target.stat().st_mtime_ns, before.st_mtime_ns)
            target.write_bytes(b"foreign cache content")
            with self.assertRaises(RuntimeError):
                bootstrap.seed(runner_home, "linux_amd64", record, no_download)
            self.assertEqual(target.read_bytes(), b"foreign cache content")

    def test_corrupt_or_unsafe_archive_and_held_cache_lock_publish_no_executable(self):
        data, _, record = artifact()
        traversal, _, traversal_record = artifact("../devbox")
        symlink, _, symlink_record = artifact(symlink=True)
        for incoming, identity in [(data + b"changed", record),
                                   (traversal, traversal_record),
                                   (symlink, symlink_record)]:
            with self.subTest(incoming=identity["archive_sha256"]), tempfile.TemporaryDirectory() as temporary:
                runner_home = Path(temporary).resolve()
                with self.assertRaises(RuntimeError):
                    bootstrap.seed(runner_home, "linux_amd64", identity, lambda: incoming)
                self.assertFalse((runner_home / ".cache/devbox/bin/0.18.4_linux_amd64/devbox").exists())
        with tempfile.TemporaryDirectory() as temporary:
            runner_home = Path(temporary).resolve()
            directory = runner_home / ".cache/devbox/bin/0.18.4_linux_amd64"
            directory.mkdir(parents=True)
            with (directory / ".broomm-seed.lock").open("wb") as held:
                fcntl.flock(held, fcntl.LOCK_EX | fcntl.LOCK_NB)
                with self.assertRaisesRegex(RuntimeError, "Another runner process"):
                    bootstrap.seed(runner_home, "linux_amd64", record, lambda: self.fail("A held production lock must refuse before downloading"))
            self.assertFalse((directory / "devbox").exists())


if __name__ == "__main__":
    unittest.main()
