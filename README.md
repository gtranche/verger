# Verger

## En une phrase

**Verger** est l'interface graphique macOS qui pilote **Cidre** : ta bibliothèque de jeux, où tu installes, règles et lances tes jeux Windows (via Cidre) comme tes jeux natifs — sans jamais toucher à la console Steam ni à une ligne de commande.

Cidre = le moteur (FEX + Wine + DXVK + KosmicKrisp). Verger = le verger où poussent les jeux : la vitrine, le catalogue, les réglages, le bouton « Jouer ».

## Pourquoi un dépôt séparé (le point qui commande tout)

Le runtime Cidre pèse des **gigas** (Wine arm64, Mesa/KosmicKrisp, DXVK, FEX…). L'UI, elle, change **souvent** et pèse **quelques Mo**. Les mélanger obligerait à re-pousser / re-télécharger tout le runtime à chaque correction d'un bouton.

→ **Verger est un dépôt et un binaire indépendants.** Il ne contient aucun binaire de runtime. Il **détecte / installe / met à jour Cidre séparément**. On peut patcher l'UI 10 fois par jour sans que personne ne retélécharge un seul octet de Wine.

Conséquence d'archi : la frontière Verger ↔ Cidre est un **contrat stable** (la CLI `cidre`), pas un couplage de code.

## Le contrat Verger ↔ Cidre (la CLI)

Verger ne réimplémente rien : il appelle la CLI `cidre` et lit/écrit des fichiers de config que `cidre` consomme.

| Besoin UI | Commande Cidre |
|---|---|
| Lister les jeux (plateforme, mode, installé ?) | `cidre list --json` |
| Fiche d'un jeu (taille, chemin, options actives) | `cidre info <appid> --json` |
| Télécharger un jeu Windows hors client | `cidre dl <appid> [windows\|macos]` |
| Lancer un jeu | `cidre play <appid>` |
| Sauvegardes (iCloud) | `cidre sync <appid\|all> [backup\|restore]` |
| (futur) Désinstaller | `cidre rm <appid>` |

Verger parse ce JSON (`Verger/CidreBridge`) ; il ne scrape jamais la sortie texte. Une valeur qu'il ne connaît pas (CLI plus récente) retombe sur une valeur neutre au lieu de faire tomber la bibliothèque.

Verger cherche la commande `cidre` dans cet ordre : le chemin choisi dans l'app, la variable `VERGER_CIDRE`, l'install standard (`~/Library/Application Support/Cidre/cidre/cidre`), puis le `PATH`.

## Fonctionnalités

### 1. Bibliothèque (le verger)
Grille des jeux possédés / installés, avec pour chacun : jaquette, plateforme (**natif** vs **Cidre/Windows**), état (installé / à télécharger / MAJ dispo), taille, dernier lancement. Bouton **Installer** (`cidre dl`) et **Jouer** (`cidre play`).

### 2. Options de lancement par jeu  ← demande explicite
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

**Modèle :** un profil **par défaut** + des **surcharges par appid**, dans un fichier de données que `cidre play` lit et que **Verger écrit** : `~/Library/Application Support/Cidre/profils.toml`.

```toml
[defaut]
hud = true

[552500]            # Vermintide 2
fils_compilation = 6
```

Clés : `tso`, `vsync`, `hud`, `async`, `fils_compilation`, `eac_untrusted`, `luajit`. Cidre livre ses propres réglages par jeu (`outil-steam/profils.toml`) ; le fichier utilisateur les surcharge clé par clé, et la section d'un jeu l'emporte sur `[defaut]`. Format volontairement plat (sections + `cle = valeur`), pour rester lisible par un script `sh`.

### 3. Login simple  ← demande explicite
**Connexion par QR / appli Steam mobile**, pas de mot de passe tapé dans Verger, pas de terminal :
1. Verger affiche un **QR code**.
2. L'utilisateur le scanne avec l'appli Steam mobile et **approuve**.
3. Verger récupère un **jeton de session** (mémorisé), zéro mot de passe stocké.

Moteur : **SteamKit2 / DepotDownloader** (supporte le login QR et le téléchargement de dépôt par OS). Pour la V1 on peut encapsuler SteamCMD (session mémorisée), mais la cible UX est le QR.

> Pourquoi pas steamctl : `python-steam` renvoie « Invalid Password » sur l'ancien flux de login (déprécié par Steam). Abandonné.

### 4. Sauvegardes
État de synchro par jeu + bouton backup/restore (`cidre sync`), au-dessus de notre sync iCloud (Steam Cloud ne résout pas les roots Windows sur mac).

## Stack technique recommandée

**SwiftUI (app macOS native, arm64).** Cohérent avec l'ADN du projet (natif, sans Rosetta, sans bloat) : ce serait absurde de livrer une UI Electron de 200 Mo pour un projet qui refuse la traduction. SwiftUI donne aussi la meilleure intégration plein écran / encoche / notifications, et un binaire léger qui se patche vite.

- UI : SwiftUI
- Logique : appels à la CLI `cidre` (Process), parsing JSON
- Login : binaire DepotDownloader embarqué (self-contained .NET) ou bridge SteamKit
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
- **Phase 2 — options par jeu** : panneau de réglages qui écrit `profils.toml`.
- **Phase 3 — install + login QR** : bouton Installer (`cidre dl`) derrière le login QR.
- **Phase 4 — polish** : saves, MAJ, détection auto de Cidre + auto-update de Verger (séparé du runtime).

## Structure du dépôt

```
verger/
  Package.swift
  Verger/
    VergerApp.swift
    Library/           # vue bibliothèque : grille, jaquettes, fiche du jeu
    CidreBridge/       # appels CLI cidre + parsing JSON (cible à part, testée)
  Tests/               # tests du pont
  Scripts/             # bundle.sh (Verger.app), test.sh
```

À venir : `Verger/GameSettings/` (Phase 2), `Verger/Login/` et `Tools/` (DepotDownloader, Phase 3).

---
*Cidre est le moteur, Verger est la vitrine. Deux dépôts, un contrat (la CLI). On patche l'un sans retélécharger l'autre.*
