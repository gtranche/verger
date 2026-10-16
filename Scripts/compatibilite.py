#!/usr/bin/env python3
"""La liste de compatibilite des jeux du site (docs/compatibilite/), depuis les fiches de Cidre.

    python3 -I Scripts/compatibilite.py --depot ~/Dev/cidre/profils
    python3 -I Scripts/compatibilite.py --depot DIR --archive profils-base.tar.gz
    python3 -I Scripts/compatibilite.py --depot DIR --sans-catalogue

Deux sources, celles que lit `cidre profils maj` (voir profils/README.md de Cidre) :
- les fiches du depot de Cidre (`profils/<appid>.toml`, ~1 250), ecrites ou relues
  a la main ; celles dont `[compat]` vient d'un essai (`source = "cidre-test"` ou
  `"utilisateur"`) sont les jeux valides par Cidre ;
- le catalogue, l'archive `profils-base.tar.gz` de la release `profils-base` du
  depot de Cidre (~26 800 fiches), qui reprend les fiches du depot et y ajoute les
  jeux notes sur ProtonDB, enrichis par PCGamingWiki et AppleGamingWiki. Lue en
  memoire, jamais deballee. Par defaut, telechargee depuis GitHub.

Pour un jeu du depot, l'etat, la voie et les notes sont ceux du depot (une
correction recente passe devant l'archive, comme dans fiche_profil.sh chemin) ;
les resumes importes (ProtonDB, AppleGamingWiki) sont pris la ou ils sont.
L'etat affiche est celui de Verger : le `[compat]` de la fiche (machine de
reference) et les entrees `[[compat.machines]]` famille par famille, avec leur
condition `si` ; la page choisit celle du Mac du visiteur (selecteur « Mon Mac »)
en evaluant ces conditions comme Cidre. Elle recoit aussi les variantes
`[[machine]]` (options et reglages du jeu propres a certaines machines) et les
`[[rapports]]` des joueurs, avec la machine de chacun. Rien du
texte des wikis n'est repris (CC BY-NC-SA) : seulement les valeurs de leurs
modeles, comme le fait l'import de Cidre.

Sortie : docs/compatibilite/jeux.json, une ligne par jeu, triee par appid, sans
date du jour (deux executions sur les memes fiches donnent le meme fichier).
"""
import argparse
import io
import json
import os
import re
import sys
import tarfile
import tomllib
import urllib.request

RACINE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SORTIE = os.path.join(RACINE, "docs", "compatibilite", "jeux.json")
ARCHIVE = "https://github.com/gtranche/cidre/releases/download/profils-base/profils-base.tar.gz"

FICHE = re.compile(r"^[0-9]+\.toml$")
ETATS = ("or", "argent", "bronze", "ko", "non-teste")
# Les sources d'un [compat] qui vient d'un essai sous Cidre, pas d'un import.
ESSAIS = ("cidre-test", "utilisateur")
PALIERS = ("platinum", "gold", "silver", "bronze", "borked", "pending")
VERDICTS_AGW = ("parfait", "jouable", "demarre", "ko")


def lire_depot(dossier):
    fiches = {}
    for nom in sorted(os.listdir(dossier)):
        if FICHE.match(nom):
            with open(os.path.join(dossier, nom), "rb") as f:
                fiches[int(nom[:-5])] = tomllib.load(f)
    return fiches


def lire_archive(chemin):
    """Les fiches d'une archive profils-base.tar.gz (fichier ou URL), lues en memoire."""
    if re.match(r"^https?://", chemin):
        with urllib.request.urlopen(chemin, timeout=120) as r:
            donnees = r.read()
    else:
        with open(chemin, "rb") as f:
            donnees = f.read()
    fiches = {}
    with tarfile.open(fileobj=io.BytesIO(donnees), mode="r:gz") as tar:
        for membre in tar:
            nom = membre.name.removeprefix("./")
            if not membre.isfile() or not FICHE.match(nom):
                continue
            try:
                fiches[int(nom[:-5])] = tomllib.loads(tar.extractfile(membre).read().decode("utf-8"))
            except (tomllib.TOMLDecodeError, UnicodeDecodeError) as e:
                print(f"compatibilite: {nom} illisible dans l'archive ({e}), laissee", file=sys.stderr)
    return fiches


