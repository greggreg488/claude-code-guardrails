#!/usr/bin/env bash
#
# external-egress-pii-guard.sh — PreToolUse (wire to YOUR egress tool's matcher)
#
# OPT-IN example. Before a tool call that sends data OFF your machine (an external LLM
# MCP, a web POST, an upload), scan the tool input for high-confidence SECRETS and deny
# if found. Conservative by design: it matches secrets (keys/tokens/private keys/
# passwords), NOT general PII, to avoid false positives. Tune to your risk model.
#
# Wire it in settings.json under the matcher for your egress tool, e.g.:
#   { "matcher": "mcp__some_external_llm__.*",
#     "hooks": [ { "type": "command", "command": "<HOME>/.claude/hooks/external-egress-pii-guard.sh" } ] }
#
# FAIL-OPEN. Bypass 60 min: touch ~/.claude/state/guardrails_bypass

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
payload="$(printf '%s' "$stdin_json" | jq -er '.tool_input // {} | tostring' 2>/dev/null)" || fail_open

# High-confidence secret signatures. Extend for your environment.
if printf '%s' "$payload" | grep -qE '-----BEGIN [A-Z ]*PRIVATE KEY-----|sk-[A-Za-z0-9]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|(password|passwd|api[_-]?key|secret|token)[": =]{1,4}[^ ",;]{6,}'; then
  deny_json "external-egress-pii-guard: the payload looks like it contains a secret (key/token/private key/password). Redact it before sending off-machine, or bypass: touch ~/.claude/state/guardrails_bypass"
  exit 0
fi
allow_json; exit 0
