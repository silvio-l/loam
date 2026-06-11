#!/usr/bin/env bash
# tool/e2e.sh — End-to-end CLI verification harness for loam.
#
# Manual PRE-PUSH gate (NOT a git hook): run it yourself before every push.
# It compiles the real AOT binary (`dart compile exe`) and exercises every
# command × format × key error/steering constellation as a SUBPROCESS — the
# only layer that catches AOT/SDK/PATH packaging bugs (e.g. the Flutter
# SDK-root crash that an in-process `dart test` cannot see). It then runs the
# in-process matrix (`dart test test/e2e`) for breadth/speed.
#
# Assertions deliberately check EXIT CODES + stable structural markers (rule
# IDs, metric presence, steering keywords) — never full message prose — so the
# harness survives message-wording changes.
#
# Usage:   tool/e2e.sh
# Exit:    0 = every constellation behaved as expected; 1 = at least one did not.
set -uo pipefail

PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../packages/loam_cli" && pwd)"
cd "$PKG_DIR" || { echo "cannot cd into $PKG_DIR"; exit 1; }

PASS=0; FAIL=0; SKIP=0
BIN="$(mktemp -t loam-e2e-bin.XXXXXX)"
WORK="$(mktemp -d -t loam-e2e-work.XXXXXX)"
cleanup() { rm -f "$BIN"; rm -rf "$WORK"; }
trap cleanup EXIT