def texte(v):
    return v.strip() if isinstance(v, str) and v.strip() else None


def entier(v):
    return v if isinstance(v, int) and not isinstance(v, bool) and v > 0 else None


def voie(fiche):
    """La voie de rendu de la fiche (README de Cidre) : d3d12 si dx12, sinon d3d11, sinon [compat] voie."""
    cidre = fiche.get("cidre", {})
    if cidre.get("dx12") is True:
        return "d3d12"
    return texte(cidre.get("d3d11")) or texte(fiche.get("compat", {}).get("voie"))


def options(cidre):
    """Des options de lancement en `cle=valeur` separes par des espaces, comme `options` de [[compat.machines]]."""
    bouts = []
    for k, v in cidre.items():
        if isinstance(v, bool):
            bouts.append(f"{k}={'true' if v else 'false'}")
        elif isinstance(v, (int, float, str)) and str(v).strip():
            bouts.append(f"{k}={v}")
    return " ".join(bouts)


def variantes(fiche):
    """Les blocs [[machine]] : condition, options de lancement, reglages du jeu (fichier et valeurs)."""
    sortie = []
    for m in fiche.get("machine", []):
        if not isinstance(m, dict) or not texte(m.get("si")):
            continue
        v = {"si": m["si"].strip()}
        cidre = m.get("cidre", {})
        if isinstance(cidre, dict) and options(cidre):
            v["options"] = options(cidre)
            # ce qui change la voie de rendu sur ces machines
            if isinstance(cidre.get("dx12"), bool):
                v["dx12"] = cidre["dx12"]
            if texte(cidre.get("d3d11")):
                v["d3d11"] = cidre["d3d11"].strip()
        reglages = []
        for r in m.get("reglages_jeu", []):
            if not isinstance(r, dict) or not isinstance(r.get("valeurs"), dict):
                continue
            fichier = texte(r.get("fichier")) or ""
            reglages.append({
                "fichier": fichier.rsplit("/", 1)[-1],
                "valeurs": " ".join(f"{k}={val}" for k, val in r["valeurs"].items()),
            })
        if reglages:
            v["reglages"] = reglages
        if len(v) > 1:
            sortie.append(v)
    return sortie


def rapports(fiche):
    """Les [[rapports]] des joueurs, avec la machine de chacun (plus recent d'abord)."""
    sortie = []
    for r in fiche.get("rapports", []):
        if not isinstance(r, dict) or r.get("etat") not in ETATS:
            continue
        x = {"etat": r["etat"]}
        x.update(mesure(r))
        for cle in ("voie", "macos_version", "modele"):
            if texte(r.get(cle)):
                x[cle] = r[cle].strip()
        if entier(r.get("famille_gpu")):
            x["famille"] = r["famille_gpu"]
        if texte(r.get("incident")) and r["incident"].startswith("https://github.com/"):
            x["incident"] = r["incident"].strip()
        sortie.append(x)
    sortie.sort(key=lambda x: x.get("date", ""), reverse=True)
    return sortie


def etat(compat):
    e = compat.get("etat")
    return e if e in ETATS else "non-teste"


def mesure(compat):
    """Ce qu'un etat ([compat] ou une entree par famille) dit en plus du verdict."""
    m = {
        "machine": texte(compat.get("machine")),
        "date": texte(compat.get("date")),
        "cidre": texte(compat.get("cidre_version")),
        "fps_menu": entier(compat.get("fps_menu")),
        "fps_jeu": entier(compat.get("fps_jeu")),
        "notes": texte(compat.get("notes")),
    }
    return {k: v for k, v in m.items() if v is not None}


