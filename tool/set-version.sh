#!/usr/bin/env bash
# Die EINE Stelle, um die loam-Version zu bumpen.
#
# Setzt die pubspec-Version (Single Source of Truth) und zieht alle erzwungenen
# Spiegel atomar nach: den in-code `loamVersion`, den Website-Versions-Chip und
# — falls noch nicht vorhanden — einen CHANGELOG-Stub-Eintrag. Danach läuft
# `docs-attest.sh check`, sodass ein inkonsistenter Zustand gar nicht erst
# stehen bleibt. Versionsnummern werden nirgends mehr von Hand verteilt.
#
#   usage: tool/set-version.sh X.Y.Z[-suffix]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NEW="${1:-}"

if ! printf '%s' "$NEW" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+([-+.][0-9A-Za-z.-]+)?$'; then
  echo "usage: $0 X.Y.Z[-suffix]   (z. B. 0.1.2 oder 0.2.0-preview)" >&2
  exit 2
fi

PUBSPEC="$ROOT/packages/loam_cli/pubspec.yaml"
VERSIONDART="$ROOT/packages/loam_cli/lib/src/version.dart"
CHANGELOG="$ROOT/packages/loam_cli/CHANGELOG.md"
WEBPAGE="$ROOT/web/src/layouts/Layout.astro"

# 1. pubspec — die Quelle.
perl -i -pe 's/^version:\s*\S+\s*$/version: '"$NEW"'\n/ if /^version:/' "$PUBSPEC"

# 2. in-code Spiegel.
perl -i -pe "s/loamVersion = '[^']*'/loamVersion = '$NEW'/" "$VERSIONDART"

# 3. Website-Versions-Chip (Form: `vX.Y.Z · …`).
if [ -f "$WEBPAGE" ]; then
  perl -i -pe 's/v\d+\.\d+\.\d+[0-9A-Za-z.+-]*( · )/v'"$NEW"'$1/' "$WEBPAGE"
fi

# 4. CHANGELOG — Stub anlegen, falls der oberste Eintrag noch nicht $NEW ist.
if [ -f "$CHANGELOG" ]; then
  top="$(grep -m1 -oE '^##[[:space:]]+[0-9]+\.[0-9]+\.[0-9]+[^[:space:]]*' "$CHANGELOG" \
         | sed -E 's/^##[[:space:]]+//' || true)"
  if [ "$top" != "$NEW" ]; then
    tmp="$(mktemp)"
    awk -v v="$NEW" '
      NR==1 && /^# Changelog/ { print; print ""; print "## " v; print "";
        print "- _TODO: describe the changes in this release._"; print ""; next }
      { print }
    ' "$CHANGELOG" > "$tmp"
    mv "$tmp" "$CHANGELOG"
    echo "→ CHANGELOG: Stub-Eintrag '## $NEW' eingefügt — bitte ausformulieren."
  fi
fi

echo "→ Version auf $NEW gesetzt (pubspec · version.dart · web-chip · changelog)."
echo "→ Verifiziere mit docs-attest …"
bash "$ROOT/tool/docs-attest.sh" check
echo "✓ Konsistent. Noch: CHANGELOG ausformulieren, committen, taggen (vX.Y.Z) → Release."