c_grn=$'\033[32m'; c_red=$'\033[31m'; c_yel=$'\033[33m'; c_dim=$'\033[2m'; c_off=$'\033[0m'
ok()   { PASS=$((PASS+1)); printf '  %s✓%s %s\n' "$c_grn" "$c_off" "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  %s✗%s %s\n      %s%s%s\n' "$c_red" "$c_off" "$1" "$c_dim" "$2" "$c_off"; }
skip() { SKIP=$((SKIP+1)); printf '  %s∼%s SKIP %s — %s\n' "$c_yel" "$c_off" "$1" "$2"; }
phase(){ printf '\n%s▸ %s%s\n' "$c_dim" "$1" "$c_off"; }

# expect_exit <desc> <expected_code> -- <cmd...>
expect_exit() {
  local desc="$1" exp="$2"; shift 2; [ "${1:-}" = "--" ] && shift
  local out code
  out="$("$@" 2>&1)"; code=$?
  if [ "$code" -eq "$exp" ]; then ok "$desc (exit $code)"
  else bad "$desc" "expected exit $exp, got $code | ${out:0:180}"; fi
}

# expect_out <desc> <expected_code> <substring> -- <cmd...>
expect_out() {
  local desc="$1" exp="$2" needle="$3"; shift 3; [ "${1:-}" = "--" ] && shift
  local out code
  out="$("$@" 2>&1)"; code=$?
  if [ "$code" -eq "$exp" ] && printf '%s' "$out" | grep -qF -- "$needle"; then ok "$desc"
  else bad "$desc" "exit exp $exp got $code; needle '$needle' missing | ${out:0:180}"; fi
}

# expect_file <desc> <path> -- <cmd...>  (asserts exit 0..1 tolerated, file exists)
expect_file() {
  local desc="$1" path="$2"; shift 2; [ "${1:-}" = "--" ] && shift
  "$@" >/dev/null 2>&1
  if [ -f "$path" ]; then ok "$desc"; else bad "$desc" "expected file $path to exist"; fi
}

# ---------------------------------------------------------------------------
# Compile the real AOT binary — the layer in-process tests cannot exercise.
# ---------------------------------------------------------------------------
phase "Compiling AOT binary (dart compile exe)"
if ! dart compile exe bin/loam.dart -o "$BIN" >/dev/null 2>"$WORK/compile.err"; then
  echo "compile failed:"; cat "$WORK/compile.err"; exit 1
fi
ok "binary compiled"

# Fixtures ------------------------------------------------------------------
FIX="test/fixtures/unused_exports_fixture"          # read-only, has findings
CLEAN="$WORK/clean"                                  # synthetic clean project
mkdir -p "$CLEAN/lib"
cat > "$CLEAN/pubspec.yaml" <<'YML'
name: clean_project
environment:
  sdk: ">=3.0.0 <4.0.0"
YML
echo "// intentionally empty" > "$CLEAN/lib/clean.dart"

# ---------------------------------------------------------------------------
# scan × every format (against a fixture WITH findings → exit 1)
# ---------------------------------------------------------------------------
phase "scan × formats"
expect_out "scan --format human"    1 "unused-public-exports" -- "$BIN" scan --format human    -p "$FIX"
expect_out "scan --format json"     1 '"ruleId"'              -- "$BIN" scan --format json     -p "$FIX"
expect_out "scan --format sarif"    1 "sarif"                 -- "$BIN" scan --format sarif    -p "$FIX"
expect_out "scan --format markdown" 1 "unused-public-exports" -- "$BIN" scan --format markdown -p "$FIX"
expect_file "scan --format html writes report" "$WORK/r.html" -- "$BIN" scan --format html --no-open -o "$WORK/r.html" -p "$FIX"
expect_exit "scan on clean project → exit 0"   0 -- "$BIN" scan -p "$CLEAN"

# ---------------------------------------------------------------------------
# health (report command, always exit 0)
# ---------------------------------------------------------------------------
phase "health"
expect_exit "health on fixture → exit 0" 0 -- "$BIN" health -p "$FIX"
expect_exit "health on clean   → exit 0" 0 -- "$BIN" health -p "$CLEAN"

# ---------------------------------------------------------------------------
# gate — baseline/ratchet (default) and --absolute modes + full lifecycle
# ---------------------------------------------------------------------------
phase "gate"
expect_out "gate w/o baseline → exit 1 + steering" 1 "baseline.json is missing" -- "$BIN" gate -p "$CLEAN"
expect_exit "gate --absolute on clean (greenfield) → exit 0" 0 -- "$BIN" gate --absolute -p "$CLEAN"
expect_exit "gate --absolute on findings → exit 1"           1 -- "$BIN" gate --absolute -p "$FIX"

phase "gate lifecycle (baseline --write → gate green)"
FIXCOPY="$WORK/fixcopy"
cp -R "$FIX" "$FIXCOPY"
expect_exit "baseline --write → exit 0" 0 -- "$BIN" baseline --write -p "$FIXCOPY"
if [ -f "$FIXCOPY/baseline.json" ]; then ok "baseline.json written"; else bad "baseline.json written" "file missing after --write"; fi
expect_exit "gate after baseline write → exit 0"   0 -- "$BIN" gate     -p "$FIXCOPY"
expect_exit "baseline show with file → exit 0"     0 -- "$BIN" baseline -p "$FIXCOPY"

# ---------------------------------------------------------------------------
# init (scaffold loam.yaml)
# ---------------------------------------------------------------------------
phase "init"
INITDIR="$WORK/inittarget"; mkdir -p "$INITDIR/lib"
cat > "$INITDIR/pubspec.yaml" <<'YML'
name: init_target
environment:
  sdk: ">=3.0.0 <4.0.0"
YML
expect_exit "init → exit 0" 0 -- "$BIN" init -p "$INITDIR"
if [ -f "$INITDIR/loam.yaml" ]; then ok "loam.yaml scaffolded"; else bad "loam.yaml scaffolded" "file missing after init"; fi

# ---------------------------------------------------------------------------
# stub commands (coming soon) → EX_USAGE (64)
# ---------------------------------------------------------------------------
phase "stub commands"
expect_exit "slop (stub) → exit 64" 64 -- "$BIN" slop -p "$FIX"
expect_exit "fix  (stub) → exit 64" 64 -- "$BIN" fix  -p "$FIX"

# ---------------------------------------------------------------------------
# usage / error surfaces → EX_USAGE (64)
# ---------------------------------------------------------------------------
phase "usage errors"
expect_exit "unknown --format → exit 64"        64 -- "$BIN" scan --format bogus -p "$FIX"
expect_exit "two positionals → exit 64"         64 -- "$BIN" scan "$FIX" "$CLEAN"
expect_exit "unknown command → exit 64"         64 -- "$BIN" nonsense-command
expect_exit "--help → exit 0"                    0 -- "$BIN" --help

# ---------------------------------------------------------------------------
# SDK resolution layer — the today-bug regression. Binary-only; invisible to
# in-process tests.
# ---------------------------------------------------------------------------
phase "SDK resolution (regression for the Flutter-root crash)"

# (a) Unusable SDK → actionable steering, exit 78, NO stacktrace. Portable:
#     any dir without lib/_internal is "unusable".
NOTSDK="$WORK/not-an-sdk"; mkdir -p "$NOTSDK"
out="$(DART_SDK="$NOTSDK" "$BIN" scan -p "$FIX" 2>&1)"; code=$?
if [ "$code" -eq 78 ] \
   && printf '%s' "$out" | grep -qF "could not locate a usable Dart SDK" \
   && printf '%s' "$out" | grep -qF "DART_SDK=" \
   && ! printf '%s' "$out" | grep -qF "#0 "; then
  ok "unusable SDK → exit 78 + steering, no stacktrace"
else
  bad "unusable SDK → exit 78 + steering" "exit $code | ${out:0:200}"
fi

# (b) Flutter-only PATH (where `dart` is the wrapper) → must resolve into
#     bin/cache/dart-sdk and scan cleanly, NOT crash. Needs a Flutter install.
FLUTTER_BIN=""
if command -v flutter >/dev/null 2>&1; then
  fpath="$(command -v flutter)"
  if command -v readlink >/dev/null 2>&1; then fpath="$(readlink -f "$fpath" 2>/dev/null || echo "$fpath")"; fi
  cand="$(dirname "$fpath")"
  [ -x "$cand/dart" ] && FLUTTER_BIN="$cand"
fi
if [ -n "$FLUTTER_BIN" ] && [ -d "$FLUTTER_BIN/cache/dart-sdk" ]; then
  out="$(PATH="$FLUTTER_BIN:/usr/bin:/bin" env -u DART_SDK "$BIN" scan -p "$FIX" 2>&1)"; code=$?
  if [ "$code" -eq 1 ] \
     && printf '%s' "$out" | grep -qF "unused-public-exports" \
     && ! printf '%s' "$out" | grep -qF "PathNotFoundException"; then
    ok "Flutter-only PATH → resolves SDK, scans (exit 1), no crash"
  else
    bad "Flutter-only PATH → scans without crash" "exit $code | ${out:0:200}"
  fi
else
  skip "Flutter-only PATH regression" "no Flutter install with bin/cache/dart-sdk found"
fi

# ---------------------------------------------------------------------------
# In-process matrix (breadth/speed): exit-code contract for every command.
# ---------------------------------------------------------------------------
phase "in-process matrix (dart test test/e2e)"
if dart test test/e2e >/dev/null 2>"$WORK/dart-e2e.log"; then
  ok "dart test test/e2e passed"
else
  bad "dart test test/e2e" "$(tail -3 "$WORK/dart-e2e.log" | tr '\n' ' ')"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\n%s──────────────────────────────────────────%s\n' "$c_dim" "$c_off"
printf 'E2E: %s%d passed%s, %s%d failed%s, %s%d skipped%s\n' \
  "$c_grn" "$PASS" "$c_off" "$c_red" "$FAIL" "$c_off" "$c_yel" "$SKIP" "$c_off"
[ "$FAIL" -eq 0 ] || { echo "Push gate: BLOCKED — fix the failures above before pushing."; exit 1; }
echo "Push gate: OK — every CLI constellation behaved as expected."
