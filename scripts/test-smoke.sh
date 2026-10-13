#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
swiftc -module-cache-path /private/tmp/CopieSmokeModuleCache \
  Copie/Models.swift Copie/HistoryStore.swift Tests/Smoke.swift \
  -framework AppKit -framework ImageIO -lsqlite3 \
  -o /private/tmp/CopieSmoke
/private/tmp/CopieSmoke
