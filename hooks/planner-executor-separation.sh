#!/usr/bin/env bash
#
# planner-executor-separation.sh — PreToolUse (matcher: Edit|Write|Bash)
#
# OPT-IN invariant. Use ONLY if your workflow separates a PLANNER agent (this Claude
# session) from a dedicated EXECUTOR (a subagent / external CLI / another tool) that
# does the actual code writing & running. Blocks the planner from directly editing/
# writing code files or executing code scripts, so implementation stays with the
# executor. Docs (*.md), Claude config (*/.claude/*), read-only shell, test runners,
# and `python -c` one-liners are always allowed.
#
# FAIL-OPEN: missing jq / empty stdin / malformed JSON / any error -> allow.
# Bypass 60 min: touch ~/.claude/state/guardrails_bypass
#
# Config (env, optional):
#   GUARDRAILS_EXECUTOR    label in the deny message      (default: "the executor agent")
#   GUARDRAILS_CODE_EXTS   space-separated blocked exts   (default: py ts js mjs cjs sh bash zsh)

EXECUTOR="${GUARDRAILS_EXECUTOR:-the executor agent}"
CODE_EXTS="${GUARDRAILS_CODE_EXTS:-py ts js mjs cjs sh bash zsh}"

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
tool_name="$(printf '%s' "$stdin_json" | jq -er '.tool_name // ""' 2>/dev/null)" || fail_open

deny_edit="planner/executor split: the planner does not write code files — delegate to ${EXECUTOR}. (Docs/config are exempt. Bypass: touch ~/.claude/state/guardrails_bypass)"
deny_bash="planner/executor split: the planner does not run code scripts — delegate to ${EXECUTOR}. Read-only and test commands are allowed."

ext_blocked() {
  local ext="${1##*.}"
  local e
  for e in $CODE_EXTS; do
    [ "$ext" = "$e" ] && return 0
  done
  return 1
}

case "$tool_name" in
  Edit|Write)
    fp="$(printf '%s' "$stdin_json" | jq -er '.tool_input.file_path // ""' 2>/dev/null)" || fail_open
    [ -z "$fp" ] && { allow_json; exit 0; }
    case "$fp" in
      *.md|*/.claude/*) allow_json; exit 0 ;;
    esac
    if ext_blocked "$fp"; then deny_json "$deny_edit"; else allow_json; fi
    exit 0
    ;;
  Bash)
    cmd="$(printf '%s' "$stdin_json" | jq -er '.tool_input.command // ""' 2>/dev/null)" || fail_open
    [ -z "$cmd" ] && { allow_json; exit 0; }
    lc="$(printf '%s' "$cmd" | tr '[:upper:]' '[:lower:]')"
    case "$lc" in *--version*|*--help*) allow_json; exit 0 ;; esac
    # NOTE: assign each ERE to a variable, then match with `=~ $var`. Inlining a regex
    # that contains ; & | ( ) directly into [[ =~ ... ]] is a bash SYNTAX error.
    # Always allow: read-only starters, test runners, python -c one-liners.
    re_readonly='^[[:space:]]*(ls|cat|grep|head|tail|find|git|echo)([[:space:]]|$)'
    re_tests='(^|[[:space:];&|/])(pytest|jest|vitest)([[:space:];&|/]|$)'
    re_npm_test='(^|[[:space:];&|])npm[[:space:]]+test([[:space:];&|]|$)'
    re_go_test='(^|[[:space:];&|])go[[:space:]]+test([[:space:];&|]|$)'
    re_py_c='^[[:space:]]*python3?[[:space:]]+-c([[:space:]]|$)'
    if [[ "$lc" =~ $re_readonly ]] || [[ "$lc" =~ $re_tests ]] \
    || [[ "$lc" =~ $re_npm_test ]] || [[ "$lc" =~ $re_go_test ]] \
    || [[ "$lc" =~ $re_py_c ]]; then
      allow_json; exit 0
    fi
    # Deny: running code scripts.
    re_py='(^|[[:space:];&|])python3?[[:space:]]+[^[:space:];&|]+\.py([[:space:];&|]|$)'
    re_node='(^|[[:space:];&|])node[[:space:]]+[^[:space:];&|]+\.(js|mjs|cjs)([[:space:];&|]|$)'
    re_sh='(^|[[:space:];&|])(bash|sh)[[:space:]]+[^[:space:];&|]+\.sh([[:space:];&|]|$)'
    re_dotsh='(^|[[:space:];&|])\./[^[:space:];&|]*\.sh([[:space:];&|]|$)'
    re_run='(^|[[:space:];&|])(cargo|go)[[:space:]]+run([[:space:];&|]|$)'
    if [[ "$lc" =~ $re_py ]] || [[ "$lc" =~ $re_node ]] \
    || [[ "$lc" =~ $re_sh ]] || [[ "$lc" =~ $re_dotsh ]] \
    || [[ "$lc" =~ $re_run ]]; then
      deny_json "$deny_bash"; exit 0
    fi
    allow_json; exit 0
    ;;
  *)
    allow_json; exit 0
    ;;
esac
