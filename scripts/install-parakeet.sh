#!/bin/bash
# Installs the optional FluidAudio/Parakeet accelerator on Apple Silicon.
# Failure is handled by the caller: VoiceType can always fall back to Whisper.

set -euo pipefail

VOICE_HOME="${VOICETYPE_HOME:-$HOME/.voicetype}"
BIN_DIR="$VOICE_HOME/bin"
MARKER="$BIN_DIR/parakeet-package.sha256"
PARAKEET_URL="${PARAKEET_URL:-https://github.com/garryvision/voicetype/releases/download/v0.4.0/VoiceType-Parakeet-macos-arm64-v0.4.0.tar.gz}"
PARAKEET_SHA256="${PARAKEET_SHA256:-7461ea4da7307be93497f9204113407b0b42d42ef6412a8617dceefd71ebb394}"

if [[ -x "$BIN_DIR/fluidaudiocli" ]] \
   && [[ -d "$BIN_DIR/FluidAudio_FluidAudioCLI.bundle" ]] \
   && [[ -d "$BIN_DIR/FluidAudio_LuxTtsG2pResources.bundle" ]] \
   && [[ -f "$MARKER" ]] \
   && [[ "$(tr -d '[:space:]' < "$MARKER")" == "$PARAKEET_SHA256" ]]; then
    echo "    Parakeet deja installe"
    exit 0
fi

STAGING=$(mktemp -d)
ARCHIVE="$STAGING/parakeet.tar.gz"
EXTRACTED="$STAGING/extracted"
mkdir -p "$EXTRACTED"

curl --fail --location --retry 3 --progress-bar -o "$ARCHIVE" "$PARAKEET_URL"
ACTUAL_SHA=$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')
if [[ "$ACTUAL_SHA" != "$PARAKEET_SHA256" ]]; then
    echo "Archive Parakeet invalide (empreinte SHA-256 incorrecte)" >&2
    exit 1
fi

tar -xzf "$ARCHIVE" -C "$EXTRACTED"
if [[ ! -x "$EXTRACTED/fluidaudiocli" ]] \
   || [[ ! -d "$EXTRACTED/FluidAudio_FluidAudioCLI.bundle" ]] \
   || [[ ! -d "$EXTRACTED/FluidAudio_LuxTtsG2pResources.bundle" ]]; then
    echo "Archive Parakeet incomplete" >&2
    exit 1
fi

mkdir -p "$BIN_DIR"
ditto "$EXTRACTED/" "$BIN_DIR/"
printf '%s\n' "$PARAKEET_SHA256" > "$MARKER"
echo "    Parakeet installe"
