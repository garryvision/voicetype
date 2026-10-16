# CLAUDE.md

Briefing pour Claude Code. Ce fichier est lu automatiquement quand l'utilisateur ouvre ce repo dans VS Code et lance Claude Code.

## Contexte

VoiceType est un outil de dictee vocale local pour macOS, ecrit en Swift natif. L'utilisateur maintient la touche Fn (Globe), parle, relache : le texte est transcrit localement via whisper.cpp (GPU Metal) et colle dans l'application active.

C'est une alternative gratuite, locale et privee a Wispr Flow et Superwhisper.

L'app a ete cree par Clement Lameley. Elle est partagee a un cercle restreint d'amis. L'utilisateur qui a clone ce repo n'est probablement pas developpeur : il a juste besoin que ca marche.

Stack technique :
- Swift natif (Sources/VoiceType/)
- whisper-cli via Homebrew pour la transcription
- AVAudioEngine pour la capture micro (ffmpeg via Homebrew en secours automatique)
- VAD Silero (modele de 885 KB telecharge par l'app au lancement) pour ignorer les silences
- CGEvent tap pour la touche Fn
- NSPasteboard plus Cmd+V pour l'injection texte

## Mission de Claude Code

Aider l'utilisateur a installer VoiceType sur son Mac et a le faire fonctionner. L'utilisateur peut etre non-tech : adopte un ton patient, explicatif, jamais condescendant. Verifie chaque etape avant de passer a la suivante. Ne pretends jamais qu'une etape a reussi sans avoir vu la preuve dans le terminal ou dans le systeme.

## Procedure d'installation guidee

Quand l'utilisateur dit "installe VoiceType" ou similaire, suis cette sequence.

### Etape 0 : Verifier les prerequis basiques

```bash
sw_vers -productVersion && uname -m
```

Conditions :
- macOS 14.0 ou plus recent. Si plus ancien, dis a l'utilisateur de mettre a jour macOS via Reglages systeme > General > Mise a jour de logiciels, et stoppe la.
- Apple Silicon (arm64) recommande. Intel (x86_64) tolere mais avec performances reduites, demande confirmation a l'utilisateur avant de continuer.

Verifie que les outils Apple sont la :

```bash
xcode-select -p
```

Si echec ("error: unable to get active developer directory"), explique a l'utilisateur qu'il doit d'abord lancer `xcode-select --install`, accepter la fenetre Apple, attendre 5 a 15 minutes que ca se termine, puis revenir te voir. C'est bloquant pour la suite.

### Etape 1 : Lancer le script d'installation

```bash
./scripts/install.sh
```

Le script va :
1. Verifier macOS et l'architecture.
2. Verifier les Xcode Command Line Tools (deja installes a l'etape 0).
3. Installer Homebrew si absent (demande le mot de passe Mac).
4. Installer whisper-cpp et ffmpeg via Homebrew.
5. Telecharger le modele Whisper (1.5 GB) via curl avec reprise automatique en cas d'echec reseau. La barre de progression s'affiche dans le terminal.
6. Compiler VoiceType.
7. Copier l'app dans /Applications.

Si le script echoue, lis le message d'erreur et propose une remediation precise. Ne devine pas.

Si l'utilisateur a une connexion lente ou instable (cas frequent au Vietnam) et que le telechargement du modele echoue : relance simplement `bash scripts/install.sh`. Le script reprend ou il s'est arrete grace a `curl -C -`.

### Etape 2 : Premier lancement et Gatekeeper

```bash
open /Applications/VoiceType.app
```

Sur macOS 15 (Sequoia) et plus recent, Gatekeeper peut bloquer la premiere ouverture avec le message "VoiceType cannot be opened because the developer cannot be verified" (la signature est ad-hoc locale, pas Apple Developer).

Procedure de bypass (l'utilisateur clique, tu ne peux pas le faire pour lui) :

1. Va dans Reglages systeme > Confidentialite et securite.
2. Descend tout en bas, tu verras un message sur VoiceType avec un bouton "Ouvrir quand meme".
3. Clique. Confirme avec le mot de passe Mac.

Apres ce bypass, l'app s'ouvre normalement et ne sera plus bloquee.

### Etape 3 : Permissions macOS (manuelles, l'utilisateur clique)

Tu ne peux pas cliquer dans les Reglages systeme a la place de l'utilisateur. Guide-le verbalement, etape par etape. Trois permissions sont necessaires :

1. **Microphone** : prompt automatique au premier enregistrement. L'utilisateur clique "Autoriser".

2. **Accessibilite** : Reglages systeme > Confidentialite et securite > Accessibilite. Cliquer le cadenas en bas, taper le mot de passe Mac. Cliquer le bouton "+", choisir VoiceType dans /Applications, valider, activer l'interrupteur.

3. **Surveillance des entrees** (Input Monitoring) : meme procedure dans Reglages systeme > Confidentialite et securite > Surveillance des entrees.

Apres avoir donne les 3 permissions, l'utilisateur doit quitter VoiceType et relancer pour qu'elles prennent effet :

```bash
killall VoiceType ; open /Applications/VoiceType.app
```

### Etape 4 : Verifier que ca marche

Le modele est deja telecharge (par le script d'install). Au lancement, un petit trait gris apparait en bas au centre de l'ecran. Si la capsule affiche "Whisper introuvable" :

```bash
ls -lah ~/.voicetype/models/
tail -50 ~/.voicetype/voicetype.log
```

Demande a l'utilisateur de tester :

1. Ouvrir l'app Notes.
2. Cliquer dans le corps de la note.
3. Maintenir la touche Fn (Globe, en bas a gauche), dire "test un deux trois" en francais, relacher.
4. Le texte doit apparaitre dans Notes au bout de 1 a 2 secondes.

Si la capsule ne s'agrandit pas quand l'utilisateur maintient Fn : permission Surveillance des entrees non active.

Si la capsule s'agrandit mais que les barres restent plates : permission Micro non active, ou mauvais micro selectionne dans Reglages systeme > Son > Entree.

Si les barres bougent mais que le texte n'arrive pas : permission Accessibilite non active. Le dernier enregistrement est dans `~/.voicetype/last-recording.wav` pour diagnostiquer.

## Etats de la capsule (en bas au centre de l'ecran)

| Ce que l'utilisateur voit | Signification |
|---|---|
| Petit trait gris | Pret |
| Contour gris vide | En pause (menu de la capsule) |
| Capsule noire, point rouge, barres qui bougent | Enregistrement, les barres suivent le niveau du micro |
| Capsule noire, barres en vague | Transcription |
| Capsule avec message | Erreur ou info en clair pendant 2 secondes |

Clic sur la capsule : menu (copier la derniere dictee, pause, langue, vocabulaire, journal, quitter).

Reglages sans recompiler : `defaults write com.clement.voicetype language auto` (ou `fr`, defaut), `audioBackend ffmpeg`, `vad -bool false`.

## Troubleshooting

### La capsule ne s'affiche pas apres install

L'app ne tourne probablement pas. Verifie :

```bash
pgrep -x VoiceType
```

Si rien, lance `open /Applications/VoiceType.app`. Si l'app refuse de se lancer, voir Etape 2 (Gatekeeper).

### La touche Fn ne declenche rien

Permission Surveillance des entrees probablement manquante. Demande a l'utilisateur d'aller dans Reglages systeme > Confidentialite et securite > Surveillance des entrees, et de verifier que VoiceType est dans la liste et active.

Apres modification : `killall VoiceType ; open /Applications/VoiceType.app`.

### Le texte n'est pas colle dans l'app cible

Permission Accessibilite probablement manquante. Meme procedure que ci-dessus.

Si le probleme persiste dans une app specifique (Electron, Slack desktop, certains navigateurs), c'est un probleme de timing du paste. C'est une limitation connue.

### L'app crash au lancement

Verifie les rapports de crash :

```bash
ls -lt ~/Library/Logs/DiagnosticReports/VoiceType* 2> /dev/null | head -3
```

Et les logs de l'app :

```bash
tail -50 ~/.voicetype/voicetype.log
```

Cause frequente : `whisper-cli` ou `ffmpeg` manquants apres une desinstallation accidentelle de Homebrew. Verifie :

```bash
which whisper-cli ffmpeg
```

Si l'un manque : `brew install whisper-cpp ffmpeg`.

### Le modele n'est pas la

Si `~/.voicetype/models/ggml-large-v3-turbo.bin` n'existe pas ou fait moins de 1.5 GB :

```bash
bash scripts/install.sh
```

Le script reprend le telechargement la ou il s'est arrete grace a `curl -C -`. Pas besoin de tout refaire.

Telechargement manuel direct possible aussi :

```bash
mkdir -p ~/.voicetype/models
curl -L --retry 5 -C - --progress-bar \
  -o ~/.voicetype/models/ggml-large-v3-turbo.bin \
  "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin"
```

### Permissions perdues apres une mise a jour

Si l'utilisateur a fait `git pull` puis `bash scripts/install.sh`, les permissions TCC peuvent etre revoquees par macOS car la signature ad-hoc de l'app a change. Procedure de recuperation :

1. Reglages systeme > Confidentialite et securite > Accessibilite : selectionner VoiceType, cliquer "-" pour le retirer.
2. Idem pour Surveillance des entrees.
3. Relancer VoiceType : `open /Applications/VoiceType.app`.
4. Re-ajouter VoiceType dans les 2 listes via le bouton "+".

C'est une limitation de macOS, pas un bug. Apple Developer ID a 99 dollars par an stabiliserait ca, mais Clement n'a pas pris cet abonnement.

## Vocabulaire personnalise (optionnel)

L'utilisateur peut ajouter des noms propres ou termes techniques que Whisper devrait connaitre :

```bash
mkdir -p ~/.voicetype && nano ~/.voicetype/vocabulary.txt
```

Format : un mot ou une phrase par ligne. Lignes commencant par `#` sont des commentaires.

Effet immediat a la prochaine transcription, pas besoin de redemarrer l'app.

## Posture et limites

- Ne tente jamais de cliquer dans les Reglages systeme a la place de l'utilisateur. Donne les instructions verbales claires, eventuellement avec le chemin exact des panneaux.
- Ne lance pas `sudo` sans expliquer ce que ca fait et pourquoi. Le script d'install ne demande sudo qu'une seule fois (pour Homebrew).
- Si une etape echoue, montre l'erreur exacte et propose une remediation. Ne devine pas, ne suppose pas que "ca devrait marcher quand meme".
- L'utilisateur n'est pas developpeur : evite le jargon. Prefere "la petite capsule en bas au centre de l'ecran" plutot que "le NSPanel flottant".
- Pour tout bug non couvert ici, suggere a l'utilisateur d'ouvrir une issue sur https://github.com/garryvision/voicetype/issues ou de contacter Clement directement avec une capture d'ecran et le contenu du log `~/.voicetype/voicetype.log`.

## Pour aller plus loin

Le code source est dans `Sources/VoiceType/`. L'app est volontairement minimaliste (~750 lignes Swift). Tout est documente dans le code.
