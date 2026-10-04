#!/bin/sh
# Construit Verger.app (arm64, release) sans Xcode : `swift build` + un bundle
# monte a la main. Sortie : build/Verger.app
#   Scripts/bundle.sh [--open]
set -eu
R=$(cd "$(dirname "$0")/.." && pwd)
# La version : celle qu'on donne, sinon le dernier tag (une construction locale
# porte la version de la derniere release, et ne se propose donc pas de mise a jour).
VERSION=${VERGER_VERSION:-$(git -C "$R" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')}
VERSION=${VERSION:-0.1.0}
# VERGER_BUILD_DIR : construire ailleurs que dans build/ (pour essayer une
# version sans remplacer l'application qu'on est en train d'utiliser).
APP="${VERGER_BUILD_DIR:-$R/build}/Verger.app"

swift build --package-path "$R" -c release --arch arm64
BIN=$(swift build --package-path "$R" -c release --arch arm64 --show-bin-path)/Verger

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
# mv, pas cp : sur macOS, ecraser un binaire mappe tue le processus qui tourne.
cp "$BIN" "$APP/Contents/MacOS/Verger.nouveau"
mv "$APP/Contents/MacOS/Verger.nouveau" "$APP/Contents/MacOS/Verger"
# Les traductions : le francais est la langue du code (table vide), l'anglais
# est dans Resources/en.lproj.
mkdir -p "$APP/Contents/Resources"
cp -R "$R/Resources/"*.lproj "$APP/Contents/Resources/"
# L'icone : Scripts/icone.sh la fabrique a partir de Resources/AppIcon-source.png.
cp "$R/Resources/AppIcon.icns" "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
   <key>CFBundleName</key><string>Verger</string>
   <key>CFBundleDisplayName</key><string>Verger</string>
   <key>CFBundleIdentifier</key><string>io.github.gtranche.verger</string>
   <key>CFBundleExecutable</key><string>Verger</string>
   <key>CFBundlePackageType</key><string>APPL</string>
   <key>CFBundleShortVersionString</key><string>$VERSION</string>
   <key>CFBundleVersion</key><string>$VERSION</string>
   <key>LSMinimumSystemVersion</key><string>14.0</string>
   <key>LSApplicationCategoryType</key><string>public.app-category.games</string>
   <key>CFBundleIconFile</key><string>AppIcon</string>
   <key>CFBundleDevelopmentRegion</key><string>fr</string>
   <key>CFBundleLocalizations</key><array><string>fr</string><string>en</string></array>
   <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP" >/dev/null
echo "OK : $APP ($(du -sh "$APP" | cut -f1))"
if [ "${1:-}" = --open ]; then
   # Un Verger deja ouvert resterait a l'ecran sur l'ancienne version : `open`
   # ne ferait que le ramener au premier plan. On le quitte d'abord.
   osascript -e 'tell application id "io.github.gtranche.verger" to quit' >/dev/null 2>&1 || true
   sleep 1
   open "$APP"
fi
exit 0
