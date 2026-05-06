#!/bin/bash
# Desinstalle VoiceType.
# Garde Homebrew et ses paquets (ils peuvent servir a d'autres outils).

set -euo pipefail

echo "Desinstallation de VoiceType"

killall VoiceType 2> /dev/null || true
sleep 1

rm -rf /Applications/VoiceType.app
rm -rf ~/.voicetype

# LaunchAgent eventuel (au cas ou)
LAUNCH_AGENT=~/Library/LaunchAgents/com.clement.voicetype.plist
if [ -f "$LAUNCH_AGENT" ]; then
  launchctl unload "$LAUNCH_AGENT" 2> /dev/null || true
  rm -f "$LAUNCH_AGENT"
fi

echo "Fait."
echo ""
echo "VoiceType est desinstalle."
echo ""
echo "Les paquets Homebrew (whisper-cpp et ffmpeg) restent installes."
echo "Pour les retirer : brew uninstall whisper-cpp ffmpeg"
echo ""
echo "Tu peux aussi retirer les permissions VoiceType dans :"
echo "Reglages systeme > Confidentialite et securite > Microphone / Accessibilite / Surveillance des entrees"
