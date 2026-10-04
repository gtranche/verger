# Verger

## En une phrase

**Verger** est l'interface graphique macOS qui pilote **Cidre** : ta bibliothèque de jeux, où tu installes, règles et lances tes jeux Windows (via Cidre) comme tes jeux natifs — sans jamais toucher à la console Steam ni à une ligne de commande.

Cidre = le moteur (FEX + Wine + DXVK + KosmicKrisp). Verger = le verger où poussent les jeux : la vitrine, le catalogue, les réglages, le bouton « Jouer ».

## Pourquoi un dépôt séparé (le point qui commande tout)

Le runtime Cidre pèse des **gigas** (Wine arm64, Mesa/KosmicKrisp, DXVK, FEX…). L'UI, elle, change **souvent** et pèse **quelques Mo**. Les mélanger obligerait à re-pousser / re-télécharger tout le runtime à chaque correction d'un bouton.

→ **Verger est un dépôt et un binaire indépendants.** Il ne contient aucun binaire de runtime. Il **détecte / installe / met à jour Cidre séparément** (voir « Installer et mettre à jour Cidre »). On peut patcher l'UI 10 fois par jour sans que personne ne retélécharge un seul octet de Wine.

Conséquence d'archi : la frontière Verger ↔ Cidre est un **contrat stable** (la CLI `cidre`), pas un couplage de code.

## Le contrat Verger ↔ Cidre (la CLI)

Verger ne réimplémente rien : il appelle la CLI `cidre` et lit/écrit des fichiers de config que `cidre` consomme.

| Besoin UI | Commande Cidre |
|---|---|
| Lister les jeux (plateforme, mode, installé ?) | `cidre list --json` |
| Fiche d'un jeu (taille, chemin, options actives) | `cidre info <id> --json` |
| Lancer un jeu | `cidre play <id>` |
| Régler une option de lancement d'un jeu | `cidre set <id> <option> <valeur>` |
| Ne plus forcer une option pour un jeu | `cidre unset <id> [option]` |
| Réglages généraux (tous les jeux) | `cidre options --json`, `cidre set defaut …`, `cidre unset defaut …` |
| Compte Steam et état de la session | `cidre session --json` |
| Se déconnecter de Steam | `cidre logout` |
| Les jeux Steam du compte, installés ou non | `cidre library --json [--refresh]` |
| Télécharger ou mettre à jour un jeu Windows hors client | `cidre dl <appid> [windows\|macos]` |
| Les jeux installés dont une version plus récente est publiée | `cidre updates --json [--refresh]` |
| Mémoriser la session Steam (au Terminal) | `cidre login` |
| Ajouter un jeu non-Steam | `cidre add <jeu.exe> [nom] --json` |
| Lancer un installeur Windows | `cidre run <fichier.exe>` |
| Où l'installeur a déposé le jeu | `cidre prefix` |
| Retirer un jeu non-Steam / désinstaller un jeu du dossier Cidre | `cidre rm <id>` |
| État du runtime (version, prérequis, jeu en cours) | `cidre status --json` |
| Configurer le runtime après installation ou mise à jour | `cidre setup` |
| Sauvegardes (iCloud) | `cidre sync <appid\|all> [backup\|restore]` |

Un jeu a un `id` : son appid Steam, ou `local-…` pour un jeu non-Steam.

Verger parse ce JSON (`Verger/CidreBridge`) ; il ne scrape jamais la sortie texte. Une valeur qu'il ne connaît pas (CLI plus récente) retombe sur une valeur neutre au lieu de faire tomber la bibliothèque.

Verger cherche la commande `cidre` dans cet ordre : le chemin choisi dans l'app, la variable `VERGER_CIDRE`, le Cidre qu'il a installé lui-même (`~/Library/Application Support/Cidre/cidre/cidre`), puis le `PATH`.

## Installer et mettre à jour Cidre

C'est Verger qui s'en charge ; il n'y a pas d'installeur à lancer à côté.