def jeu(appid, depot, catalogue):
    """L'entree d'un jeu, ou None s'il n'a pas de nom."""
    fiche = depot or catalogue
    importe = catalogue or depot
    j = fiche.get("jeu", {})
    nom = texte(j.get("nom")) or texte(importe.get("jeu", {}).get("nom"))
    if not nom:
        return None
    compat = fiche.get("compat", {})
    e = etat(compat)
    teste = compat.get("source") in ESSAIS and e != "non-teste"
    sortie = {
        "id": appid,
        "nom": nom,
        # t : valide par Cidre ; d : fiche du depot, pas encore essayee ; c : catalogue importe
        "o": "t" if teste else ("d" if depot else "c"),
        "etat": e,
    }
    for cle in ("api", "moteur", "anticheat"):
        v = texte(j.get(cle)) or texte(importe.get("jeu", {}).get(cle))
        if v and v not in ("none", "autre"):
            sortie[cle] = v
    # sans voie ecrite, un jeu D3D11 ou D3D12 passe par le defaut de Cidre (dx12 = false,
    # d3d11 = "dxmt", outil-steam/profils.toml) ; on ne le dit que d'un jeu essaye
    v = voie(fiche) or ("dxmt" if teste and sortie.get("api") in ("d3d11", "d3d12") else None)
    if v:
        sortie["voie"] = v
    if teste:
        sortie.update(mesure(compat))
        familles = []
        for m in compat.get("machines", []):
            if not isinstance(m, dict) or m.get("etat") not in ETATS:
                continue
            f = {"nom": texte(m.get("nom")) or "", "etat": m["etat"]}
            if texte(m.get("si")):
                f["si"] = m["si"].strip()
            if texte(m.get("voie")):
                f["voie"] = m["voie"].strip()
            if texte(m.get("options")):
                f["options"] = m["options"].strip()
            f.update(mesure(m))
            familles.append(f)
        if familles:
            sortie["familles"] = familles
    if depot:
        # ce que la fiche regle autrement selon la machine, et ce qu'en disent les joueurs
        if variantes(depot):
            sortie["variantes"] = variantes(depot)
        if rapports(depot):
            sortie["rapports"] = rapports(depot)
    # les resumes importes : dans la fiche du depot s'il les a, sinon dans l'archive
    for source in (fiche, importe):
        p = source.get("compat", {}).get("protondb", {})
        if p.get("palier") in PALIERS:
            sortie["protondb"] = p["palier"]
            if entier(p.get("rapports")):
                sortie["protondb_rapports"] = p["rapports"]
            break
    for source in (fiche, importe):
        a = source.get("compat", {}).get("applegamingwiki", {})
        verdicts = {k: a[k] for k in ("crossover", "wine") if a.get(k) in VERDICTS_AGW}
        if verdicts:
            sortie["agw"] = verdicts
            if texte(a.get("url")):
                sortie["agw_url"] = a["url"].strip()
            break
    return sortie


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--depot", required=True, help="le dossier profils/ d'un checkout de Cidre")
    p.add_argument("--archive", default=ARCHIVE, help="profils-base.tar.gz, fichier ou URL (defaut : la release profils-base)")
    p.add_argument("--sans-catalogue", action="store_true", help="les fiches du depot seulement")
    p.add_argument("--sortie", default=SORTIE)
    args = p.parse_args()

    depot = lire_depot(args.depot)
    if len(depot) < 100:
        sys.exit(f"compatibilite: {len(depot)} fiches dans {args.depot}, est-ce bien profils/ de Cidre ?")
    catalogue = {} if args.sans_catalogue else lire_archive(args.archive)
    if catalogue and len(catalogue) < len(depot):
        sys.exit(f"compatibilite: l'archive n'a que {len(catalogue)} fiches, moins que le depot ({len(depot)})")

    jeux = []
    for appid in sorted(set(depot) | set(catalogue)):
        j = jeu(appid, depot.get(appid), catalogue.get(appid))
        if j:
            jeux.append(j)
    dates = [f.get("compat", {}).get("date") for f in depot.values()]
    entete = {
        "donnees_du": max((d for d in dates if isinstance(d, str)), default=None),
        "comptes": {o: sum(1 for j in jeux if j["o"] == o) for o in ("t", "d", "c")},
    }
    os.makedirs(os.path.dirname(args.sortie), exist_ok=True)
    tmp = args.sortie + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        # une ligne par jeu : un diff lisible d'une generation a l'autre
        f.write('{"entete":' + json.dumps(entete, ensure_ascii=False, separators=(",", ":")) + ',\n"jeux":[\n')
        f.write(",\n".join(json.dumps(j, ensure_ascii=False, separators=(",", ":")) for j in jeux))
        f.write("\n]}\n")
    os.replace(tmp, args.sortie)
    c = entete["comptes"]
    print(f"{args.sortie} : {len(jeux)} jeux ({c['t']} valides par Cidre, {c['d']} fiches du depot, {c['c']} du catalogue)")


if __name__ == "__main__":
    main()
