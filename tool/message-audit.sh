#!/usr/bin/env bash
# message-audit.sh — SOFT "agent-proof" audit of loam's finding messages.
#
# loam's output is consumed by AI agents as well as humans. A finding that
# states only a bare fact leaves an interpretation gap an agent fills itself —
# the documented root cause of real mis-triage ("those are just build()
# methods", "that cycle is a standard pattern, not a bug"). The HARD contract
# (test/model/agent_proof_contract_test.dart) deterministically guarantees that
# every finding carries a non-empty `kind` + `remedy`. It cannot judge whether
# the PROSE is actually persuasive and un-rationalisable — that is what this
# script does.
#
# It runs loam against the fixtures that trigger each live rule, extracts one
# representative finding per (ruleId, kind), and asks an LLM whether an agent
# could misread, undercount, or argue away each message/remedy. ADVISORY and
# NON-BLOCKING — never wire it into a git hook (an LLM is non-deterministic and
# costs tokens; CONTEXT.md Invariant 2). Run it after changing rule messages.
#
#   tool/message-audit.sh            Print the message catalogue + a ready
#   tool/message-audit.sh --print    review prompt (read it, or hand to an agent).
#   tool/message-audit.sh --llm      Run it through the `claude` CLI on a cheap
#                                    model. Uses your Claude SUBSCRIPTION (the
#                                    logged-in session), NOT the pay-per-token
#                                    API (honours CLAUDE_CODE_OAUTH_TOKEN too).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG="$ROOT/packages/loam_cli"
CLI="$PKG/bin/loam.dart"
MODEL="${LOAM_AUDIT_MODEL:-claude-haiku-4-5-20251001}"  # cheap by default

# Fixtures chosen to exercise every live rule at least once.
FIXTURES=(
  "test/fixtures/unused_exports_fixture"
  "test/fixtures/circular_deps_fixture"
  "test/fixtures/complexity_hotspots_fixture"
)

# --- 1. Collect one representative finding per (ruleId, kind) -----------------
catalogue="$(mktemp)"
raw="$(mktemp)"
for fx in "${FIXTURES[@]}"; do
  ( cd "$PKG" && dart run bin/loam.dart scan --format json -p "$fx" 2>/dev/null ) >> "$raw" || true
  echo "" >> "$raw"  # separate JSON documents
done

python3 - "$raw" "$catalogue" <<'PY'
import json, sys
raw_path, out_path = sys.argv[1], sys.argv[2]
seen = {}
for chunk in open(raw_path).read().split('\n{'):
    chunk = chunk.strip()
    if not chunk:
        continue
    if not chunk.startswith('{'):
        chunk = '{' + chunk
    try:
        doc = json.loads(chunk)
    except Exception:
        continue
    for f in doc.get('findings', []):
        key = (f.get('ruleId'), f.get('kind'))
        if key in seen:
            continue
        seen[key] = f
with open(out_path, 'w') as out:
    for (rule, kind), f in sorted(seen.items(), key=lambda kv: (kv[0][0] or '', kv[0][1] or '')):
        out.write(f"### ruleId={rule}  kind={kind}\n")
        out.write(f"message: {f.get('message')}\n")
        out.write(f"remedy : {f.get('remedy')}\n\n")
PY

# --- 2. Assemble the review prompt -------------------------------------------
prompt="$(mktemp)"
{
  cat <<'EOF'
You are an "agent-proofing" auditor for loam.dev, a Dart/Flutter code-intelligence
CLI whose findings are consumed by AI coding agents as well as humans.

A finding is AGENT-PROOF when an agent reading it CANNOT plausibly:
  (a) misclassify or miscount it (e.g. guess "build() vs logic" wrongly),
  (b) understate or dismiss it ("that's just a standard pattern / framework
      noise / not a real bug"), or
  (c) be left without a concrete, verifiable next action.

Below is loam's current message catalogue: one representative finding per
(ruleId, kind), with its `message` and its `remedy`.

For EACH entry, judge:
  1. Does `message` state the fact unambiguously AND classify it so the agent
     has no interpretation gap to fill?
  2. Does `remedy` give a concrete, imperative action — and where a common
     rationalisation exists, does it pre-empt it explicitly?
  3. Could a motivated agent still argue this away? If so, HOW — quote the gap.

Report per entry:
  [VERDICT] ruleId/kind — <weakness, quoting the exact wording> -> <concrete rewrite>
VERDICT in {AGENT-PROOF, WEAK (rationalisable), GAP (missing classification or
action)}. Be specific and quote. End with a prioritized list of the messages
most in need of hardening.

## Current message catalogue
EOF
  cat "$catalogue"
} > "$prompt"

case "${1:-}" in
  --llm)
    if command -v claude >/dev/null 2>&1; then
      echo "→ message-audit: running the soft check via claude ($MODEL) …" >&2
      claude -p "$(cat "$prompt")" --model "$MODEL"
    else
      echo "✗ message-audit: 'claude' CLI not found — printing the bundle instead." >&2
      cat "$prompt"
    fi
    ;;
  ""|--print)
    cat "$prompt"
    ;;
  *)
    echo "usage: message-audit.sh [--print | --llm]" >&2
    rm -f "$prompt" "$catalogue" "$raw"; exit 2
    ;;
esac
rm -f "$prompt" "$catalogue" "$raw"
