#!/usr/bin/env bash
# Local release build + publish for loam (issue #15).
#
# The release binaries are NOT built on GitHub runners any more (Actions
# minutes are scarce). This script builds them where the platforms live:
#
#   macOS arm64   this Mac, `dart compile exe`
#   Linux x86_64  test-lab VM `ubu`  (via ~/.claude/bin/labctl)
#   Windows x64   test-lab VM `win` (via ~/.claude/bin/labctl)
#
# and then (unless --dry-run) attaches the archives + `.sha256` files to the
# GitHub release and renders the Homebrew formula into the tap repo.
#
# The asset names and the `.sha256` format (bare 64-char hex digest + newline)
# are a contract with the self-updater, see
# packages/loam_cli/lib/src/update/integrity.dart (`binaryAssetName`,
# `parseSha256File`) and tool/homebrew/loam.rb.tmpl. Do not rename them.
#
# Usage:
#   tool/release-local.sh [--dry-run] [--ref <git-ref>] [--only mac,linux,windows] <tag>
#
#   <tag>       release tag, e.g. v0.1.16; must match packages/loam_cli/pubspec.yaml
#               at --ref (default: the tag; with --dry-run the tag may not exist
#               yet, then --ref defaults to HEAD).
#   --dry-run   build + verify + render the formula, upload NOTHING (no release,
#               no asset, no tap push). Output lands in the printed work dir.
#
# The pub.dev publish stays on GitHub (.github/workflows/release.yml, OIDC,
# runs on the tag push) and is independent of this script.
set -euo pipefail

RELEASE_REPO="silvio-l/loam"
TAP_REPO="silvio-l/homebrew-loam"
LABCTL="${LABCTL:-$HOME/.claude/bin/labctl}"
GUEST_TIMEOUT="${GUEST_TIMEOUT:-1500}"

DRY=0; REF=""; ONLY="mac,linux,windows"; TAG=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1 ;;
    --ref) REF="$2"; shift ;;
    --only) ONLY="$2"; shift ;;
    -h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) TAG="$1" ;;
  esac
  shift
done
[ -n "$TAG" ] || { echo "usage: $0 [--dry-run] [--ref REF] [--only LIST] <tag>" >&2; exit 2; }
case "$TAG" in v[0-9]*) ;; *) echo "tag must look like v1.2.3: $TAG" >&2; exit 2 ;; esac
VERSION="${TAG#v}"

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
if [ -z "$REF" ]; then
  if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then REF="$TAG"
  elif [ "$DRY" = 1 ]; then REF="HEAD"
  else echo "tag $TAG does not exist locally; create + push it first" >&2; exit 1; fi
fi

# The version baked into the binary comes from pubspec.yaml: it has to be the tag.
PUB_VERSION="$(git show "$REF:packages/loam_cli/pubspec.yaml" | sed -n 's/^version: *//p' | head -1 | tr -d '[:space:]')"
[ "$PUB_VERSION" = "$VERSION" ] || { echo "pubspec version $PUB_VERSION at $REF != tag $TAG" >&2; exit 1; }
if [ "$DRY" = 0 ]; then
  [ -z "$(git status --porcelain --untracked-files=no)" ] || { echo "working tree not clean" >&2; exit 1; }
  [ "$(git rev-parse "$REF^{commit}")" = "$(git rev-parse "refs/tags/$TAG^{commit}")" ] \
    || { echo "--ref must be the tag commit for a real release" >&2; exit 1; }
fi

