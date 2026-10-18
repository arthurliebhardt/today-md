import base64
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("release_metadata", SCRIPTS / "release-metadata.py")
metadata = importlib.util.module_from_spec(spec)
spec.loader.exec_module(metadata)


class ReleaseMetadataTests(unittest.TestCase):
    def test_stable_tag_only(self):
        self.assertEqual(metadata.version_for_tag("v1.9.0"), "1.9.0")
        for tag in ("main", "v1.9.0-rc1", "v1.9", "v01.9.0", "v1.9.0;echo unsafe"):
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                metadata.version_for_tag(tag)

    def test_input_failures_do_not_expose_secret_values(self):
        version, _ = metadata.project_version()
        secret = "invalid-private-value-that-must-not-be-printed"
        with patch.dict(os.environ, {
            "RELEASE_TAG": "v" + version, "MACOS_TEAM_ID": "ABCDE12345",
            "SPARKLE_PUBLIC_ED_KEY": base64.b64encode(bytes(32)).decode(),
            "MACOS_SIGNING_P12": "YQ==", "MACOS_SIGNING_P12_PASSWORD": "test-only",
            "ASC_KEY_ID": "test", "ASC_ISSUER_ID": "test",
            "ASC_PRIVATE_KEY_P8": "-----BEGIN PRIVATE KEY-----", "SPARKLE_PRIVATE_KEY": secret,
        }, clear=True):
            with self.assertRaises(ValueError) as result:
                metadata.check_inputs()
        self.assertNotIn(secret, str(result.exception))

    def test_rejects_unsigned_or_truncated_feed(self):
        with tempfile.TemporaryDirectory() as directory:
            feed = Path(directory) / "appcast.xml"
            for content in (b"<rss/>", b"<rss/><!-- sparkle-signatures:\n", b"<rss/><!-- sparkle-signatures:\nedSignature: AAA=\nlength: 999\n-->\n"):
                feed.write_bytes(content)
                with self.assertRaises(ValueError):
                    metadata.signed_feed(feed)


@unittest.skipUnless(sys.platform == "darwin", "CryptoKit verification runs on macOS")
class SparkleSignatureTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.directory_path = Path(self.directory.name)
        self.archive = self.directory_path / "today-md-v1.9.0-macos.zip"
        self.archive.write_bytes(b"archive fixture bytes")
        self.feed = self.directory_path / "appcast.xml"
        # A temporary test key is generated in memory. No Keychain is accessed.
        signatures = subprocess.run(["xcrun", "swift", "-", str(self.archive)], input=r'''
import CryptoKit
import Foundation
let key = Curve25519.Signing.PrivateKey()
let archive = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let signature = try key.signature(for: archive).base64EncodedString()
let xml = """
<?xml version="1.0"?><rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item><title>Release</title><sparkle:version>32</sparkle:version><sparkle:shortVersionString>1.9.0</sparkle:shortVersionString><description>Notes</description><enclosure url="https://github.com/arthurliebhardt/today-md/releases/download/v1.9.0/today-md-v1.9.0-macos.zip" length="\(archive.count)" sparkle:edSignature="\(signature)"/></item></channel></rss>
"""
let content = Data(xml.utf8)
let feedSignature = try key.signature(for: content).base64EncodedString()
let result = ["public": key.publicKey.rawRepresentation.base64EncodedString(),
              "xml": xml + "<!-- sparkle-signatures:\nedSignature: \(feedSignature)\nlength: \(content.count)\n-->\n"]
print(String(data: try JSONEncoder().encode(result), encoding: .utf8)!)
''', text=True, capture_output=True, check=True)
        result = json.loads(signatures.stdout)
        self.feed.write_text(result["xml"])
        self.public_key = result["public"]

    def verify(self):
        return subprocess.run(["bash", str(SCRIPTS / "verify-sparkle-release.sh"),
                               str(self.feed), str(self.archive), "v1.9.0", "32"],
                              env={**os.environ, "SPARKLE_PUBLIC_ED_KEY": self.public_key},
                              text=True, capture_output=True)

    def test_signed_artifacts_pass(self):
        result = self.verify()
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_archive_tampering_fails(self):
        self.archive.write_bytes(b"Archive fixture bytes")
        result = self.verify()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("signature does not match", result.stderr)

    def test_feed_tampering_fails(self):
        self.feed.write_text(self.feed.read_text().replace("Release", "release"))
        result = self.verify()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("signature does not match", result.stderr)

    def test_wrong_public_key_fails(self):
        self.public_key = base64.b64encode(bytes(32)).decode()
        result = self.verify()
        self.assertNotEqual(result.returncode, 0)

    def test_archive_url_must_be_immutable(self):
        self.feed.write_text(self.feed.read_text().replace("download/v1.9.0/", "latest/download/"))
        with self.assertRaisesRegex(ValueError, "immutable"):
            metadata.check_appcast(self.feed, self.archive, "v1.9.0", "32")


if __name__ == "__main__":
    unittest.main()
