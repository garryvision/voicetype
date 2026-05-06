#!/bin/bash
# VoiceType installer
# Telecharge les dependances, compile l'app, l'installe dans /Applications.
# Pas de Apple Developer ID requis. Signature ad-hoc locale.

set -euo pipefail

# Couleurs
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${GREEN}==>${NC} ${BOLD}$1${NC}"; }
warn()    { echo -e "${YELLOW}!  ${NC} $1"; }
err()     { echo -e "${RED}X  ${NC} $1" >&2; }
step()    { echo -e "    $1"; }

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="VoiceType"

echo ""
echo -e "${BOLD}VoiceType installer${NC}"
echo "Dossier de travail : $REPO_DIR"
echo ""

# 1. macOS check
info "Verification du systeme"

if [[ "$(uname)" != "Darwin" ]]; then
  err "VoiceType est macOS uniquement. Ton systeme : $(uname)"
  exit 1
fi

MACOS_MAJOR=$(sw_vers -productVersion | cut -d. -f1)
if [[ "$MACOS_MAJOR" -lt 14 ]]; then
  err "macOS 14 (Sonoma) minimum requis. Tu es en macOS $(sw_vers -productVersion)."
  err "Mets a jour macOS via Reglages systeme > General > Mise a jour de logiciels."
  exit 1
fi
step "macOS $(sw_vers -productVersion) OK"

ARCH=$(uname -m)
if [[ "$ARCH" != "arm64" ]]; then
  warn "Apple Silicon recommande. Tu es en Intel ($ARCH)."
  warn "VoiceType peut fonctionner mais la transcription sera plus lente."
  read -r -p "Continuer ? [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]] || exit 1
else
  step "Apple Silicon ($ARCH) OK"
fi

# 2. Xcode Command Line Tools
info "Verification des Xcode Command Line Tools"

if ! xcode-select -p &> /dev/null; then
  warn "Xcode Command Line Tools non installes."
  warn "Une boite de dialogue Apple va s'ouvrir : clique 'Installer'."
  warn "Quand l'install Apple est terminee, relance ce script."
  xcode-select --install
  exit 0
fi
step "Xcode CLI tools OK"

# 3. Homebrew
info "Verification de Homebrew"

if ! command -v brew &> /dev/null; then
  warn "Homebrew non installe. Installation en cours."
  warn "Ton mot de passe Mac va etre demande pour autoriser l'installation."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Charger l'environnement Homebrew pour la suite du script
  if [[ "$ARCH" == "arm64" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  else
    eval "$(/usr/local/bin/brew shellenv)"
  fi
fi
step "Homebrew $(brew --version | head -1) OK"

# 4. Dependances
info "Installation des dependances (whisper-cpp et ffmpeg)"

if brew list whisper-cpp &> /dev/null; then
  step "whisper-cpp deja installe"
else
  step "Installation de whisper-cpp (peut prendre 2-3 min)"
  brew install whisper-cpp
fi

if brew list ffmpeg &> /dev/null; then
  step "ffmpeg deja installe"
else
  step "Installation de ffmpeg (peut prendre 5-10 min selon ta connexion)"
  brew install ffmpeg
fi

# Verifier que les binaires sont accessibles
if ! command -v whisper-cli &> /dev/null; then
  err "whisper-cli introuvable apres installation."
  err "Lance manuellement : brew install whisper-cpp"
  exit 1
fi
if ! command -v ffmpeg &> /dev/null; then
  err "ffmpeg introuvable apres installation."
  err "Lance manuellement : brew install ffmpeg"
  exit 1
fi

# 5. Build et install de l'app
info "Compilation de VoiceType"

cd "$REPO_DIR"
make build

info "Installation dans /Applications"
make install

# 6. Recap
echo ""
echo -e "${GREEN}${BOLD}Installation terminee.${NC}"
echo ""
echo -e "${BOLD}Etape suivante : autoriser 3 permissions macOS.${NC}"
echo ""
echo "1. Lance l'app :"
echo "   open /Applications/VoiceType.app"
echo ""
echo "2. Une boite Apple va demander l'acces au microphone : clique 'Autoriser'."
echo ""
echo "3. Va dans Reglages systeme > Confidentialite et securite, puis active VoiceType dans :"
echo "   - Accessibilite"
echo "   - Surveillance des entrees"
echo ""
echo "   Si VoiceType n'apparait pas dans la liste, clique le bouton + et choisis"
echo "   /Applications/VoiceType.app"
echo ""
echo "4. Quitte VoiceType (clic droit sur le dot ou : killall VoiceType)"
echo "   puis relance l'app pour que les permissions prennent effet."
echo ""
echo -e "${BOLD}Au tout premier lancement :${NC}"
echo "L'app telecharge le modele Whisper (1.5 GB). Compte 5 a 15 minutes selon ta connexion."
echo "Le dot reste gris pendant le telechargement, puis devient vert quand pret."
echo ""
echo -e "${BOLD}Utilisation :${NC}"
echo "Maintiens Fn (touche Globe en bas a gauche du clavier), parle, relache."
echo "Le texte arrive dans l'app active."
echo ""
echo "Logs : tail -f ~/.voicetype/voicetype.log"
echo ""
