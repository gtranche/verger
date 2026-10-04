#!/bin/sh
# Lance les tests. Avec les seuls Command Line Tools (sans Xcode actif), SwiftPM
# ne trouve pas Swift Testing tout seul : on lui montre le framework, et on
# coupe l'overlay _Testing_Foundation que les CLT livrent sans son module.
set -eu
R=$(cd "$(dirname "$0")/.." && pwd)
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
if xcode-select -p | grep -q CommandLineTools && [ -d "$F/Testing.framework" ]; then
   exec swift test --package-path "$R" \
      -Xswiftc -F -Xswiftc "$F" -Xswiftc -Xfrontend -Xswiftc -disable-cross-import-overlays \
      -Xlinker -F -Xlinker "$F" -Xlinker -rpath -Xlinker "$F" "$@"
fi
exec swift test --package-path "$R" "$@"