- **Installation.** Sans Cidre, Verger propose de l'installer : il télécharge l'archive `cidre-runtime.tar.xz` de la dernière release de Cidre (environ 400 Mo), la décompresse dans `~/Library/Application Support/Cidre/cidre`, puis lance `cidre setup`, qui prépare le pilote Vulkan, le préfixe Wine, DXVK, FEX, le pont Steam et SteamCMD. La configuration voyage avec le runtime : Verger n'en connaît pas les étapes, il les affiche.
- **Mise à jour.** Au lancement, Verger compare la version installée (`cidre status`) à la dernière release et propose la mise à jour dans un bandeau. Elle décompresse par-dessus l'installation : les jeux, les sauvegardes (le préfixe Wine n'est pas dans l'archive) et `profils.toml` restent en place. Elle est refusée tant qu'un jeu tourne.
- **Aucun prérequis.** À partir de Cidre 1.2.0, le runtime embarque les bibliothèques dont il dépend (zstd, SPIRV-Tools, FreeType, libpng) : ni Homebrew ni Terminal. Avec un runtime plus ancien, Verger signale celles qui manquent.

Un dépôt de développement de Cidre (sans fichier `VERSION`) n'est jamais mis à jour par Verger. `VERGER_RUNTIME_URL` fait installer une archive donnée (fichier local ou miroir) au lieu de la dernière release, et `VERGER_CIDRE_HOME` change le dossier d'installation : pour essayer une version avant de la publier.

## Fonctionnalités

### 1. Bibliothèque (le verger)
Grille des jeux possédés / installés, avec pour chacun : jaquette, plateforme (**natif** vs **Cidre/Windows**), état (installé / à télécharger / MAJ dispo), taille, dernier lancement. Bouton **Installer** (`cidre dl`) et **Jouer** (`cidre play`).

### 2. Installer un jeu
Le bouton **+** de la barre d'outils.

**Un jeu Steam de ta bibliothèque.** Verger liste les jeux que possède ton compte (`cidre library`) et ne propose que ceux qui ne sont pas installés. La version Windows se télécharge dans le dossier Cidre (`cidre dl`), hors du client Steam, avec son avancement et un bouton d'arrêt ; un téléchargement arrêté reprend où il en était. Quand le jeu a une version macOS, c'est elle qui est proposée d'abord, et c'est Steam qui l'installe.

La liste vient de la session SteamCMD mémorisée. S'il n'y en a pas, Verger ouvre sa fenêtre de connexion (voir « Connexion à Steam »).

**Un jeu non-Steam.** « Ajouter un jeu non-Steam… » : tu choisis son `.exe`, il entre dans la bibliothèque et se lance par Cidre ; ses fichiers restent où ils sont. Si le jeu arrive sous forme d'installeur (GOG, itch…), « Lancer un installeur Windows… » l'exécute d'abord ; le sélecteur s'ouvre ensuite sur le disque C: du préfixe, là où il a déposé le jeu.

**Mises à jour des jeux.** Au lancement (et au bouton Actualiser), Verger compare le build installé de chaque jeu Steam au dernier publié (`cidre updates`, une information publique lue sans compte). Un jeu en retard porte l'étiquette « Mise à jour » ; depuis sa fiche, un jeu du dossier Cidre se met à jour par Verger (`cidre dl`, avec avancement), un jeu du client Steam par Steam.

**Désinstaller.** Depuis la fiche du jeu : un jeu non-Steam est retiré de la bibliothèque (fichiers intacts), un jeu du dossier Cidre est supprimé du disque après confirmation. Un jeu du client Steam est désinstallé par Steam, que Verger ouvre sur sa demande de confirmation.

### 3. Options de lancement par jeu  ← demande explicite
Un panneau de réglages **par jeu**, avec des interrupteurs pour **activer/désactiver des fonctionnalités**. Chaque interrupteur mappe une variable que `cidre play` lit déjà :

