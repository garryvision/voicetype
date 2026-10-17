# Installer VoiceType

VoiceType te permet de dicter a voix haute dans n'importe quelle application Mac (Notes, Mail, Slack, navigateur, code editor). Tu maintiens une touche, tu parles, le texte s'ecrit la ou ton curseur est. Tout reste sur ton Mac, rien ne part sur internet (sauf le telechargement initial du modele de transcription). C'est une alternative gratuite a Wispr Flow et Superwhisper, qui sont autour de 15 euros par mois.

Compte 30 a 45 minutes pour la premiere installation : 5 a 10 minutes de commandes, 15 a 30 minutes de telechargements automatiques (selon ta connexion), 5 minutes pour autoriser 3 permissions macOS. Tu peux laisser tourner et faire autre chose.

Tu ne peux rien casser. Si tu bloques quelque part, ping Clement avec une capture d'ecran, on debloque ensemble. La desinstallation est propre, en une commande (voir tout en bas de cette page).

## Pre-requis

- Mac sous macOS 14 (Sonoma) ou plus recent. Verifie : Menu Pomme > A propos de ce Mac.
- Apple Silicon recommande (M1, M2, M3, M4). Intel fonctionne mais c'est plus lent.
- 4 GB d'espace disque libre (1.5 GB pour le modele de transcription, le reste pour les outils Apple et Homebrew).
- Une connexion internet stable.
- Un micro (le micro interne du Mac suffit, externe c'est mieux pour la qualite).

## Avant de commencer : installer les outils Apple

Cette etape est manuelle, gratuite, et indispensable. Elle prend 5 a 15 minutes selon ta connexion.

Ouvre l'application Terminal (touche Cmd, qui est la touche commande en bas a cote de la barre espace, plus la barre Espace, tape "Terminal", appuie Entree).

Colle cette commande, appuie Entree :

```
xcode-select --install
```

Une fenetre Apple s'ouvre. Clique le bouton bleu **Installer**, puis Accepter sur les conditions. Attends que le telechargement se termine. Quand la fenetre Apple disparait, c'est bon.

Si le terminal te dit "command line tools are already installed", c'est qu'ils sont deja la. Tu peux passer a la suite.

## Installation : 2 options

Choisis selon ce que tu utilises au quotidien.

### Option 1 : Avec Claude Code (le plus simple)

Si tu utilises VS Code et Claude Code dans ton travail, c'est le chemin le plus court : Claude Code va lire les instructions du projet et te tenir la main etape par etape.

1. Dans le Terminal, telecharge le code source :

   ```
   cd ~/Downloads
   git clone https://github.com/garryvision/voicetype.git
   ```

2. Ouvre le dossier dans VS Code. Soit via le terminal :

   ```
   code ~/Downloads/voicetype
   ```

   Si la commande `code` n'est pas reconnue (`command not found: code`) : ouvre VS Code a la main, puis menu **File** > **Open Folder**, navigue jusqu'a Downloads/voicetype, clique Ouvrir.

3. Dans VS Code, lance Claude Code (raccourci Cmd+Esc, ou via la palette de commandes Cmd+Shift+P et taper "Claude Code").

4. Tape simplement : `installe VoiceType`

   Claude Code va lire le fichier `CLAUDE.md` du projet et te guider de bout en bout. Si quelque chose plante, demande lui simplement de t'aider.

### Option 2 : A la main dans le Terminal

Si tu n'utilises pas Claude Code, suis cette procedure manuelle. Elle marche tout autant.

Dans le Terminal, colle ces commandes une par une, en appuyant Entree apres chaque ligne :

```
cd ~/Downloads
git clone https://github.com/garryvision/voicetype.git
cd voicetype
bash scripts/install.sh
```

Le script va :

1. Verifier ton Mac et ton macOS.
2. Verifier les outils Apple (deja installes a l'etape "Avant de commencer").
3. Installer Homebrew si tu ne l'as pas. Ton mot de passe Mac sera demande.
4. Installer les outils dont VoiceType a besoin : `whisper-cpp` pour la transcription, `ffmpeg` en secours pour le micro.
5. Telecharger le modele de transcription (1.5 GB). Une barre de progression s'affiche. Si la connexion coupe, relance la commande `bash scripts/install.sh`, le telechargement reprendra ou il s'est arrete.
6. Compiler VoiceType et l'installer dans Applications.

Compte 15 a 35 minutes pour cette etape.

## Autoriser les 3 permissions macOS

Trois permissions sont necessaires. Cette etape est manuelle, tu dois cliquer toi meme.

### Etape 1 : lance l'app

Dans le Terminal :

```
open /Applications/VoiceType.app
```

Si macOS te dit "VoiceType cannot be opened because the developer cannot be verified" (frequent sur macOS 15 et plus recent) : va dans **Reglages systeme** > **Confidentialite et securite**, descend tout en bas, tu verras un message sur VoiceType avec un bouton **Ouvrir quand meme**. Clique. Confirme avec ton mot de passe Mac. L'app va ensuite se lancer.

### Permission 1 : Microphone

Une fenetre Apple va apparaitre automatiquement : "VoiceType veut acceder au microphone". Clique **Autoriser**.

Si tu rates le prompt : Reglages systeme > Confidentialite et securite > Microphone, active la ligne VoiceType.

### Permission 2 : Accessibilite

Reglages systeme > Confidentialite et securite > **Accessibilite**.

Clique le cadenas en bas a gauche, tape ton mot de passe Mac. Clique le bouton **+** (au-dessus de la liste), choisis **VoiceType** dans Applications, clique Ouvrir. Verifie que l'interrupteur a cote de VoiceType est sur on (bleu).

### Permission 3 : Surveillance des entrees (Input Monitoring)

Reglages systeme > Confidentialite et securite > **Surveillance des entrees**.

Meme procedure : cadenas, mot de passe, **+**, choisir VoiceType, activer.

### Etape finale : quitte et relance

Pour que les 3 permissions prennent effet, dans le Terminal :

```
killall VoiceType
open /Applications/VoiceType.app
```

(`killall VoiceType` ferme proprement l'application, c'est normal malgre le mot.)

## Utiliser au quotidien

Une petite capsule apparait en bas au centre de l'ecran, au-dessus du Dock. Etats :

| Ce que tu vois | Signification |
|---|---|
| Petit trait gris discret | Pret, tu peux parler |
| Capsule noire avec point rouge et barres qui bougent | Enregistrement : les barres suivent ta voix, si elles restent plates le micro ne t'entend pas |
| Capsule noire avec barres en vague | Transcription en cours |
| Capsule avec un message (ex : "Micro indisponible") | Erreur, explique en clair pendant 2 secondes |

Clique sur la capsule pour ouvrir le menu : copier la derniere dictee, pause, langue, vocabulaire, journal, quitter.

Pour dicter :

1. Place ton curseur la ou tu veux le texte (Mail, Notes, navigateur, Slack, ...).
2. Maintiens la touche **Fn** (touche Globe en bas a gauche du clavier).
3. Parle.
4. Relache. Le texte apparait au bout de 1 a 2 secondes.

Astuce : Fn + une autre touche (fleches, suppr) n'enregistre rien, c'est un raccourci.

Francais par defaut. Pour l'anglais ou un melange de langues : menu de la capsule > "Detecter la langue automatiquement".

## Vocabulaire personnalise (optionnel)

Si tu utilises souvent des noms propres ou termes techniques que Whisper ne reconnait pas, ajoute les a un fichier de vocabulaire :

```
mkdir -p ~/.voicetype
nano ~/.voicetype/vocabulary.txt
```

Tape un mot ou une phrase par ligne. Sauvegarde avec **Ctrl+O**, Entree, puis **Ctrl+X** pour quitter nano.

Effet immediat a la prochaine transcription.

## Si ca plante

### La capsule affiche "Whisper introuvable" ou rien ne se transcrit

Si le probleme persiste apres une relance, ouvre Claude Code (ou ping Clement) et envoie le contenu du log :

```
tail -50 ~/.voicetype/voicetype.log
```

### La touche Fn ne declenche rien (la capsule ne s'agrandit pas quand tu maintiens)

La permission **Surveillance des entrees** n'est probablement pas active. Retourne dans Reglages systeme > Confidentialite et securite > Surveillance des entrees, verifie que VoiceType est dans la liste avec l'interrupteur sur on.

Quitte et relance :

```
killall VoiceType ; open /Applications/VoiceType.app
```

### Le texte ne s'ecrit pas dans l'app cible

La permission **Accessibilite** n'est probablement pas active. Meme procedure que ci-dessus dans la section Accessibilite.

### Tout autre cas

Le plus simple : ouvre Claude Code dans le dossier du repo et explique lui ton probleme. Il a tout le contexte (fichier `CLAUDE.md` du projet).

Sinon, ping Clement directement avec une capture d'ecran et / ou le contenu du log :

```
tail -100 ~/.voicetype/voicetype.log
```

## Mises a jour

Si Clement publie une mise a jour :

```
cd ~/Downloads/voicetype
git pull
bash scripts/install.sh
```

Apres chaque mise a jour, les permissions macOS sont a redonner (les interrupteurs restent allumes mais ne marchent plus). Procedure :

1. Reglages systeme > Confidentialite et securite > Accessibilite : retire VoiceType (selectionne, bouton -).
2. Idem pour Surveillance des entrees.
3. Relance VoiceType (`killall VoiceType ; open /Applications/VoiceType.app`). Si macOS redemande le micro, clique Autoriser.
4. Re-ajoute VoiceType dans les 2 listes via le bouton +, puis relance une derniere fois.

C'est une limitation de macOS quand l'application change de signature, pas un bug.

### Revenir a la version precedente

Si une mise a jour pose probleme, reviens a la 0.2.0 :

```
cd ~/Downloads/voicetype
git checkout v0.2.0
bash scripts/install.sh
```

Pour revenir ensuite a la derniere version : `git checkout main && git pull && bash scripts/install.sh`.

## Desinstaller

Une seule commande :

```
cd ~/Downloads/voicetype
bash scripts/uninstall.sh
```

L'app, le modele et les caches sont supprimes. Homebrew et ses paquets restent (ils peuvent te servir a d'autres outils).

Pour retirer aussi les permissions : Reglages systeme > Confidentialite et securite, et retire VoiceType de Microphone, Accessibilite, et Surveillance des entrees.
