#!/bin/sh
# Fabrique Resources/AppIcon.icns a partir de l'illustration Resources/AppIcon-source.png
# (carree, 1024 x 1024, sans coins arrondis : la forme est appliquee ici).
# A relancer quand l'illustration change ; l'icns est commite, bundle.sh le copie.
set -eu
R=$(cd "$(dirname "$0")/.." && pwd)
SET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$SET"
for t in 16 32 128 256 512; do
   swift "$R/Scripts/icone.swift" "$R/Resources/AppIcon-source.png" "$SET/icon_${t}x${t}.png" "$t"
   swift "$R/Scripts/icone.swift" "$R/Resources/AppIcon-source.png" "$SET/icon_${t}x${t}@2x.png" "$((t * 2))"
done
iconutil -c icns "$SET" -o "$R/Resources/AppIcon.icns"
echo "OK : $R/Resources/AppIcon.icns"
