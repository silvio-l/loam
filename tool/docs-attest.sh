#!/usr/bin/env bash
# Public-Docs-QS — deterministisch, 0 Token. Hält die öffentlich sichtbaren
# Artefakte zum Repo-Stand konsistent:
#   (1) Root-README  (2) CLI-Hilfe (loam --help)  (3) Website web/
#
#   docs-attest.sh check     Struktur-Invarianten je Artefakt gegen
#                            docs/public-docs-spec.md. (immer erfüllen)
#   docs-attest.sh attest    BEWUSSTE Bestätigung vor dem Push: ALLE Artefakte
#                            folgen dem Aufbau UND sind inhaltlich aktuell ->
#                            stempelt den aktuellen HEAD nach .docs-attest.
#   docs-attest.sh attested  Gibt den zuletzt attestierten Commit aus (oder leer).
#
# Genutzt vom pre-push-Hook (Schranke), pre-commit-Hook und dart-test-Gate (check).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPEC="$ROOT/docs/public-docs-spec.md"
ATTEST="$ROOT/.docs-attest"
README="$ROOT/README.md"
CLI="$ROOT/packages/loam_cli/bin/loam.dart"
WEB="$ROOT/web"
PUBSPEC="$ROOT/packages/loam_cli/pubspec.yaml"
PKGREADME="$ROOT/packages/loam_cli/README.md"

# Anti-Vokabular (PCRE via perl -> portabel macOS/Linux). Generische Wörter
# bewusst ausgelassen, um False Positives in Prosa zu vermeiden.
ANTIVOCAB='(Firebase|Firestore|Crashlytics|\bLoam\b(?!\.dev))'
antivocab() { perl -ne "print \"  \$.: \$_\" if /$ANTIVOCAB/" "$1" 2>/dev/null || true; }

fail=0
note() { echo "  ✗ $1"; fail=1; }

check_readme() {
  # Pflicht-Marker aus der Spec (Single Source of Truth für den Aufbau)
  local markers; markers="$(awk '/required:start/{f=1;next} /required:end/{f=0} f' "$SPEC" \
                            | sed '/^[[:space:]]*$/d')"
  while IFS= read -r m; do
    [ -z "$m" ] && continue
    grep -qF -- "$m" "$README" || note "README fehlt Pflicht-Marker: $m"
  done <<< "$markers"

  # relative Bild-/Link-Pfade existieren
  local refs; refs="$( { grep -oE 'src="[^"]+"' "$README" | sed -E 's/src="([^"]+)"/\1/';
                         grep -oE '\]\([^)]+\)' "$README" | sed -E 's/\]\(([^)]+)\)/\1/'; } \
                       | sort -u || true )"
  while IFS= read -r r; do
    [ -z "$r" ] && continue
    case "$r" in http://*|https://*|mailto:*|\#*) continue ;; esac
    r="${r%%#*}"; r="${r%%\?*}"; [ -z "$r" ] && continue
    [ -e "$ROOT/$r" ] || note "README verweist auf fehlenden Pfad: $r"
  done <<< "$refs"

  # Anti-Vokabular
  local hits; hits="$(antivocab "$README")"
  if [ -n "$hits" ]; then note "Anti-Vokabular in README:"; echo "$hits"; fi
  return 0
}

check_cli() {
  [ -f "$CLI" ] || { note "CLI-Entry fehlt: ${CLI#$ROOT/}"; return; }
  # registrierte Commands extrahieren (name = '…') -> müssen in README stehen
  local cmds; cmds="$(grep -oE "name = '[a-z][a-z-]*'" "$CLI" \
                      | sed -E "s/name = '([a-z-]+)'/\1/" | sort -u || true)"
  while IFS= read -r c; do
    [ -z "$c" ] && continue
    grep -qF -- "loam $c" "$README" || note "CLI-Command '$c' nicht in README dokumentiert"
  done <<< "$cmds"
  return 0
}

check_web() {
  [ -d "$WEB" ] || { note "web/ fehlt"; return; }
  # Anti-Vokabular über Web-Markdown und (sobald gebaut) HTML
  while IFS= read -r f; do
    local hits; hits="$(antivocab "$f")"
    if [ -n "$hits" ]; then note "Anti-Vokabular in ${f#$ROOT/}:"; echo "$hits"; fi
  done < <(find "$WEB" \( -name '*.md' -o -name '*.html' \) -type f 2>/dev/null)
  return 0
}

check_pub() {
  # pub.dev-Artefakt: pubspec `description` + die von pub.dev gerenderte Package-README.
  [ -f "$PUBSPEC" ] || { note "pubspec.yaml fehlt"; return 0; }
  local desc
  desc="$(sed -nE 's/^description:[[:space:]]*"(.*)"[[:space:]]*$/\1/p' "$PUBSPEC")"
  if [ -z "$desc" ]; then  # gefalteter Block (>-, |) als Fallback
    desc="$(awk '/^description:/{c=1;next} c==1{ if($0 ~ /^[^[:space:]]/){c=0} else {l=$0; sub(/^[[:space:]]+/,"",l); printf "%s ",l} }' "$PUBSPEC")"
  fi
  desc="$(printf '%s' "$desc" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
  local n=${#desc}
  if [ "$n" -lt 60 ] || [ "$n" -gt 180 ]; then
    note "pubspec description $n Zeichen (pub.dev-Richtwert 60–180): $desc"
  fi
  if printf '%s' "$desc" | perl -ne "exit(1) if /$ANTIVOCAB/"; then :; else note "Anti-Vokabular in pubspec description"; fi

  if [ -f "$PKGREADME" ]; then
    local hits; hits="$(antivocab "$PKGREADME")"
    if [ -n "$hits" ]; then note "Anti-Vokabular in packages/loam_cli/README.md:"; echo "$hits"; fi
  else
    note "Package-README fehlt (pub.dev rendert sie)"
  fi
  return 0
}

cmd_check() {
  fail=0
  check_readme; check_cli; check_web; check_pub
  [ "$fail" -eq 0 ] || { echo "Public-Docs-QS (check) fehlgeschlagen." >&2; exit 1; }
  echo "Public-Docs-QS check: ok (README · CLI · web/ · pub.dev)"
}

cmd_attest() {
  cmd_check
  git -C "$ROOT" rev-parse HEAD > "$ATTEST"
  echo "Öffentliche Docs als aktuell & aufbaukonform bestätigt für $(cat "$ATTEST")."
  echo "Hinweis: attest = README, CLI-Hilfe, web/ und pub.dev-Beschreibung GELESEN und gegen den Repo-Stand geprüft."
}

cmd_attested() { [ -f "$ATTEST" ] && cat "$ATTEST" || true; }

case "${1:-}" in
  check)    cmd_check ;;
  attest)   cmd_attest ;;
  attested) cmd_attested ;;
  *) echo "usage: $0 {check|attest|attested}" >&2; exit 2 ;;
esac
