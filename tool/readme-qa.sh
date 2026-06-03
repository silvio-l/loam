#!/usr/bin/env bash
# README-QS — deterministisch, 0 Token. Hält die README zum Repo-Stand konsistent.
#
#   readme-qa.sh check       Inhalts-Invarianten (immer erfüllen): Bild-/Link-
#                            Pfade existieren, kein Anti-Vokabular, Pflichtsektionen.
#   readme-qa.sh freshness   Attestierung: sind README-QUELLEN seit dem letzten
#                            bewussten ack unverändert? (stale -> exit 3)
#   readme-qa.sh ack         BEWUSSTE Bestätigung: README wurde geprüft und passt
#                            zum aktuellen Repo-Stand -> Stempel neu schreiben.
#
# Wird vom git pre-commit-Hook und vom dart-test-Gate aufgerufen.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
README="$ROOT/README.md"
STAMP="$ROOT/.readme-stamp"

# README-QUELLEN: ändert sich eine davon, muss die README bewusst re-attestiert
# werden. Bewusst klein gehalten (Command-Surface + Domäne + Spec).
SOURCES=(
  "CONTEXT.md"
  "docs/PRD.md"
  "packages/loam_cli/bin/loam.dart"
)

# Anti-Vokabular (sicher regexbar; siehe CONTEXT.md). Generische Wörter bewusst
# ausgelassen, um False Positives in Prosa zu vermeiden.
ANTIVOCAB='Firebase|Firestore|Crashlytics|\bLoam\b(?!\.dev)'

# Pflicht-Bausteine der README.
REQUIRED=(
  'assets/brand/lockup-horizontal-dark.png'   # Hero-Logo
  'dart pub global activate loam'             # Install
  '## License'                                # Lizenz-Sektion
)

sha() { shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'; }

sources_hash() {
  local acc=""
  for f in "${SOURCES[@]}"; do
    [ -f "$ROOT/$f" ] && acc+="$(sha "$ROOT/$f")  $f"$'\n'
  done
  printf '%s' "$acc" | shasum -a 256 | awk '{print $1}'
}

cmd_check() {
  local fail=0

  # 1) relative Bild-/Link-Pfade existieren
  local refs
  refs="$( { grep -oE 'src="[^"]+"' "$README" | sed -E 's/src="([^"]+)"/\1/';
             grep -oE '\]\([^)]+\)' "$README" | sed -E 's/\]\(([^)]+)\)/\1/'; } \
           | sort -u || true )"
  while IFS= read -r r; do
    [ -z "$r" ] && continue
    case "$r" in
      http://*|https://*|mailto:*|\#*) continue ;;
    esac
    r="${r%%#*}"; r="${r%%\?*}"
    [ -z "$r" ] && continue
    if [ ! -e "$ROOT/$r" ]; then
      echo "  ✗ README verweist auf fehlenden Pfad: $r"; fail=1
    fi
  done <<< "$refs"

  # 2) kein Anti-Vokabular
  if grep -nP "$ANTIVOCAB" "$README" >/dev/null 2>&1; then
    echo "  ✗ Anti-Vokabular in README (siehe CONTEXT.md):"
    grep -nP "$ANTIVOCAB" "$README" | sed 's/^/      /'
    fail=1
  fi

  # 3) Pflicht-Bausteine vorhanden
  for need in "${REQUIRED[@]}"; do
    grep -qF "$need" "$README" || { echo "  ✗ README fehlt Pflicht-Baustein: $need"; fail=1; }
  done

  if [ "$fail" -ne 0 ]; then
    echo "README-QS (check) fehlgeschlagen." >&2; exit 1
  fi
  echo "README-QS check: ok"
}

cmd_freshness() {
  local cur stamp
  cur="$(sources_hash)"
  stamp="$( [ -f "$STAMP" ] && cat "$STAMP" || echo '' )"
  if [ "$cur" != "$stamp" ]; then
    cat >&2 <<EOF
README-QS: QUELLEN haben sich seit der letzten Bestätigung geändert
  geänderte Quellen-Menge: ${SOURCES[*]}
→ README.md gegen den aktuellen Stand PRÜFEN (und ggf. anpassen),
  dann BEWUSST bestätigen:  tool/readme-qa.sh ack   &&  git add .readme-stamp
EOF
    exit 3
  fi
  echo "README-QS freshness: ok"
}

cmd_ack() {
  sources_hash > "$STAMP"
  echo "README als aktuell bestätigt — Stempel geschrieben ($STAMP)."
  echo "Nicht vergessen: git add .readme-stamp"
}

case "${1:-}" in
  check)     cmd_check ;;
  freshness) cmd_freshness ;;
  ack)       cmd_ack ;;
  *) echo "usage: $0 {check|freshness|ack}" >&2; exit 2 ;;
esac
