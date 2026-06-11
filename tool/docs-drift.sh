#!/usr/bin/env bash
# docs-drift.sh — SOFT semantic-drift check for the public docs. Companion to the
# deterministic tool/docs-attest.sh.
#
# docs-attest.sh is the HARD gate (structure, version-sync, anti-vocab, shipped-
# status) — deterministic, 0 token, runs in git hooks + the dart-test gate.
# It is blind to SEMANTIC staleness: prose/examples that describe old behaviour,
# understate shipped features, or freeze at an old version ("0.1.0 — one rule").
#
# This script assembles the IMPLEMENTATION ground truth (derived from code) plus
# the public-facing docs and asks an LLM to flag exactly that drift. It is
# ADVISORY and NON-BLOCKING — never wire it into a git hook (an LLM is non-
# deterministic and costs tokens). Run it before cutting a release, or after
# landing notable feature work.
#
#   tool/docs-drift.sh            Print the ground truth + doc bundle + a ready
#                                 review prompt (read it, or pipe to any LLM /
#                                 hand to an agent that can read the repo).
#   tool/docs-drift.sh --llm      Additionally run it through the `claude` CLI
#                                 with a cheap model and print the drift report.
#
# Free-tier-safe: human-invoked, bounded, opt-in LLM on a cheap model.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$ROOT/packages/loam_cli/bin/loam.dart"
RUNNER="$ROOT/packages/loam_cli/lib/src/runner/analysis_runner.dart"
PUBSPEC="$ROOT/packages/loam_cli/pubspec.yaml"
MODEL="${LOAM_DRIFT_MODEL:-claude-haiku-4-5-20251001}"  # cheap by default

# --- 1. Ground truth (deterministic, 0 token) --------------------------------
version="$(sed -nE 's/^version:[[:space:]]*([0-9][^[:space:]]*).*/\1/p' "$PUBSPEC" | head -1)"
live_rules="$(awk '/fullRegistryIds = \[/{f=1;next} f&&/\]/{f=0} f' "$RUNNER" \
              | grep -oE "'[a-z][a-z-]*'" | tr -d "'" | paste -sd',' - | sed 's/,/, /g')"
# Command -> live|stub via the notImplemented-block heuristic (same as docs-attest).
cmd_lines="$(perl -ne 'if(/name = \x27([a-z][a-z-]*)\x27/){ if(defined $c){print "  - loam $c: ".($s?"coming soon (stub)":"live")."\n"} $c=$1;$s=0;next } $s=1 if /notImplemented/; END{ print "  - loam $c: ".($s?"coming soon (stub)":"live")."\n" if defined $c }' "$CLI")"

# --- 2. Public docs whose PROSE must track the implementation ----------------
# Inlined (where drift historically lives):
INLINE_DOCS=(
  "README.md"
  "packages/loam_cli/README.md"
  "docs/developer-guide.md"
  "packages/loam_cli/CHANGELOG.md"
)
# Also user-facing — listed so an agent with repo access reviews them too:
LISTED_DOCS=(
  "web/src/pages/index.astro · web/src/pages/de/index.astro"
  "web/src/pages/rules.astro · web/src/pages/de/rules.astro"
  "web/src/pages/how-it-works.astro · web/src/pages/de/how-it-works.astro"
  "packages/loam_cli/bin/loam.dart (CLI --help / command descriptions)"
  "packages/loam_cli/pubspec.yaml (description field)"
)

# --- 3. Assemble the review prompt + bundle ----------------------------------
prompt="$(mktemp)"
{
  cat <<EOF
You are a documentation-drift auditor for loam.dev. Below is the CURRENT
implementation ground truth (derived from code), then the public-facing docs.

Find prose, examples, or claims that CONTRADICT, UNDERSTATE, or OMIT what the
code actually does now — the semantic staleness a structural linter cannot see
(e.g. a README still saying "0.1.0 — one rule live" when three rules ship).

Rules of judgement:
- Anything a doc presents as live/available/now that is NOT in the ground truth
  below is drift. Anything in the ground truth not reflected in user-facing docs
  is drift.
- A genuinely historical note ("live since 0.1.3") is fine; a CURRENT-STATE
  claim pinned to an old version ("available now (0.1.0)") is drift.
- Version numbers, the live-rule set, and the live-vs-coming-soon command set
  must be consistent everywhere they appear.

Report per file:
  [SEVERITY] <relative/path> ~line — <stale claim vs reality> -> <concrete fix>
SEVERITY in {BLOCKER (contradicts shipped reality / misleads), SHOULD-FIX
(omits/understates shipped features), NIT (wording / stale version label)}.
List clean files in one line. End with a prioritized fix order. Be specific —
quote the exact stale wording and cite line numbers.

## Implementation ground truth (source of truth)
- Version being released: $version
- Live analysis rules (AnalysisRunner.fullRegistryIds): $live_rules
- CLI commands:
$cmd_lines
- Output formats: human, sarif, json, markdown, html. HTML writes a file
  (loam-report.html; --output overrides) and auto-opens in the browser on
  interactive runs (--no-open skips; auto-off when piped or under CI). The other
  formats stream to stdout.

## Also review (an agent with repo access should open these too)
EOF
  for d in "${LISTED_DOCS[@]}"; do echo "- $d"; done
  echo ""
  echo "## Inlined public docs"
  for d in "${INLINE_DOCS[@]}"; do
    [ -f "$ROOT/$d" ] || continue
    echo ""
    echo "===== FILE: $d ====="
    cat "$ROOT/$d"
  done
} > "$prompt"

if [ "${1:-}" = "--llm" ]; then
  if command -v claude >/dev/null 2>&1; then
    echo "→ docs-drift: running the soft check via claude ($MODEL) …" >&2
    claude -p "$(cat "$prompt")" --model "$MODEL"
  else
    echo "✗ docs-drift: 'claude' CLI not found." >&2
    echo "  Pipe the bundle to any LLM instead:  tool/docs-drift.sh | <your-llm>" >&2
    cat "$prompt"
  fi
else
  cat "$prompt"
fi
rm -f "$prompt"
