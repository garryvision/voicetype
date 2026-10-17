#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)

mkdir -p "$TMP/package/FluidAudio_FluidAudioCLI.bundle"
mkdir -p "$TMP/package/FluidAudio_LuxTtsG2pResources.bundle"
printf '#!/bin/sh\necho parakeet-test\n' > "$TMP/package/fluidaudiocli"
chmod +x "$TMP/package/fluidaudiocli"
tar -czf "$TMP/parakeet.tar.gz" -C "$TMP/package" .
SHA=$(shasum -a 256 "$TMP/parakeet.tar.gz" | awk '{print $1}')

VOICETYPE_HOME="$TMP/home/.voicetype" \
PARAKEET_URL="file://$TMP/parakeet.tar.gz" \
PARAKEET_SHA256="$SHA" \
bash "$ROOT/scripts/install-parakeet.sh"

test -x "$TMP/home/.voicetype/bin/fluidaudiocli"
test -d "$TMP/home/.voicetype/bin/FluidAudio_FluidAudioCLI.bundle"
test -d "$TMP/home/.voicetype/bin/FluidAudio_LuxTtsG2pResources.bundle"
test "$("$TMP/home/.voicetype/bin/fluidaudiocli")" = "parakeet-test"

echo "PASS Parakeet installer"
