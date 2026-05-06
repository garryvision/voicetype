# Installer VoiceType

VoiceType est un outil de dictee vocale local pour macOS. Tu maintiens la touche Fn (Globe, en bas a gauche du clavier), tu parles, tu relaches : le texte arrive dans l'application ou ton curseur est. Toute la transcription se passe sur ton Mac, sans connexion internet (sauf le telechargement initial du modele).

Compte 15 a 25 minutes pour l'installation complete : 5 minutes de commandes, 10 a 15 minutes de telechargement automatique du modele, 5 minutes pour autoriser les permissions.

## Avant de commencer

- Mac sous macOS 14 (Sonoma) ou plus recent. Verifie via Menu Pomme > A propos de ce Mac.
- Apple Silicon recommande (M1, M2, M3, M4). Intel fonctionne mais c'est plus lent.
- 3 GB d'espace disque libre (1.5 GB pour le modele Whisper, le reste pour les outils).
- Une connexion internet stable au premier lancement (telechargement du modele).
- Un micro (le micro interne du Mac suffit, externe c'est mieux).

## Installation

Tu as deux options. La premiere est plus simple si tu utilises VS Code et Claude Code.

### Option 1 : Avec Claude Code (recommandee)

1. Telecharge le code source dans le terminal :

   ```
   cd ~/Downloads
   git clone https://github.com/garryvision/voicetype.git
   ```

2. Ouvre le dossier dans VS Code :

   ```
   code ~/Downloads/voicetype
   ```

3. Lance Claude Code dans VS Code (raccourci Cmd+Esc ou via le menu).

4. Tape simplement : `installe VoiceType`

   Claude Code va lire le fichier `CLAUDE.md` du repo et te guider etape par etape. Il te dira quand cliquer ou. Si quelque chose plante, demande lui de t'aider.

### Option 2 : A la main dans le terminal

Ouvre l'application Terminal (Cmd + Espace, tape "Terminal", Entree).

Copie cette commande, colle dans le Terminal, Entree :

```
cd ~/Downloads && git clone https://github.com/garryvision/voicetype.git && cd voicetype && bash scripts/install.sh
```

Le script va :

1. Verifier ton Mac et ton macOS.
2. Te demander d'installer les Xcode Command Line Tools si tu ne les as pas (une boite Apple s'ouvre, clique "Installer", attends, relance la commande ci-dessus).
3. Installer Homebrew si tu ne l'as pas. Ton mot de passe Mac sera demande.
4. Installer les outils dont VoiceType a besoin (whisper-cpp, ffmpeg).
5. Compiler VoiceType et l'installer dans Applications.

Compte 5 a 10 minutes.

## Autoriser les permissions

VoiceType a besoin de 3 permissions macOS. Cette etape est manuelle, tu dois cliquer toi meme.

### 1. Microphone

Lance l'app :

```
open /Applications/VoiceType.app
```

Une boite Apple va demander l'acces au microphone : clique "Autoriser".

Si tu rates le prompt : Reglages systeme > Confidentialite et securite > Microphone, active la ligne VoiceType.

### 2. Accessibilite

Reglages systeme > Confidentialite et securite > Accessibilite.

Clique le cadenas en bas a gauche, tape ton mot de passe Mac. Clique le bouton "+", choisis VoiceType dans Applications, valide. Active l'interrupteur a cote de VoiceType.

### 3. Surveillance des entrees

Reglages systeme > Confidentialite et securite > Surveillance des entrees.

Meme procedure : "+", choisir VoiceType, activer.

### Relancer

Pour que les 3 permissions prennent effet, quitte VoiceType et relance le :

```
killall VoiceType
open /Applications/VoiceType.app
```

## Premier lancement

A ce stade tu vois un petit dot (point) en haut a droite de l'ecran. Au tout premier lancement il reste **gris** : VoiceType telecharge le modele de transcription Whisper, environ 1.5 GB. Compte 5 a 15 minutes selon ta connexion.

Quand le dot devient **vert**, c'est pret. Tu peux dicter.

## Utiliser au quotidien

Place ton curseur la ou tu veux le texte (Mail, Notes, navigateur, Slack, n'importe quelle app texte).

Maintiens **Fn** (touche Globe en bas a gauche du clavier).
Parle.
Relache.

Le texte apparait au bout de 0.6 a 1 seconde. Auto detect francais et anglais.

### Etats du dot

| Couleur | Signification |
|---|---|
| Gris | Chargement ou telechargement du modele |
| Vert | Pret |
| Rouge pulsant | Enregistrement en cours |
| Orange | Transcription en cours |
| Violet | Erreur (3 secondes puis retour vert) |

## Vocabulaire personnalise (optionnel)

Si tu utilises souvent des noms propres ou termes que Whisper ne reconnait pas, ajoute les a un fichier de vocabulaire :

```
mkdir -p ~/.voicetype
nano ~/.voicetype/vocabulary.txt
```

Tape un mot ou une phrase par ligne. Sauvegarde avec Ctrl+O, Entree, puis Ctrl+X.

Les ajouts sont pris en compte a la prochaine transcription, sans redemarrage.

## Desinstaller

```
cd ~/Downloads/voicetype
bash scripts/uninstall.sh
```

L'app, les modeles et les caches sont supprimes. Homebrew et ses paquets restent (ils peuvent te servir a d'autres outils).

Pour retirer aussi les permissions : Reglages systeme > Confidentialite et securite > Microphone / Accessibilite / Surveillance des entrees, retirer VoiceType de chaque liste.

## Si ca plante

Le plus simple : ouvre Claude Code dans le dossier du repo et explique lui ton probleme. Il a tout le contexte (fichier `CLAUDE.md`).

Sinon, ping Clement directement.

## Mises a jour

Si Clement publie une mise a jour :

```
cd ~/Downloads/voicetype
git pull
bash scripts/install.sh
```

Les permissions macOS peuvent etre a redonner apres une mise a jour. Suis la procedure de la section "Autoriser les permissions".
