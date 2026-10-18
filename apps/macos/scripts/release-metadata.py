#!/usr/bin/env python3
"""Release input and artifact checks, without reading any local credentials."""

import argparse
import base64
import binascii
import json
import os
from pathlib import Path
import plistlib
import re
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[3]
REPOSITORY = "arthurliebhardt/today-md"
FEED_URL = f"https://github.com/{REPOSITORY}/releases/latest/download/appcast.xml"
SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def decode(value, name, lengths=None):
    try:
        result = base64.b64decode(value.strip(), validate=True)
    except (ValueError, binascii.Error):
        raise ValueError(f"{name} must contain valid base64") from None
    require(lengths is None or len(result) in lengths, f"{name} has an invalid length")
    return result


def version_for_tag(tag):
    require(re.fullmatch(r"v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", tag),
            "Release tag must be a stable version in the form vX.Y.Z")
    return tag[1:]


def project_version():
    project = (ROOT / "apps/macos/Config/Version.xcconfig").read_text()
    values = []
    for setting in ("MARKETING_VERSION", "CURRENT_PROJECT_VERSION"):
        matches = set(re.findall(rf"^{setting}\s*=\s*([^;\n]+)", project, re.MULTILINE))
        require(len(matches) == 1, f"All targets and configurations must agree on {setting}")
        values.append(matches.pop().strip('"'))
    require(values[1].isdigit(), "CURRENT_PROJECT_VERSION must be a numeric, increasing build")
    return values


def check_inputs():
    for name in ("RELEASE_TAG", "MACOS_TEAM_ID", "SPARKLE_PUBLIC_ED_KEY", "MACOS_SIGNING_P12",
                 "MACOS_SIGNING_P12_PASSWORD", "ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_PRIVATE_KEY_P8",
                 "SPARKLE_PRIVATE_KEY"):
        require(bool(os.environ.get(name)), f"Required release configuration is missing: {name}")
    require(version_for_tag(os.environ["RELEASE_TAG"]) == project_version()[0],
            "The release tag does not match MARKETING_VERSION; bump both app targets first")
    require(re.fullmatch(r"[A-Z0-9]{10}", os.environ["MACOS_TEAM_ID"]), "MACOS_TEAM_ID must be an Apple Team ID")
    decode(os.environ["SPARKLE_PUBLIC_ED_KEY"], "SPARKLE_PUBLIC_ED_KEY", (32,))
    decode(os.environ["SPARKLE_PRIVATE_KEY"], "SPARKLE_PRIVATE_KEY", (32, 64, 96))
    decode(os.environ["MACOS_SIGNING_P12"], "MACOS_SIGNING_P12")
    require("-----BEGIN PRIVATE KEY-----" in os.environ["ASC_PRIVATE_KEY_P8"],
            "ASC_PRIVATE_KEY_P8 must contain the raw multiline .p8 file")


def check_app(app, tag, public_key):
    with (app / "Contents/Info.plist").open("rb") as stream:
        info = plistlib.load(stream)
    require(info["CFBundleIdentifier"] == "com.today-md.app", "Unexpected application bundle ID")
    require(info["CFBundleShortVersionString"] == version_for_tag(tag), "Archived version does not match the release tag")
    require(str(info["CFBundleVersion"]).isdigit(), "CFBundleVersion must be numeric")
    require(info.get("SUFeedURL") == FEED_URL, "The archive does not use the stable GitHub update feed")
    require(info.get("SUPublicEDKey") == public_key, "Archived Sparkle public key does not match CI configuration")
    require(info.get("SURequireSignedFeed") is True, "The archive must require a signed update feed")
    require(info.get("SUVerifyUpdateBeforeExtraction") is True, "The archive must verify updates before extraction")
    return str(info["CFBundleVersion"])


def signed_feed(feed):
    data = feed.read_bytes()
    marker = b"<!-- sparkle-signatures:\n"
    position = data.rfind(marker)
    require(position >= 0, "The appcast is missing its embedded Sparkle signature")
    block = data[position + len(marker):]
    match = re.fullmatch(rb"edSignature: ([A-Za-z0-9+/=]+)\nlength: ([0-9]+)\n-->\n?", block)
    require(match is not None, "Invalid Sparkle feed signing block")
    require(int(match[2]) == position, "Signed feed content length does not match its signature block")
    decode(match[1].decode(), "Feed signature", (64,))
    return data[:position], match[1].decode()


def check_appcast(feed, archive, tag, build):
    content, feed_signature = signed_feed(feed)
    document = ET.fromstring(content)
    candidates = [item for item in document.findall("./channel/item")
                  if item.findtext(f"{SPARKLE}version") == build]
    require(len(candidates) == 1, "The appcast must have one item for this build")
    item = candidates[0]
    require(item.findtext(f"{SPARKLE}shortVersionString") == version_for_tag(tag), "Appcast version does not match the tag")
    enclosure = item.find("enclosure")
    require(enclosure is not None, "Appcast update archive is missing")
    expected = f"https://github.com/{REPOSITORY}/releases/download/{tag}/{archive.name}"
    require(enclosure.get("url") == expected, "Appcast archive must use the immutable tagged download URL")
    require(enclosure.get("length") == str(archive.stat().st_size), "Appcast archive size is incorrect")
    archive_signature = enclosure.get(f"{SPARKLE}edSignature", "")
    decode(archive_signature, "Archive signature", (64,))
    require(item.find("description") is not None, "Release notes must be embedded in the signed feed")
    require(item.find(f"{SPARKLE}releaseNotesLink") is None, "Do not fetch unsigned external release notes")
    return content, feed_signature, archive_signature


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    version = sub.add_parser("project-version")
    version.add_argument("--short", action="store_true")
    version.add_argument("--build", action="store_true")
    sub.add_parser("check-inputs")
    app = sub.add_parser("check-app")
    app.add_argument("app", type=Path)
    app.add_argument("tag")
    feed = sub.add_parser("check-appcast")
    feed.add_argument("feed", type=Path)
    feed.add_argument("archive", type=Path)
    feed.add_argument("tag")
    feed.add_argument("build")
    feed.add_argument("verification_dir", type=Path)
    previous = sub.add_parser("check-previous-build")
    previous.add_argument("feed", type=Path)
    previous.add_argument("build")
    args = parser.parse_args()
    if args.command == "project-version":
        short, build = project_version()
        print(build if args.build else short)
    elif args.command == "check-inputs":
        check_inputs()
    elif args.command == "check-app":
        print(check_app(args.app, args.tag, os.environ["SPARKLE_PUBLIC_ED_KEY"]))
    elif args.command == "check-appcast":
        content, signature, archive_signature = check_appcast(args.feed, args.archive, args.tag, args.build)
        args.verification_dir.mkdir(parents=True, exist_ok=True)
        (args.verification_dir / "feed-content").write_bytes(content)
        (args.verification_dir / "signatures.json").write_text(json.dumps({
            "feed": signature, "archive": archive_signature,
        }))
    elif args.command == "check-previous-build":
        content, _ = signed_feed(args.feed)
        builds = [item.findtext(f"{SPARKLE}version", "") for item in ET.fromstring(content).findall("./channel/item")]
        require(all(build.isdigit() and int(build) < int(args.build) for build in builds),
                "CURRENT_PROJECT_VERSION must exceed every build in the existing stable feed")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, ET.ParseError) as error:
        sys.exit(f"Release validation failed: {error}")
