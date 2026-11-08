import hashlib
import io
from pathlib import Path
import subprocess
import tempfile
import unittest

import seed_gradle as bootstrap


class GradleSeedTests(unittest.TestCase):
    def test_verified_zip_is_published_exclusively_and_reused_offline(self):
        data = b"verified distribution fixture"
        digest = hashlib.sha256(data).hexdigest()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            target = bootstrap.seed(root, lambda: io.BytesIO(data), len(data), digest)
            before = target.stat()
            self.assertEqual(target.read_bytes(), data)
            self.assertEqual(before.st_nlink, 1)
            result = bootstrap.seed(root, lambda: self.fail("Verified cache must work offline"), len(data), digest)
            self.assertEqual(result.stat().st_ino, before.st_ino)
            self.assertEqual(result.stat().st_mtime_ns, before.st_mtime_ns)
            target.write_bytes(b"another installation")
            with self.assertRaises(RuntimeError):
                bootstrap.seed(root, lambda: self.fail("Foreign cache must not fetch"), len(data), digest)
            self.assertEqual(target.read_bytes(), b"another installation")

    def test_corrupt_interrupted_and_foreign_stages_remain_unpublished(self):
        data = b"expected distribution"
        digest = hashlib.sha256(data).hexdigest()
        for incoming in [data + b"oversize", data[:-1], b"x" * len(data)]:
            with self.subTest(incoming=incoming), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary).resolve()
                with self.assertRaises(RuntimeError):
                    bootstrap.seed(root, lambda: io.BytesIO(incoming), len(data), digest)
                directory = root.joinpath(*bootstrap.cache_parts())
                self.assertEqual([p.name for p in directory.iterdir()], ["gradle-9.3.1-all.zip.lck"])
                foreign = directory / "gradle-9.3.1-all.zip.part"
                foreign.write_bytes(b"retained partial transfer")
                with self.assertRaisesRegex(RuntimeError, "incomplete or foreign"):
                    bootstrap.seed(root, lambda: self.fail("Unknown partial must be retained"), len(data), digest)
                self.assertEqual(foreign.read_bytes(), b"retained partial transfer")

    def test_actual_java_wrapper_cache_path_and_record_lock_are_respected(self):
        # Use Flutter's real supplied wrapper and a separate Java process holding
        # its actual FileChannel lock; a Python-only imitation proves neither.
        wrapper = bootstrap.flutter_wrapper()
        self.assertEqual(hashlib.sha256(wrapper.read_bytes()).hexdigest(), bootstrap.WRAPPER_SHA256)
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary).resolve()
            source = root / "HeldWrapper.java"
            source.write_text('''
import java.io.*;
import java.net.URI;
import java.nio.channels.*;
import org.gradle.wrapper.*;
class HeldWrapper {
  public static void main(String[] args) throws Exception {
    WrapperConfiguration config = new WrapperConfiguration();
    config.setDistribution(new URI(args[1]));
    File zip = new PathAssembler(new File(args[0])).getDistribution(config).getZipFile();
    zip.getParentFile().mkdirs();
    try (RandomAccessFile file = new RandomAccessFile(zip + ".lck", "rw");
         FileLock held = file.getChannel().lock()) {
      System.out.println(zip.getCanonicalPath()); System.out.flush();
      System.in.read();
    }
  }
}
''')
            subprocess.run(["javac", "-cp", str(wrapper), str(source)], check=True, capture_output=True, timeout=20)
            child = subprocess.Popen(["java", "-cp", str(wrapper) + ":" + str(root), "HeldWrapper", str(root), bootstrap.DISTRIBUTION],
                                     stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            try:
                observed = child.stdout.readline().strip()
                expected = root.joinpath(*bootstrap.cache_parts(), "gradle-9.3.1-all.zip")
                self.assertEqual(observed, str(expected))
                with self.assertRaisesRegex(RuntimeError, "Another process holds"):
                    bootstrap.seed(root, lambda: self.fail("Live wrapper must refuse before network"), 1, "0" * 64)
                self.assertFalse(expected.exists())
            finally:
                child.communicate("release\n", timeout=10)
                self.assertEqual(child.returncode, 0)


if __name__ == "__main__":
    unittest.main()
