# CLAUDE.md

Briefing pour Claude Code. Ce fichier est lu automatiquement quand l'utilisateur ouvre ce repo dans VS Code et lance Claude Code.

## Contexte

VoiceType est un outil de dictee vocale local pour macOS, ecrit en Swift natif. L'utilisateur maintient la touche Fn (Globe), parle, relache : le texte est transcrit localement via whisper.cpp (GPU Metal) et colle dans l'application active.

C'est une alternative gratuite, locale et privee a Wispr Flow et Superwhisper.

L'app a ete cree par Clement Lameley. Elle est partagee a un cercle restreint d'amis. L'utilisateur qui a clone ce repo n'est probablement pas developpeur : il a juste besoin que ca marche.

Stack technique :
- Swift natif (Sources/VoiceType/)
- whisper-cli via Homebrew pour la transcription
- ffmpeg via Homebrew pour la capture micro
- CGEvent tap pour la touche Fn
- NSPasteboard plus Cmd+V pour l'injection texte

## Mission de Claude Code

Aider l'utilisateur a installer VoiceType sur son Mac et a le faire fonctionner. L'utilisateur peut etre non-tech : adopte un ton patient, explicatif, jamais condescendant. Verifie chaque etape avant de passer a la suivante.

## Procedure d'installation guidee

Quand l'utilisateur dit "installe VoiceType" ou similaire, suis cette sequence.

### Etape 1 : Verifier les prerequis

Lance dans le terminal :

```bash
sw_vers -productVersion && uname -m
```

Conditions :
- macOS 14.0 ou plus recent.
- Apple Silicon (arm64) recommande. Intel toleré avec performances reduites.

Si macOS trop ancien : explique a l'utilisateur qu'il doit mettre a jour via Reglages systeme > General > Mise a jour de logiciels. Stoppe la.

### Etape 2 : Lancer le script d'installation

```bash
./scripts/install.sh
```

