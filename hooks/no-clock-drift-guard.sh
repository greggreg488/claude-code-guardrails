#!/usr/bin/env bash
#
# no-clock-drift-guard.sh — PreToolUse (matcher: Edit|Write; passes everything else)
#
# OPT-IN, inert by default. LLMs have no internal clock, so timestamps they hand-write
# into logs/state files drift. Configure globs for your timestamped files; a direct
# Edit/Write to one is then denied with a reminder to source the time from real `date`
# (route the write through a helper that stamps `date -u +%FT%TZ`).
#
# FAIL-OPEN. Bypass 60 min: touch ~/.claude/state/guardrails_bypass
#
# Config (env):
#   GUARDRAILS_TIMESTAMPED_GLOBS   space-separated case-globs (default: empty = inert)
#       e.g.  "*/state.json */run_log*.md"

GLOBS="${GUARDRAILS_TIMESTAMPED_GLOBS:-}"

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

# Inert until configured.
[ -z "$GLOBS" ] && fail_open

sentinel="${HOME:-}/.claude/state/guardrails_bypass"
[ -z "${HOME:-}" ] && fail_open
[ -n "$(find "$sentinel" -mmin -60 2>/dev/null)" ] && { allow_json; exit 0; }
command -v jq >/dev/null 2>&1 || fail_open

stdin_json="$(cat 2>/dev/null)"
[ -z "$stdin_json" ] && fail_open
tool_name="$(printf '%s' "$stdin_json" | jq -er '.tool_name // ""' 2>/dev/null)" || fail_open

case "$tool_name" in
  Edit|Write)
    fp="$(printf '%s' "$stdin_json" | jq -er '.tool_input.file_path // ""' 2>/dev/null)" || fail_open
    [ -z "$fp" ] && { allow_json; exit 0; }
    for g in $GLOBS; do
      case "$fp" in
        $g)
          deny_json "no-clock-drift: '$fp' carries timestamps — don't hand-write the time. Route the write through a helper that injects real \`date -u +%FT%TZ\`, or bypass: touch ~/.claude/state/guardrails_bypass"
          exit 0
          ;;
      esac
    done
    allow_json; exit 0
    ;;
  *)
    allow_json; exit 0
    ;;
esac
