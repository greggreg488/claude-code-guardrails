#!/usr/bin/env bash
# smoke.sh — feed each hook a representative event and assert it exits 0 and emits
# either nothing or valid JSON. Contract-safety test ("doesn't crash"), not behavior.
set -uo pipefail
cd "$(dirname "$0")/.."
fail=0

check() {  # $1 name  $2 stdin-json  $3 hook-relpath
  local name="$1" input="$2" hook="$3" out rc
  out="$(printf '%s' "$input" | bash "$hook" 2>/dev/null)"; rc=$?
  if [ "$rc" -ne 0 ]; then echo "FAIL $name (exit $rc)"; fail=1; return; fi
  # UserPromptSubmit hooks may emit plain text (added as context) OR JSON. Only
  # validate as JSON when the output actually looks like a JSON object.
  case "$out" in
    "{"*) printf '%s' "$out" | jq . >/dev/null 2>&1 || { echo "FAIL $name (malformed JSON)"; fail=1; return; } ;;
  esac
  echo "ok   $name"
}

check verify-before-assert \
  '{"prompt":"which model is cheapest and best? recommend one"}' \
  hooks/verify-before-assert.sh
check escalate-to-best-model \
  '{"prompt":"design the architecture for this system — an irreversible decision"}' \
  hooks/escalate-to-best-model.sh
check no-phantom-conflict \
  '{"messages":[{"role":"assistant","content":"Which is authoritative, A or B? You decide between them."}]}' \
  hooks/no-phantom-conflict-escalation.sh
check stale-memory \
  '{}' \
  hooks/stale-memory-warning.sh
check planner-executor \
  '{"tool_name":"Write","tool_input":{"file_path":"/tmp/x.py"}}' \
  hooks/planner-executor-separation.sh
check subagent-singleton-lock \
  '{"tool_name":"Agent","tool_input":{"subagent_type":"codex:rescue"}}' \
  hooks/subagent-singleton-lock.sh
check no-clock-drift \
  '{"tool_name":"Write","tool_input":{"file_path":"/tmp/state.json"}}' \
  hooks/no-clock-drift-guard.sh
check external-egress-pii \
  '{"tool_input":{"text":"my api_key=abcdef123456 here"}}' \
  hooks/external-egress-pii-guard.sh

if [ "$fail" -eq 0 ]; then echo "ALL OK"; else echo "SOME FAILED"; fi
exit $fail