Le script va :
1. Verifier macOS et l'architecture.
2. Installer Xcode Command Line Tools si absent (boite de dialogue Apple, l'utilisateur doit cliquer "Installer" puis attendre puis relancer le script).
3. Installer Homebrew si absent (demande le mot de passe Mac).
4. Installer whisper-cpp et ffmpeg via Homebrew.
5. Compiler VoiceType.
6. Copier l'app dans /Applications.

Si le script echoue, lis le message d'erreur et propose une remediation precise. Ne devine pas.

### Etape 3 : Permissions macOS (manuelles, l'utilisateur clique)

Tu ne peux pas cliquer dans les Reglages systeme a la place de l'utilisateur. Guide-le verbalement, etape par etape. Trois permissions sont necessaires :

1. **Microphone** : prompt automatique au premier lancement. L'utilisateur clique "Autoriser".

2. **Accessibilite** : Reglages systeme > Confidentialite et securite > Accessibilite. Cliquer le cadenas en bas, taper le mot de passe Mac. Cliquer le bouton "+", choisir VoiceType dans /Applications, valider, activer l'interrupteur.

3. **Surveillance des entrees** (Input Monitoring) : meme procedure dans Reglages systeme > Confidentialite et securite > Surveillance des entrees.

Apres avoir donne les 3 permissions, l'utilisateur doit quitter VoiceType (`killall VoiceType` dans le terminal, ou clic droit sur le dot) puis relancer (`open /Applications/VoiceType.app`). Les permissions prennent effet au lancement suivant.

### Etape 4 : Premier lancement et telechargement du modele

Au tout premier lancement, VoiceType telecharge le modele Whisper (1.5 GB, large-v3-turbo) dans `~/.voicetype/models/`. Cela prend 5 a 15 minutes selon la connexion.

Pendant le telechargement, le dot (petit point en haut a droite de l'ecran) reste gris. Quand il devient vert, l'app est prete.

Pour verifier la progression :

```bash
ls -lah ~/.voicetype/models/ 2> /dev/null
```

Si le fichier `ggml-large-v3-turbo.bin` apparait et grossit, c'est en cours. S'il y a 0 fichier au bout de 2 minutes, voir Troubleshooting plus bas.

### Etape 5 : Utilisation

L'utilisateur place son curseur dans une app texte (Notes, Mail, navigateur, ...), maintient la touche Fn (Globe, en bas a gauche du clavier), parle, relache. Le texte arrive 0.6 a 1 seconde apres avoir relache.

Etats du dot :
- Gris : chargement ou telechargement modele.
- Vert : pret.
- Rouge pulsant : enregistrement en cours.
- Orange : transcription en cours.
- Violet : erreur (3 secondes puis retour vert).

## Troubleshooting

### Le dot ne s'affiche pas apres install

L'app ne tourne probablement pas. Verifier :

```bash
ps aux | grep VoiceType | grep -v grep
```

Si rien : lance `open /Applications/VoiceType.app`.

Si l'app tourne mais pas de dot visible : c'est rare. Regarde les logs :

```bash
tail -50 ~/.voicetype/voicetype.log
```

### La touche Fn ne declenche rien

Permission "Surveillance des entrees" probablement manquante. Demande a l'utilisateur d'aller dans Reglages systeme > Confidentialite et securite > Surveillance des entrees, et de verifier que VoiceType est dans la liste et active.

Apres modification : `killall VoiceType ; open /Applications/VoiceType.app`.

### Le texte n'est pas colle dans l'app cible

Permission "Accessibilite" probablement manquante. Meme procedure que ci-dessus dans la section Accessibilite.

Si le probleme persiste dans une app specifique (Electron, Slack, navigateur), cela peut venir d'un delai de paste trop court. C'est documenté comme limitation.

### L'app crash au lancement

Verifie les rapports de crash :

```bash
ls -lt ~/Library/Logs/DiagnosticReports/VoiceType* 2> /dev/null | head -3
```

Et les logs de l'app :

```bash
tail -50 ~/.voicetype/voicetype.log
```

Cause frequente : whisper-cli ou ffmpeg manquants. Verifie :

```bash
which whisper-cli ffmpeg
```

Si l'un manque : `brew install whisper-cpp ffmpeg`.

### Le modele ne se telecharge pas

Si le dot reste gris plus de 15 minutes :

```bash
ls -lah ~/.voicetype/models/
```

S'il n'y a pas de fichier `.bin` qui grossit : connexion internet ? espace disque ?

Telechargement manuel possible :

```bash
mkdir -p ~/.voicetype/models
curl -L --progress-bar -o ~/.voicetype/models/ggml-large-v3-turbo.bin \
  "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin"
```

Puis relance VoiceType.

### Permissions perdues apres une mise a jour

Si l'utilisateur a fait `git pull` puis `./scripts/install.sh`, les permissions TCC peuvent etre revoquees par macOS car la signature de l'app a change. Procedure de recuperation :

1. Reglages systeme > Confidentialite et securite > Accessibilite : retirer VoiceType (bouton -).
2. Idem pour Surveillance des entrees.
3. Relancer VoiceType : `open /Applications/VoiceType.app`.
4. Re-ajouter VoiceType dans les 2 listes via le bouton +.

## Vocabulaire personnalise (optionnel)

L'utilisateur peut ajouter des noms propres ou termes techniques que Whisper devrait connaitre :

```bash
mkdir -p ~/.voicetype && nano ~/.voicetype/vocabulary.txt
```

Format : un mot ou une phrase par ligne. Lignes commencant par `#` sont des commentaires.

Effet immediat a la prochaine transcription, pas besoin de redemarrer l'app.

## Posture et limites

- Ne tente jamais de cliquer dans les Reglages systeme a la place de l'utilisateur. Donne les instructions verbales claires.
- Ne lance pas `sudo` sans expliquer ce que ca fait et pourquoi.
- Si une etape echoue, montre l'erreur exacte et propose une remediation. Ne devine pas.
- L'utilisateur n'est pas developpeur : evite le jargon, preferer "le petit point a droite de l'ecran" plutot que "le NSWindow flottant".
- Pour tout bug non couvert ici, suggere a l'utilisateur d'ouvrir une issue sur https://github.com/garryvision/voicetype/issues ou de contacter Clement directement.

## Pour aller plus loin

Source du projet et historique de developpement : voir le repo GitHub. L'app est volontairement minimaliste (~750 lignes Swift). Toutes les ameliorations sont les bienvenues.