| Réglage UI | Variable / arg Cidre | Effet |
|---|---|---|
| Perf CPU (ordre mémoire relâché) | `CIDRE_TSO=0` (`FEX_TSOENABLED`) | gros gain CPU, risque de course — **off par défaut** |
| Vsync | `CIDRE_VSYNC=0` (`dxgi.syncInterval=0`) | enlève le plafond vblank (40→84 fps mesuré DREDGE) |
| HUD fps/GPU | `CIDRE_HUD=1` (`DXVK_HUD`, `MTL_HUD`) | overlay de perf pour régler |
| Compilation shaders async | `DXVK_ASYNC=1` + `numCompilerThreads` | tue le stutter (ex. VT2) |
| Anti-triche permissif | `-eac-untrusted` | realm Modded (EAC = mur en ligne) |
| Correctif LuaJIT | `PROTON_OUVERT_LUAJIT=1` | requis VT2 |
| Plein écran / encoche | (à venir côté Cidre) | couvrir l'encoche comme le natif |

Trois niveaux, du plus faible au plus fort : ce que Cidre livre, tes **réglages généraux** (Réglages → Options, pour tous les jeux), et ce que tu **forces pour un jeu** dans sa fiche. Chaque interrupteur dit ce qu'il fait gagner et ce qu'il risque ; une pastille marque ce qui est réglé à ce niveau, et la flèche à côté y renonce. Le changement s'applique au prochain lancement.

**Modèle :** un profil **par défaut** + des **surcharges par jeu**, dans un fichier de données que `cidre play` lit et que Verger écrit par `cidre set` : `~/Library/Application Support/Cidre/profils.toml`.

```toml
[defaut]
hud = true

[552500]            # Vermintide 2
fils_compilation = 6
```

Clés : `tso`, `vsync`, `hud`, `async`, `fils_compilation`, `eac_untrusted`, `luajit`. Cidre livre ses propres réglages par jeu (`outil-steam/profils.toml`) ; le fichier utilisateur les surcharge clé par clé, et la section d'un jeu l'emporte sur `[defaut]`. Format volontairement plat (sections + `cle = valeur`), pour rester lisible par un script `sh`.

