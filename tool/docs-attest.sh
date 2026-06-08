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
WEBPAGE="$ROOT/web/src/layouts/Layout.astro"  # Single Source des Chrome (Brand-Tokens, Versions-Chip, Footer-Links)
WEBPAGE_HOME_EN="$ROOT/web/src/pages/index.astro"
WEBPAGE_HOME_DE="$ROOT/web/src/pages/de/index.astro"
PUBSPEC="$ROOT/packages/loam_cli/pubspec.yaml"
PKGREADME="$ROOT/packages/loam_cli/README.md"
PKGCHANGELOG="$ROOT/packages/loam_cli/CHANGELOG.md"
VERSIONDART="$ROOT/packages/loam_cli/lib/src/version.dart"  # in-code Versionsspiegel
DEVGUIDE="$ROOT/docs/developer-guide.md"

# Anti-Vokabular (PCRE via perl -> portabel macOS/Linux). Generische Wörter
# bewusst ausgelassen, um False Positives in Prosa zu vermeiden.
ANTIVOCAB='(Firebase|Firestore|Crashlytics|\bLoam\b(?!\.dev))'
antivocab() { perl -ne "print \"  \$.: \$_\" if /$ANTIVOCAB/" "$1" 2>/dev/null || true; }

fail=0
note() { echo "  ✗ $1"; fail=1; }

