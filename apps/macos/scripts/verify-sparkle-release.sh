#!/usr/bin/env bash
# Independently verify Ed25519 signatures against the public key shipped in the app.
set -euo pipefail
script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
feed=${1:?Usage: verify-sparkle-release.sh appcast.xml archive.zip tag build}
archive=${2:?Archive required}
tag=${3:?Tag required}
build=${4:?Build required}
: "${SPARKLE_PUBLIC_ED_KEY:?Set SPARKLE_PUBLIC_ED_KEY}"
verification_dir=$(mktemp -d "${TMPDIR:-/tmp}/today-md-verify.XXXXXX")
trap 'rm -rf "$verification_dir"' EXIT
python3 "$script_dir/release-metadata.py" check-appcast "$feed" "$archive" "$tag" "$build" "$verification_dir"
xcrun swift - "$verification_dir" "$archive" "$SPARKLE_PUBLIC_ED_KEY" <<'SWIFT'
import CryptoKit
import Foundation

let args = CommandLine.arguments
let directory = URL(fileURLWithPath: args[1])
guard let publicData = Data(base64Encoded: args[3]), publicData.count == 32 else {
    fatalError("Invalid configured Sparkle public key")
}
let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicData)
let signatures = try JSONDecoder().decode([String: String].self,
    from: Data(contentsOf: directory.appendingPathComponent("signatures.json")))
for (kind, file) in [("feed", directory.appendingPathComponent("feed-content")),
                     ("archive", URL(fileURLWithPath: args[2]))] {
    guard let encoded = signatures[kind], let signature = Data(base64Encoded: encoded),
          publicKey.isValidSignature(signature, for: try Data(contentsOf: file, options: .mappedIfSafe)) else {
        fputs("Sparkle \(kind) signature does not match the configured public key\n", stderr)
        exit(1)
    }
}
print("Sparkle feed and archive signatures verified against the app public key")
SWIFT
