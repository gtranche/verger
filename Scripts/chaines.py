#!/usr/bin/env python3
"""Les textes de l'interface, et leur traduction.

    Scripts/chaines.py            liste les textes du code sans traduction anglaise
    Scripts/chaines.py --tout     liste tous les textes trouves, avec leur contexte

Les textes sont ecrits en francais dans le code ; Resources/en.lproj/Localizable.strings
porte leur traduction. Un texte a trous devient une cle a format : `\\(x)` -> `%@`
(ou `%lld` pour un entier, a corriger a la main dans IGNORES/ENTIERS ci-dessous).
Sort avec le code 1 s'il manque une traduction : a lancer avant de publier.
"""
import os
import re
import sys

RACINE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SOURCES = os.path.join(RACINE, "Verger")
TABLE = os.path.join(RACINE, "Resources", "en.lproj", "Localizable.strings")

# Les interpolations qui portent un entier : leur trou est %lld, pas %@.
ENTIERS = ("candidates.count",)

# Des chaines qui ne sont pas des textes d'interface.
def technique(s):
    if not re.search(r"[A-Za-zÀ-ÿ]", s):
        return True
    # une expression reguliere, un bout de Markdown : pas un texte d'interface
    if re.search(r"\\\\|\(\?|\[0-9|\[A-Z|\[U:1|\*\*|```|err:\|", s):
        return True
    if re.fullmatch(r"[a-z0-9_.\-/:=%@#+ ]*", s) and " " not in s.strip():
        return True
    return s.startswith(("/", "http", "steam://", "Library/", "Contents/", "@", "+", "-", "--", "== ")) \
        or s in IGNORES


IGNORES = {
    "Verger", "Cidre", "Steam", "macOS · Windows", "Windows", "CIDRE_STEAM_USER", "VERGER_CIDRE",
    "VERGER_RUNTIME_URL", "VERGER_RUNTIME_VERSION", "VERGER_CIDRE_HOME", "PATH", "Accept", "Authorization",
    "Bearer %@", "CFBundleShortVersionString", "Français", "English", "Deutsch", "Español", "Italiano",
    "Português", "Polski", "%@#%@", "sleep 1; /usr/bin/open \"$0\"", "Verger.zip", "Verger (version précédente)",
    "%@", "%lld", "dl %@", "brew install ", "steam guard code:", "two-factor code:",
    "confirm the login in the steam mobile app", "waiting for user info...ok", "invalid password",
    "rate limit exceeded", "two-factor code mismatch", "invalid login auth code", "fr_FR", "en_US",
    "‹steam›", "‹mac›", "‹mail›", "macOS %@ · %@ · %@ · %@", "%2B", "text", "dev",
    "SET_ACTIVITY", "ERROR", "DISPATCH", "READY", "Discord", "steam",
    "ongletReglages", "cleSteamGridDB", "cidrePath", "steamUser", "AppleLanguages", "langue",
}

LITTERAL = re.compile(r'"((?:[^"\\]|\\.)*)"')


def cle(s):
    def trou(m):
        return "%lld" if any(e in m.group(1) for e in ENTIERS) else "%@"
    s = re.sub(r"\\\(([^()]*(?:\([^()]*\))?[^()]*)\)", trou, s)
    return s.replace('\\"', '"').replace("\\n", "\n")


def textes():
    for dossier, _, fichiers in os.walk(SOURCES):
        for f in sorted(fichiers):
            if not f.endswith(".swift"):
                continue
            chemin = os.path.join(dossier, f)
            for n, ligne in enumerate(open(chemin, encoding="utf-8"), 1):
                code = ligne.split("//")[0] if not ligne.strip().startswith('"') else ligne
                if re.match(r"\s*(case \w+ = |///|//)", ligne) or "CodingKey" in ligne:
                    continue
                for m in LITTERAL.finditer(code):
                    s = cle(m.group(1))
                    if not technique(s):
                        yield os.path.relpath(chemin, RACINE), n, s, code[max(0, m.start() - 28):m.start()].strip()


def traduits():
    if not os.path.exists(TABLE):
        return {}
    t = open(TABLE, encoding="utf-8").read()
    return {a.replace('\\"', '"').replace("\\n", "\n"): b for a, b in re.findall(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)";', t, re.M)}


def main():
    connus = traduits()
    vus = {}
    for fichier, n, s, contexte in textes():
        vus.setdefault(s, (fichier, n, contexte))
    if "--tout" in sys.argv:
        for s, (fichier, n, contexte) in vus.items():
            print("%s:%d\t%s\t%r" % (fichier.replace("Verger/", ""), n, contexte[-22:], s))
        return
    manquants = [(s, v) for s, v in vus.items() if s not in connus]
    for s, (fichier, n, _) in manquants:
        print("%s:%d  %r" % (fichier, n, s))
    inutiles = [s for s in connus if s not in vus]
    print("%d textes, %d sans traduction, %d traductions sans texte" % (len(vus), len(manquants), len(inutiles)))
    for s in inutiles:
        print("  inutile : %r" % s)
    sys.exit(1 if manquants else 0)


if __name__ == "__main__":
    main()
