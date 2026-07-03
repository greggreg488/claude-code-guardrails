#!/usr/bin/env bash
#
# subagent-singleton-lock.sh — PreToolUse (matcher: Agent)
#
# OPT-IN. Blocks dispatching a subagent whose type starts with a configured prefix
# while an instance of the backing process is already running — for tools that can't
# run concurrently (a singleton CLI, a single license seat, a shared external lock).
#
# FAIL-OPEN. Bypass 60 min: touch ~/.claude/state/guardrails_bypass
#
# Config (env, optional):
#   GUARDRAILS_SINGLETON_AGENT_PREFIX   subagent_type prefix to guard (default: "codex:")
#   GUARDRAILS_SINGLETON_PGREP          pgrep -f pattern to detect it (default: "codex exec")

PREFIX="${GUARDRAILS_SINGLETON_AGENT_PREFIX:-codex:}"
PGREP_PAT="${GUARDRAILS_SINGLETON_PGREP:-codex exec}"

allow_json() {
  if command -v jq >/dev/null 2>&1; then
    jq -cn '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}' 2>/dev/null \
      || printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
  else
    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
  fi
}
deny_json() {
  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg r "$1" '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":$r}}' 2>/dev/null \
      || allow_json
  else
    allow_json
  fi
}
fail_open() { allow_json; exit 0; }

sentinel="${HOME:-}/.claude/state/guardrails_bypass"
[ -z "${HOME:-}" ] && fail_open
[ -n "$(find "$sentinel" -mmin -60 2>/dev/null)" ] && { allow_json; exit 0; }
command -v jq >/dev/null 2>&1 || fail_open

stdin_json="$(cat 2>/dev/null)"
[ -z "$stdin_json" ] && fail_open
subagent_type="$(printf '%s' "$stdin_json" | jq -er '.tool_input.subagent_type // ""' 2>/dev/null)" || fail_open

case "$subagent_type" in
  ${PREFIX}*)
    command -v pgrep >/dev/null 2>&1 || fail_open
    if pgrep -f "$PGREP_PAT" >/dev/null 2>&1; then
      deny_json "singleton lock: a '${PGREP_PAT}' process is already running — queue this dispatch or use a fallback executor."
      exit 0
    fi
    allow_json; exit 0
    ;;
  *)
    allow_json; exit 0
    ;;
esac
