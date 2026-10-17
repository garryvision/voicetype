#!/bin/bash
# VoiceType installer.
# Telecharge les dependances, compile l'app, l'installe dans /Applications,
# pre-telecharge le modele Whisper. Pas de Apple Developer ID requis.

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
MODEL_DIR="$HOME/.voicetype/models"
MODEL_NAME="ggml-large-v3-turbo.bin"
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/${MODEL_NAME}"
MODEL_PATH="$MODEL_DIR/$MODEL_NAME"
MODEL_MIN_SIZE_BYTES=$((1500 * 1024 * 1024))  # ~1.5 GB plancher pour valider l'integrite

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
  warn "Apple Silicon (M1/M2/M3/M4) recommande. Tu es en Intel ($ARCH)."
  warn "VoiceType peut fonctionner mais la transcription sera notablement plus lente."
  read -r -p "Continuer ? [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]] || exit 1
else
  step "Apple Silicon ($ARCH) OK"
fi

# 2. Xcode Command Line Tools (bloquant si absent)
info "Verification des Xcode Command Line Tools"

if ! xcode-select -p &> /dev/null; then
  warn "Xcode Command Line Tools absents."
  warn "Une fenetre Apple va s'ouvrir : clique le bouton bleu 'Installer'."
  warn "L'installation prend 5 a 15 minutes selon ta connexion."
  warn "Quand l'installation Apple est terminee, RELANCE ce script :"
  warn "  cd $REPO_DIR && bash scripts/install.sh"
  xcode-select --install || true
  exit 0
fi
step "Xcode CLI tools OK"

# 3. Homebrew
info "Verification de Homebrew"

if ! command -v brew &> /dev/null; then
  warn "Homebrew non installe."
  warn "Le script officiel Homebrew (brew.sh) va te demander ton mot de passe Mac"
  warn "pour s'installer. C'est documente sur https://brew.sh."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Charger l'environnement Homebrew (gere les 2 paths : Apple Silicon natif, et Mac migres depuis Intel)
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -x /usr/local/bin/brew ]]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

if ! command -v brew &> /dev/null; then
  err "Homebrew n'a pas pu etre charge meme apres installation."
  err "Lance manuellement (depuis le Terminal) :"
  err "  eval \"\$(/opt/homebrew/bin/brew shellenv)\""
  err "Puis relance ce script."
  exit 1
fi

# Une seule ligne, robuste contre SIGPIPE
BREW_VER=$(brew --version 2>/dev/null | sed -n '1p' || true)
step "Homebrew ${BREW_VER:-installed} OK"

# 4. Dependances
info "Installation des dependances (whisper-cpp et ffmpeg)"

if brew list --formula 2>/dev/null | grep -qx whisper-cpp; then
  step "whisper-cpp deja installe"
else
  step "Installation de whisper-cpp (peut prendre 2-3 min)"
  brew install whisper-cpp
fi

if brew list --formula 2>/dev/null | grep -qx ffmpeg; then
  step "ffmpeg deja installe"
else
  step "Installation de ffmpeg (peut prendre 5-10 min selon ta connexion)"
  brew install ffmpeg
fi

if ! command -v whisper-cli &> /dev/null; then
  err "whisper-cli introuvable apres installation. Lance : brew install whisper-cpp"
  exit 1
fi
if ! command -v ffmpeg &> /dev/null; then
  err "ffmpeg introuvable apres installation. Lance : brew install ffmpeg"
  exit 1
fi

# 5. Moteur rapide Parakeet (Apple Silicon uniquement, Whisper reste le secours)
if [[ "$ARCH" == "arm64" ]]; then
  info "Installation du moteur rapide Parakeet (11 MB)"
  if ! bash "$REPO_DIR/scripts/install-parakeet.sh"; then
    warn "Parakeet n'a pas pu etre installe. VoiceType utilisera Whisper normalement."
  fi
fi

# 6. Telechargement du modele Whisper (avant le 1er lancement de l'app)
# On le fait ici via curl (resume natif via -C -), pas dans l'app.
# Avantages : barre de progression visible, retry automatique, reprise si la connexion coupe.
info "Telechargement du modele Whisper (1.5 GB)"

mkdir -p "$MODEL_DIR"