check_readme() {
  # Pflicht-Marker aus der Spec (Single Source of Truth für den Aufbau)
  # Verwende den exakten Kommentar-Marker (<!-- required:start -->) damit andere
  # Marker-Blöcke (z. B. devguide-required:start) nicht irrtümlich mitgelesen werden.
  # SPEC ist bewusst gitignored (interne QS-Spec) -> in CI/Fresh-Clone abwesend.
  # Dann Marker-Check überspringen statt unter set -e an awk zu sterben.
  local markers=""
  [ -f "$SPEC" ] && markers="$(awk '/<!-- required:start -->/{f=1;next} /<!-- required:end -->/{f=0} f' "$SPEC" \
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

check_devguide() {
  # Developer & Tool Guide: docs/developer-guide.md
  # Pflicht-Marker aus der Spec (§6, devguide-required:start … devguide-required:end).
  [ -f "$DEVGUIDE" ] || { note "Developer-Guide fehlt: ${DEVGUIDE#$ROOT/}"; return; }

  local markers=""
  [ -f "$SPEC" ] && markers="$(awk '/devguide-required:start/{f=1;next} /devguide-required:end/{f=0} f' "$SPEC" \
                            | sed '/^[[:space:]]*$/d')"
  while IFS= read -r m; do
    [ -z "$m" ] && continue
    grep -qF -- "$m" "$DEVGUIDE" || note "Developer-Guide fehlt Pflicht-Marker: $m"
  done <<< "$markers"

  # Alle registrierten CLI-Commands müssen im Guide vorkommen (CLI ⊆ Guide).
  [ -f "$CLI" ] || return 0
  local cmds; cmds="$(grep -oE "name = '[a-z][a-z-]*'" "$CLI" \
                      | sed -E "s/name = '([a-z-]+)'/\1/" | sort -u || true)"
  while IFS= read -r c; do
    [ -z "$c" ] && continue
    grep -qF -- "loam $c" "$DEVGUIDE" || note "Developer-Guide: CLI-Command '$c' nicht dokumentiert"
  done <<< "$cmds"

  # Relative Links/Pfade im Guide existieren.
  local refs; refs="$( { grep -oE '\]\([^)]+\)' "$DEVGUIDE" | sed -E 's/\]\(([^)]+)\)/\1/'; } \
                       | sort -u || true )"
  while IFS= read -r r; do
    [ -z "$r" ] && continue
    case "$r" in http://*|https://*|mailto:*|\#*) continue ;; esac
    r="${r%%#*}"; r="${r%%\?*}"; [ -z "$r" ] && continue
    # Links in docs/ sind relativ zu docs/; auflösen gegen docs/-Verzeichnis.
    local target; target="$(cd "$ROOT/docs" && realpath -m "$r" 2>/dev/null || echo "")"
    [ -z "$target" ] && target="$ROOT/docs/$r"
    [ -e "$target" ] || note "Developer-Guide verweist auf fehlenden Pfad: $r"
  done <<< "$refs"

  # Anti-Vokabular
  local hits; hits="$(antivocab "$DEVGUIDE")"
  if [ -n "$hits" ]; then note "Anti-Vokabular in ${DEVGUIDE#$ROOT/}:"; echo "$hits"; fi

  # README muss den Guide verlinken (GitHub-erreichbar).
  grep -qF -- "docs/developer-guide.md" "$README" \
    || note "README verweist nicht auf Developer-Guide (docs/developer-guide.md)"

  # Website rendert den Guide als EIGENE Seite (Single-Source aus docs/, via
  # Astro-Content-Layer — keine duplizierte Kopie unter web/). Geprüft wird:
  #  (a) beide Sprachfassungen der Guide-Route existieren,
  #  (b) der Content-Layer liest die eine Quelle docs/developer-guide.md,
  #  (c) das Layout (Chrome) verlinkt die On-Site-Guide-Route.
  local guide_en="$ROOT/web/src/pages/developer-guide.astro"
  local guide_de="$ROOT/web/src/pages/de/developer-guide.astro"
  local guide_loader="$ROOT/web/src/content.config.ts"
  [ -f "$guide_en" ] || note "Website: EN Developer-Guide-Seite fehlt: web/src/pages/developer-guide.astro"
  [ -f "$guide_de" ] || note "Website: DE Developer-Guide-Seite fehlt: web/src/pages/de/developer-guide.astro"
  if [ -f "$guide_loader" ]; then
    grep -qF -- "developer-guide.md" "$guide_loader" \
      || note "Website: content.config.ts liest nicht docs/developer-guide.md (Single-Source verletzt)"
  else
    note "Website: web/src/content.config.ts fehlt (Guide-Content-Loader)"
  fi
  grep -qF -- "/developer-guide" "$WEBPAGE" \
    || note "Website-Quelle (Layout.astro) verlinkt nicht die On-Site-Guide-Route /developer-guide"

  return 0
}

check_pubdev_docs() {
  # pub.dev "Provide documentation" (20/20 Punkte) absichern:
  #  (a) Das Paket hat ein Example (10 Punkte).
  #  (b) Die public API ist dokumentiert (10 Punkte; ≥20% reicht für die Punkte,
  #      loam.dev hält 100% via Lint).
  local pkgdir="$ROOT/packages/loam_cli"
  local exdir="$pkgdir/example"

  # (a) Example — pana akzeptiert eines dieser Artefakte (Reihenfolge ~ pana).
  local has_example=0 cand
  for cand in \
    "$exdir/lib/main.dart" "$exdir/main.dart" "$exdir/example.dart" \
    "$exdir/loam.dart" "$exdir/lib/loam.dart" \
    "$exdir/README.md" "$exdir/readme.md" "$exdir/example.md"; do
    [ -f "$cand" ] && { has_example=1; break; }
  done
  [ "$has_example" -eq 1 ] \
    || note "pub.dev: kein Example gefunden — lege packages/loam_cli/example/README.md (oder example/main.dart) an"

  # (b) public-API-Doku: erzwungen durch den public_member_api_docs-Lint im
  # analyze-Gate. Hier nur der Guard, dass die Enforcement nicht still entfernt
  # wurde (sonst könnte die Doku-Coverage unbemerkt unter die pub.dev-Schwelle fallen).
  local aopts="$pkgdir/analysis_options.yaml"
  if [ -f "$aopts" ]; then
    grep -qE '^[[:space:]]*-[[:space:]]*public_member_api_docs[[:space:]]*$' "$aopts" \
      || note "analysis_options.yaml: Lint 'public_member_api_docs' fehlt — erzwingt die public-API-Doku für die pub.dev-Punktzahl"
  else
    note "packages/loam_cli/analysis_options.yaml fehlt (public-API-Doku-Enforcement)"
  fi
  return 0
}

check_i18n() {
  # i18n Hard-Checks (ab Issue 01, verschärft in Issue 07 auf ALLE Inhalts-Routen):
  #  (a) Jede Inhalts-Route hat BEIDE Sprachfassungen (EN + DE).
  #  (b) Layout.astro enthält hreflang-Alternates (das Muster prüfen, nicht die
  #      gebauten HTML-Seiten, damit der Check ohne Build läuft).
  #
  # CONTENT_ROUTES: slug-relative Pfad-Segmente (ohne führenden Slash).
  # Home: EN = pages/index.astro, DE = pages/de/index.astro.
  # Restliche: EN = pages/<slug>.astro, DE = pages/de/<slug>.astro.
  # Neuen Route hinzufügen: nur hier in die Liste eintragen.
  local pages_dir="$ROOT/web/src/pages"
  local -a CONTENT_ROUTES=("" "how-it-works" "rules" "privacy" "developer-guide")
  local route
  for route in "${CONTENT_ROUTES[@]}"; do
    if [ -z "$route" ]; then
      # Home: index.astro / de/index.astro
      local en_file="$pages_dir/index.astro"
      local de_file="$pages_dir/de/index.astro"
      local label="Home (/)"
    else
      local en_file="$pages_dir/${route}.astro"
      local de_file="$pages_dir/de/${route}.astro"
      local label="${route} (/${route})"
    fi
    [ -f "$en_file" ] || note "i18n: EN ${label} fehlt: ${en_file#$ROOT/}"
    [ -f "$de_file" ] || note "i18n: DE ${label} fehlt: ${de_file#$ROOT/}"
  done
  # Jede Seite leitet ihre hreflang-Tags aus Layout.astro ab (hreflangAlternates-Aufruf).
  [ -f "$WEBPAGE" ] && {
    grep -qF 'hreflangAlternates' "$WEBPAGE" \
      || note "i18n: Layout.astro ruft hreflangAlternates nicht auf (hreflang-Alternates fehlen)"
    grep -qF 'rel="alternate"' "$WEBPAGE" \
      || note "i18n: Layout.astro rendert keine hreflang-<link>-Tags"
  }
  return 0
}

check_privacy_footer() {
  # Privacy Hard-Check (ab Issue 04):
  #  Layout.astro muss einen Footer-Link auf /privacy (EN) UND /de/privacy (DE) enthalten.
  [ -f "$WEBPAGE" ] || { note "privacy-footer: Website-Quelle fehlt: ${WEBPAGE#$ROOT/}"; return; }
  grep -qF '/privacy' "$WEBPAGE" \
    || note "privacy-footer: Footer in Layout.astro verlinkt nicht /privacy (EN)"
  grep -qF '/de/privacy' "$WEBPAGE" \
    || note "privacy-footer: Footer in Layout.astro verlinkt nicht /de/privacy (DE)"
  # Privacy-Seiten müssen als Astro-Dateien existieren.
  local priv_en="$ROOT/web/src/pages/privacy.astro"
  local priv_de="$ROOT/web/src/pages/de/privacy.astro"
  [ -f "$priv_en" ] || note "privacy-footer: EN Privacy-Seite fehlt: web/src/pages/privacy.astro"
  [ -f "$priv_de" ] || note "privacy-footer: DE Privacy-Seite fehlt: web/src/pages/de/privacy.astro"
  return 0
}

cmd_check() {
  fail=0
  # public-docs-spec.md ist bewusst gitignored (interne QS-Spec, nicht nach
  # GitHub). Lokal vorhanden -> Marker-Checks laufen normal. Fehlt sie (Fresh
  # Clone ohne die lokale Spec), sichtbar überspringen statt still durchrutschen.
  [ -f "$SPEC" ] || echo "  ⚠ ${SPEC#$ROOT/} nicht vorhanden (lokal/gitignored) — Marker-Checks übersprungen." >&2
  check_readme; check_cli; check_web; check_pub; check_brand; check_version_sync; check_devguide; check_pubdev_docs; check_i18n; check_privacy_footer
  [ "$fail" -eq 0 ] || { echo "Public-Docs-QS (check) fehlgeschlagen." >&2; exit 1; }
  echo "Public-Docs-QS check: ok (README · CLI · web/ · pub.dev · brand-tokens · version-sync · developer-guide · pub-points · i18n · privacy-footer)"
}

cmd_attest() {
  cmd_check
  git -C "$ROOT" rev-parse HEAD > "$ATTEST"
  echo "Öffentliche Docs als aktuell & aufbaukonform bestätigt für $(cat "$ATTEST")."
  echo "Hinweis: attest = README, CLI-Hilfe, web/, pub.dev-Beschreibung und Developer-Guide GELESEN und gegen den Repo-Stand geprüft."
}

cmd_attested() { [ -f "$ATTEST" ] && cat "$ATTEST" || true; }

case "${1:-}" in
  check)    cmd_check ;;
  attest)   cmd_attest ;;
  attested) cmd_attested ;;
  *) echo "usage: $0 {check|attest|attested}" >&2; exit 2 ;;
esac