### 4. Connexion à Steam
Une fenêtre dans Verger, pas de Terminal (bouton **+**, « Connexion à Steam… », ou d'elle-même quand la session manque) : identifiant, mot de passe, puis ce que Steam Guard demande — valider dans l'appli mobile, ou taper un code.

Verger ne garde ni mot de passe ni jeton. Il prête un terminal à SteamCMD (`cidre login`), l'outil de Valve, lui relaie la saisie et l'oublie aussitôt ; c'est SteamCMD qui mémorise la session, dans un dossier à lui (`~/Library/Application Support/Cidre/steamcmd`) que le client Steam n'efface pas. Sans session, Cidre s'arrête et le dit : il ne laisse jamais SteamCMD tenter un mot de passe vide. La sortie brute de SteamCMD n'est jamais affichée ni journalisée, seulement la raison d'un refus (« mot de passe incorrect », « trop de tentatives »).

**Cible : la connexion par QR code**, sans mot de passe du tout. SteamCMD ne sait pas la faire ; elle demande de le remplacer par un moteur bâti sur SteamKit (DepotDownloader) pour télécharger les jeux et lire la bibliothèque. À faire.

> Pourquoi pas steamctl : `python-steam` renvoie « Invalid Password » sur l'ancien flux de login (déprécié par Steam). Abandonné.

### 5. Réglages (⌘,)
- **Cidre** : la version installée et la dernière publiée, l'emplacement, l'état de chaque pièce (runtime, préfixe Wine, SteamCMD, bibliothèques), la mise à jour et la reconfiguration (`cidre setup`).
- **Steam** : le compte, l'état de la session, se connecter, se déconnecter, changer de compte. Déconnecté, les jeux installés restent jouables : la session ne sert qu'à lire la liste des jeux, à en installer et à les mettre à jour. Un jeu Steam a en revanche besoin du client Steam ouvert pendant la partie.
- **Options** : les réglages généraux de lancement.
- **Verger** : sa version et sa mise à jour.

### 6. Mise à jour de Verger
Verger se met à jour depuis ses releases GitHub, séparément de Cidre. Au lancement il compare sa version à la dernière release ; « Mettre à jour et relancer » télécharge `Verger.zip`, vérifie qu'il contient bien une application à la signature intacte, la met à la place de l'ancienne et relance. Si quoi que ce soit échoue, l'ancienne version reste en place.

Publier une version : pousser un tag `vX.Y.Z`. Le workflow GitHub Actions teste, construit `Verger.app` et l'attache à la release.

### 7. Sauvegardes
État de synchro par jeu + bouton backup/restore (`cidre sync`), au-dessus de notre sync iCloud (Steam Cloud ne résout pas les roots Windows sur mac).

## Stack technique recommandée

**SwiftUI (app macOS native, arm64).** Cohérent avec l'ADN du projet (natif, sans Rosetta, sans bloat) : ce serait absurde de livrer une UI Electron de 200 Mo pour un projet qui refuse la traduction. SwiftUI donne aussi la meilleure intégration plein écran / encoche / notifications, et un binaire léger qui se patche vite.

- UI : SwiftUI
- Logique : appels à la CLI `cidre` (Process), parsing JSON
- Login : fenêtre au-dessus de SteamCMD aujourd'hui ; cible QR avec DepotDownloader embarqué (self-contained .NET) ou bridge SteamKit
- Stockage réglages : `profils.toml` partagé avec Cidre

Alternative si on veut du cross-platform plus tard : Tauri (Rust + web, léger). Mais pour une cible mac-only, SwiftUI gagne.

## Construire et lancer

Il faut les outils Swift (Command Line Tools ou Xcode), rien d'autre.

```bash
Scripts/bundle.sh --open
```

construit `build/Verger.app` (arm64, moins d'1 Mo) et l'ouvre. Les tests du pont :

```bash
Scripts/test.sh
```

## Où on en est

- **Phase 0 — plomberie** (côté Cidre) : `cidre list --json`, `cidre info --json`, `profils.toml`. **Fait.**
- **Phase 1 — Verger lecture seule** : bibliothèque + bouton Jouer (`cidre play`) sur les jeux déjà installés, fiche du jeu avec ses options actives. **Fait.**
- **Phase 2 — options par jeu** : panneau de réglages qui écrit `profils.toml` (`cidre set`). **Fait.**
- **Phase 3 — installer** : jeux Steam du compte (`cidre library`, `cidre dl`) et jeux non-Steam (`cidre add`, `cidre run`), désinstallation (`cidre rm`). **Fait**, avec une fenêtre de connexion au-dessus de SteamCMD ; le login QR reste à faire.
- **Installation et mise à jour de Cidre par Verger** (`cidre status`, `cidre setup`). **Fait.**
- **Mises à jour des jeux** (`cidre updates`). **Fait.**
- **Réglages** (état de Cidre, compte Steam, options générales) et **mise à jour de Verger par GitHub**. **Fait.**
- **Phase 4 — polish** : saves, connexion par QR code.

## Structure du dépôt

```
verger/
  Package.swift
  Verger/
    VergerApp.swift
    Library/           # vue bibliothèque : grille, jaquettes, fiche du jeu
    GameSettings/      # options de lancement par jeu
    Install/           # installer un jeu Steam du compte
    Login/             # fenêtre de connexion à Steam
    Runtime/           # installer et mettre à jour Cidre
    Settings/          # réglages : Cidre, Steam, options générales, Verger
    Updater/           # mise à jour de Verger lui-même
    CidreBridge/       # appels CLI cidre + parsing JSON (cible à part, testée)
  Tests/               # tests du pont
  Scripts/             # bundle.sh (Verger.app), test.sh
```

À venir : `Tools/` (DepotDownloader, pour le login QR).

---
*Cidre est le moteur, Verger est la vitrine. Deux dépôts, un contrat (la CLI). On patche l'un sans retélécharger l'autre.*