if [ -f "$MODEL_PATH" ]; then
  EXISTING_SIZE=$(stat -f%z "$MODEL_PATH" 2>/dev/null || echo 0)
  if [ "$EXISTING_SIZE" -ge "$MODEL_MIN_SIZE_BYTES" ]; then
    step "Modele deja present et complet ($((EXISTING_SIZE / 1024 / 1024)) MB)"
    SKIP_DL=1
  else
    step "Modele present mais incomplet ($((EXISTING_SIZE / 1024 / 1024)) MB), reprise du telechargement"
    SKIP_DL=0
  fi
else
  SKIP_DL=0
fi

if [ "${SKIP_DL:-0}" = "0" ]; then
  step "Telechargement depuis HuggingFace (peut prendre 5 a 30 min selon ta connexion)"
  step "Si la connexion coupe, relance ce script : il reprendra ou il s'est arrete."
  echo ""

  # -L : suit les redirections HuggingFace
  # --retry 5 : 5 essais en cas d'echec reseau
  # --retry-delay 5 : 5s entre les essais
  # -C - : reprend a partir du dernier byte si fichier partiel
  # --progress-bar : barre de progression simple
  if ! curl -L --retry 5 --retry-delay 5 -C - --progress-bar \
       -o "$MODEL_PATH" "$MODEL_URL"; then
    err "Echec du telechargement du modele apres 5 essais."
    err "Verifie ta connexion internet et relance ce script. Le telechargement reprendra."
    exit 1
  fi

  # Verification taille
  FINAL_SIZE=$(stat -f%z "$MODEL_PATH" 2>/dev/null || echo 0)
  if [ "$FINAL_SIZE" -lt "$MODEL_MIN_SIZE_BYTES" ]; then
    err "Modele telecharge incomplet ($((FINAL_SIZE / 1024 / 1024)) MB, attendu > 1500 MB)."
    err "Relance ce script pour reprendre le telechargement."
    exit 1
  fi
  step "Modele telecharge ($((FINAL_SIZE / 1024 / 1024)) MB)"
fi

# 7. Build et install de l'app
info "Compilation de VoiceType"
cd "$REPO_DIR"
make build

info "Installation dans /Applications"
make install

# 8. Recap permissions
echo ""
echo -e "${GREEN}${BOLD}Installation terminee.${NC}"
echo ""
echo -e "${BOLD}Etape 1 : Lance l'app${NC}"
echo "  open /Applications/VoiceType.app"
echo ""
echo -e "${BOLD}Si macOS te dit 'developer cannot be verified' (macOS 15+) :${NC}"
echo "  Va dans Reglages systeme > Confidentialite et securite,"
echo "  descend en bas, clique 'Ouvrir quand meme' a cote de VoiceType."
echo ""
echo -e "${BOLD}Etape 2 : Autorise 3 permissions${NC}"
echo ""
echo "  1. Microphone : une fenetre Apple va le demander, clique 'Autoriser'."
echo ""
echo "  2. Accessibilite : Reglages systeme > Confidentialite et securite > Accessibilite."
echo "     Clique le cadenas en bas, tape ton mot de passe Mac. Bouton +,"
echo "     choisis VoiceType dans /Applications, valide. Active l'interrupteur."
echo ""
echo "  3. Surveillance des entrees (Input Monitoring) : meme procedure."
echo ""
echo -e "${BOLD}Etape 3 : Quitte et relance VoiceType${NC}"
echo "  killall VoiceType ; open /Applications/VoiceType.app"
echo ""
echo "  (Les permissions ne prennent effet qu'au prochain lancement.)"
echo ""
echo -e "${BOLD}Utilisation${NC}"
echo "  Maintiens la touche Fn (Globe, en bas a gauche du clavier), parle, relache."
echo "  Le texte arrive dans l'application active."
echo ""
echo -e "${BOLD}La capsule (en bas au centre de l'ecran)${NC}"
echo "  Petit trait gris = pret"
echo "  Capsule noire + barres qui bougent = enregistrement (les barres suivent ta voix)"
echo "  Barres en vague = transcription     Message en clair = erreur"
echo "  Clique dessus pour le menu (copier la derniere dictee, pause, quitter...)"
echo ""
echo "Logs : tail -f ~/.voicetype/voicetype.log"
echo ""
