#!/usr/bin/env bash
# Public-Docs-QS — deterministisch, 0 Token. Hält die öffentlich sichtbaren
# Artefakte (aktuell: Root-README) zum Repo-Stand konsistent.
#
#   docs-attest.sh check     Struktur-Invarianten gegen docs/readme-spec.md:
#                            Pflicht-Marker vorhanden, Bild-/Link-Pfade existieren,
#                            kein Anti-Vokabular. (immer erfüllen)
#   docs-attest.sh attest    BEWUSSTE Bestätigung vor dem Push: README folgt dem
#                            Aufbau UND ist inhaltlich aktuell -> stempelt den
#                            aktuellen HEAD nach .docs-attest. Führt check vorher aus.
#   docs-attest.sh attested  Gibt den zuletzt attestierten Commit aus (oder leer).
#
# Genutzt vom pre-push-Hook (Schranke) und vom dart-test-Gate (check).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPEC="$ROOT/docs/readme-spec.md"
ATTEST="$ROOT/.docs-attest"

# Öffentlich sichtbare Artefakte (erweiterbar: Hilfe-Texte, web/ …).
PUBLIC_DOCS=( "README.md" )

cmd_check() {
  local fail=0 doc="$ROOT/README.md"

  # 1) Pflicht-Marker aus der Spec (Single Source of Truth für den Aufbau)
  local markers
  markers="$(awk '/required:start/{f=1;next} /required:end/{f=0} f' "$SPEC" \
             | sed '/^[[:space:]]*$/d')"
  while IFS= read -r m; do
    [ -z "$m" ] && continue
    grep -qF -- "$m" "$doc" || { echo "  ✗ README fehlt Pflicht-Marker: $m"; fail=1; }
  done <<< "$markers"

  # 2) relative Bild-/Link-Pfade existieren
  local refs
  refs="$( { grep -oE 'src="[^"]+"' "$doc" | sed -E 's/src="([^"]+)"/\1/';
             grep -oE '\]\([^)]+\)' "$doc" | sed -E 's/\]\(([^)]+)\)/\1/'; } \
           | sort -u || true )"
  while IFS= read -r r; do
    [ -z "$r" ] && continue
    case "$r" in http://*|https://*|mailto:*|\#*) continue ;; esac
    r="${r%%#*}"; r="${r%%\?*}"; [ -z "$r" ] && continue
    [ -e "$ROOT/$r" ] || { echo "  ✗ README verweist auf fehlenden Pfad: $r"; fail=1; }
  done <<< "$refs"

  # 3) Anti-Vokabular (PCRE via perl -> portabel auf macOS/Linux)
  local hits
  hits="$(perl -ne 'print "  $.: $_" if /(Firebase|Firestore|Crashlytics|\bLoam\b(?!\.dev))/' "$doc" || true)"
  if [ -n "$hits" ]; then echo "  ✗ Anti-Vokabular in README (siehe CONTEXT.md):"; echo "$hits"; fail=1; fi

  [ "$fail" -eq 0 ] || { echo "Public-Docs-QS (check) fehlgeschlagen." >&2; exit 1; }
  echo "Public-Docs-QS check: ok"
}

cmd_attest() {
  cmd_check
  git -C "$ROOT" rev-parse HEAD > "$ATTEST"
  echo "README als aktuell & aufbaukonform bestätigt für $(cat "$ATTEST")."
  echo "Hinweis: attest bedeutet — README GELESEN und gegen den Repo-Stand geprüft."
}

cmd_attested() { [ -f "$ATTEST" ] && cat "$ATTEST" || true; }

case "${1:-}" in
  check)    cmd_check ;;
  attest)   cmd_attest ;;
  attested) cmd_attested ;;
  *) echo "usage: $0 {check|attest|attested}" >&2; exit 2 ;;
esac
