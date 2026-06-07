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
WEBPAGE="$ROOT/web/src/pages/index.astro"   # Astro-Quelle der Startseite (Single Source des Markups)
PUBSPEC="$ROOT/packages/loam_cli/pubspec.yaml"
PKGREADME="$ROOT/packages/loam_cli/README.md"
PKGCHANGELOG="$ROOT/packages/loam_cli/CHANGELOG.md"
VERSIONDART="$ROOT/packages/loam_cli/lib/src/version.dart"  # in-code Versionsspiegel

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
  # Anti-Vokabular über die Web-Quelle: Astro-Pages/-Components, Markdown, CSS und
  # (falls gebaut) HTML. node_modules/ und dist/ (Build-Output) werden ausgespart —
  # die Quelle ist deterministisch immer vorhanden, der Output ist daraus abgeleitet.
  while IFS= read -r f; do
    local hits; hits="$(antivocab "$f")"
    if [ -n "$hits" ]; then note "Anti-Vokabular in ${f#$ROOT/}:"; echo "$hits"; fi
  done < <(find "$WEB" \( -path '*/node_modules/*' -o -path '*/dist/*' -o -path '*/.astro/*' \) -prune \
                 -o \( -name '*.astro' -o -name '*.md' -o -name '*.html' -o -name '*.css' \) -type f -print 2>/dev/null)
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
    # Die pub.dev-Paketseite MUSS den einfachsten Install-Pfad zeigen.
    grep -qF -- "dart pub global activate loam" "$PKGREADME" \
      || note "Package-README fehlt pub.dev-Install-Zeile: dart pub global activate loam"
  else
    note "Package-README fehlt (pub.dev rendert sie)"
  fi
  return 0
}

# Versions-Sync: pubspec `version` ist die EINE Quelle. CHANGELOG-Top und der
# Website-Versions-Chip dürfen nicht hinterherhinken (genau die Drift-Klasse,
# die sonst beim Release still auf pub.dev/getloam.dev landet).
check_version_sync() {
  [ -f "$PUBSPEC" ] || return 0
  local ver
  ver="$(sed -nE 's/^version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+[^[:space:]]*).*$/\1/p' "$PUBSPEC" | head -1)"
  if [ -z "$ver" ]; then note "pubspec.yaml: keine semver version gefunden"; return 0; fi

  if [ -f "$PKGCHANGELOG" ]; then
    local clver
    clver="$(grep -m1 -oE '^##[[:space:]]+[0-9]+\.[0-9]+\.[0-9]+[^[:space:]]*' "$PKGCHANGELOG" \
             | sed -E 's/^##[[:space:]]+//')"
    [ "$clver" = "$ver" ] || note "CHANGELOG-Top ($clver) ≠ pubspec version ($ver)"
  else
    note "Package-CHANGELOG fehlt (pub.dev rendert ihn)"
  fi

  if [ -f "$WEBPAGE" ]; then
    grep -qF -- "v$ver" "$WEBPAGE" || note "Website-Versions-Chip ≠ v$ver (in ${WEBPAGE#$ROOT/})"
  fi

  # In-code Versionsspiegel: die AOT-Binary (Homebrew/pub global) hat keine
  # pubspec zur Laufzeit, darum ist die Version als `loamVersion` einkompiliert.
  # Sie MUSS der pubspec-Version entsprechen, sonst zeigt der Scan-Footer eine
  # falsche Version (genau die Drift, die diese Schranke verhindert).
  if [ -f "$VERSIONDART" ]; then
    local vd
    vd="$(sed -nE "s/^const String loamVersion = '([^']+)';.*/\1/p" "$VERSIONDART" | head -1)"
    [ "$vd" = "$ver" ] || note "version.dart loamVersion ($vd) ≠ pubspec version ($ver)"
  else
    note "version.dart fehlt (in-code Versionsquelle für die kompilierte Binary)"
  fi
  return 0
}

check_brand() {
  # Corporate-Design: EINE Quelle (assets/brand/tokens.json). Drift verhindern,
  # indem Off-Token-/Legacy-Farben in den Brand-Quellen + der Website verboten sind.
  local legacy='282420|6A635A|7A7064|4A443C|ECE9E1|F2F2F2'
  for f in "$WEBPAGE" "$ROOT/assets/brand/_svg/build.py" \
           "$ROOT/assets/brand/_ascii/gen.py" "$ROOT/assets/brand/_svg/wordmark_from_font.py"; do
    [ -f "$f" ] || continue
    local h; h="$(grep -niE "#($legacy)" "$f" || true)"
    if [ -n "$h" ]; then note "Off-Token-/Legacy-Farbe in ${f#$ROOT/}:"; echo "$h"; fi
  done
  # Token-Werte müssen in der Website-Quelle vorkommen (Konsistenz zum Logo)
  [ -f "$WEBPAGE" ] || note "Website-Quelle fehlt: ${WEBPAGE#$ROOT/}"
  for v in 88C840 564F47 ECEAE3 101014; do
    grep -iqF "$v" "$WEBPAGE" 2>/dev/null || note "Token #$v fehlt in ${WEBPAGE#$ROOT/}"
  done
  return 0
}

cmd_check() {
  fail=0
  check_readme; check_cli; check_web; check_pub; check_brand; check_version_sync
  [ "$fail" -eq 0 ] || { echo "Public-Docs-QS (check) fehlgeschlagen." >&2; exit 1; }
  echo "Public-Docs-QS check: ok (README · CLI · web/ · pub.dev · brand-tokens · version-sync)"
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
