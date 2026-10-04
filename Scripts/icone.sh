#!/bin/sh
# Fabrique l'icone de Verger : Scripts/logo.swift dessine le logo
# (Resources/AppIcon-source.png, carre, sans coins arrondis), puis on lui donne la
# forme des icones macOS a toutes les tailles (Resources/AppIcon.icns).
# A relancer quand le dessin change ; les deux fichiers sont commites, bundle.sh copie l'icns.
set -eu
R=$(cd "$(dirname "$0")/.." && pwd)
swift "$R/Scripts/logo.swift" "$R/Resources/AppIcon-source.png"
SET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$SET"
for t in 16 32 128 256 512; do
   swift "$R/Scripts/icone.swift" "$R/Resources/AppIcon-source.png" "$SET/icon_${t}x${t}.png" "$t"
   swift "$R/Scripts/icone.swift" "$R/Resources/AppIcon-source.png" "$SET/icon_${t}x${t}@2x.png" "$((t * 2))"
done
iconutil -c icns "$SET" -o "$R/Resources/AppIcon.icns"
# la vignette du README et du site, et les icones du site
swift "$R/Scripts/icone.swift" "$R/Resources/AppIcon-source.png" "$R/docs/captures/icone.png" 256
swift "$R/Scripts/icone.swift" "$R/Resources/AppIcon-source.png" "$R/docs/favicon.png" 64
# iOS arrondit lui-meme : on lui donne le dessin plein cadre
sips -z 180 180 "$R/Resources/AppIcon-source.png" --out "$R/docs/apple-touch-icon.png" >/dev/null
echo "OK : $R/Resources/AppIcon.icns"