# Every platform builds with the Dart SDK pinned in the pub.dev workflow (#94),
# so the binaries match the published package. A guest with another SDK aborts.
DART_PIN="$(git show "$REF:.github/workflows/release.yml" | sed -n "s/^ *sdk: *'\\([0-9][0-9.]*\\)'.*/\\1/p" | head -1)"
[ -n "$DART_PIN" ] || { echo "no Dart sdk pin found in .github/workflows/release.yml at $REF" >&2; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/loam-release.XXXXXX")"
DIST="$WORK/dist"; mkdir -p "$DIST"
echo "== loam $VERSION (ref $REF, Dart $DART_PIN, dry-run=$DRY), work dir $WORK"
git archive --format=tar.gz -o "$WORK/src.tar.gz" "$REF" packages/loam_cli

want() { case ",$ONLY," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }
fail=0
note() { echo "-- $*"; }

sha_of() { shasum -a 256 "$1" | awk '{print $1}'; }

# ---- macOS (local) -------------------------------------------------------
build_mac() {
  local d="$WORK/mac"; mkdir -p "$d"; tar xzf "$WORK/src.tar.gz" -C "$d"
  ( cd "$d/packages/loam_cli"
    dart --version 2>&1 | sed 's/^/   /'
    dart --version 2>&1 | grep -q "^Dart SDK version: $DART_PIN " \
      || { echo "macOS: Dart SDK is not the pinned $DART_PIN" >&2; exit 1; }
    dart pub get >/dev/null
    mkdir -p dist
    # The define marks the official release build: only such a binary replaces
    # itself on update; a local `dart compile exe` never does (#9).
    dart compile exe -Dloam.release_binary=true bin/loam.dart -o dist/loam >/dev/null
    ./dist/loam --version | head -1 | grep -qx "loam $VERSION"
    COPYFILE_DISABLE=1 tar czf "$DIST/loam-macos-arm64.tar.gz" -C dist loam )
}

# ---- guests (Linux / Windows) ---------------------------------------------
# Source goes in with --push, the finished archive comes back with --pull.
# `labctl run` executes in the guest's interactive session as user `tester`.
build_linux() {
  local guest_script="$WORK/build-linux.sh"
  cat > "$guest_script" <<EOS
set -e
rm -rf loam-build && mkdir loam-build && cd loam-build
tar xzf ../loam-src.tar.gz
cd packages/loam_cli
dart --version 2>&1
dart --version 2>&1 | grep -q "^Dart SDK version: $DART_PIN " \
  || { echo "Linux: Dart SDK is not the pinned $DART_PIN" >&2; exit 1; }
dart pub get >/dev/null
mkdir -p dist
dart compile exe -Dloam.release_binary=true bin/loam.dart -o dist/loam >/dev/null
./dist/loam --version | head -1 | grep -qx "loam $VERSION"
tar czf ../../../loam-linux-x86_64.tar.gz -C dist loam
EOS
  "$LABCTL" run ubu --timeout "$GUEST_TIMEOUT" \
    --push "$WORK/src.tar.gz=loam-src.tar.gz" \
    --push "$guest_script=loam-build.sh" \
    --pull "loam-linux-x86_64.tar.gz=$DIST/loam-linux-x86_64.tar.gz" \
    -- 'bash loam-build.sh'
}

build_windows() {
  local guest_script="$WORK/build-windows.ps1"
  cat > "$guest_script" <<EOS
\$ErrorActionPreference = 'Stop'
Set-Location \$HOME
if (Test-Path loam-build) { Remove-Item -Recurse -Force loam-build }
New-Item -ItemType Directory loam-build | Out-Null
tar xzf loam-src.tar.gz -C loam-build
Set-Location loam-build/packages/loam_cli
# `dart --version` prints to stderr; PowerShell 5.1 turns redirected native
# stderr into error records, so relax the preference around the capture.
\$ErrorActionPreference = 'Continue'
\$dv = (dart --version 2>&1 | ForEach-Object { \$_.ToString() }) -join ' '
\$ErrorActionPreference = 'Stop'
\$dv
if (-not \$dv.StartsWith('Dart SDK version: $DART_PIN ')) { throw 'Windows: Dart SDK is not the pinned $DART_PIN' }
dart pub get | Out-Null
if (\$LASTEXITCODE -ne 0) { throw 'dart pub get failed' }
New-Item -ItemType Directory dist | Out-Null
# PowerShell splits an unquoted -Dloam.x=y at the dot, so the define is quoted.
dart compile exe '-Dloam.release_binary=true' bin/loam.dart -o dist/loam.exe | Out-Null
if (\$LASTEXITCODE -ne 0) { throw 'dart compile exe failed' }
\$v = (& ./dist/loam.exe --version | Select-Object -First 1)
if (\$v -ne 'loam $VERSION') { throw "unexpected version: \$v" }
Set-Location dist
tar -a -cf ../../../../loam-windows-x86_64.zip loam.exe
if (\$LASTEXITCODE -ne 0) { throw 'zip failed' }
EOS
  "$LABCTL" run win --timeout "$GUEST_TIMEOUT" \
    --push "$WORK/src.tar.gz=C:/Users/tester/loam-src.tar.gz" \
    --push "$guest_script=C:/Users/tester/loam-build.ps1" \
    --pull "C:/Users/tester/loam-windows-x86_64.zip=$DIST/loam-windows-x86_64.zip" \
    -- 'powershell -NoProfile -ExecutionPolicy Bypass -File C:/Users/tester/loam-build.ps1'
}

run_step() {
  local name="$1"; shift
  note "build $name"
  if "$@"; then note "$name: ok"; else note "$name: FAILED"; fail=1; fi
}
want mac     && run_step macos   build_mac
want linux   && run_step linux   build_linux
want windows && run_step windows build_windows
[ "$fail" = 0 ] || { echo "a platform build failed; nothing uploaded (work dir $WORK)" >&2; exit 1; }

# ---- checksums ------------------------------------------------------------
# Bare hex digest + newline, exactly what the former workflow wrote and what
# parseSha256File() reads.
for f in "$DIST"/loam-*.tar.gz "$DIST"/loam-*.zip; do
  [ -f "$f" ] || continue
  sha_of "$f" > "$f.sha256"
  grep -Eq '^[0-9a-f]{64}$' "$f.sha256" || { echo "bad checksum file for $f" >&2; exit 1; }
done
ls -l "$DIST"

# Self-update + Homebrew need these two; fail early if one is missing.
need=(); want mac && need+=(loam-macos-arm64.tar.gz); want linux && need+=(loam-linux-x86_64.tar.gz)
for a in ${need[@]+"${need[@]}"}; do
  [ -s "$DIST/$a" ] && [ -s "$DIST/$a.sha256" ] || { echo "missing asset $a" >&2; exit 1; }
  tar tzf "$DIST/$a" | grep -qx loam || { echo "$a does not contain 'loam'" >&2; exit 1; }
done

# ---- Homebrew formula -----------------------------------------------------
if want mac && want linux; then
  sha() { tr -d '[:space:]' < "$DIST/$1.sha256"; }
  sed -e "s|__VERSION__|${VERSION}|g" \
      -e "s|__SHA_MACOS_ARM64__|$(sha loam-macos-arm64.tar.gz)|g" \
      -e "s|__SHA_LINUX_X86_64__|$(sha loam-linux-x86_64.tar.gz)|g" \
      tool/homebrew/loam.rb.tmpl > "$WORK/loam.rb"
  if grep -q '__[A-Z_0-9]*__' "$WORK/loam.rb"; then echo "formula has unrendered placeholders" >&2; exit 1; fi
  ruby -c "$WORK/loam.rb" >/dev/null 2>&1 || note "ruby syntax check skipped/failed (ruby missing?)"
  note "formula rendered: $WORK/loam.rb"
fi

if [ "$DRY" = 1 ]; then
  echo "== DRY RUN complete: nothing uploaded. Assets in $DIST"
  exit 0
fi

# ---- publish --------------------------------------------------------------
want mac && want linux || { echo "a real release needs mac and linux" >&2; exit 1; }
command -v gh >/dev/null || { echo "gh missing" >&2; exit 1; }

if ! gh release view "$TAG" --repo "$RELEASE_REPO" >/dev/null 2>&1; then
  gh release create "$TAG" --repo "$RELEASE_REPO" --verify-tag --title "$TAG" --generate-notes
fi
# .sha256 files are required: a standalone binary only updates itself after the
# downloaded archive matches its checksum (#9).
gh release upload "$TAG" --repo "$RELEASE_REPO" --clobber "$DIST"/loam-*

content_b64="$(base64 < "$WORK/loam.rb" | tr -d '\n')"
existing_sha="$(gh api "repos/$TAP_REPO/contents/Formula/loam.rb" --jq .sha 2>/dev/null || true)"
args=(--method PUT "repos/$TAP_REPO/contents/Formula/loam.rb"
      -f "message=chore(formula): loam $VERSION"
      -f "content=$content_b64")
[ -n "$existing_sha" ] && args+=(-f "sha=$existing_sha")
gh api "${args[@]}" --jq '.commit.sha' | sed 's/^/Formula committed to tap: /'
echo "== release $TAG published"
