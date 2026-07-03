#!/usr/bin/env bash
# TEMPLATE — intent-to-skill-nudge (UserPromptSubmit).
#
# Copy this to hooks/<your-name>.sh, fill the three <<PLACEHOLDERS>>, and wire it in
# settings.json under hooks.UserPromptSubmit. It detects an intent phrase in the user's
# prompt and nudges Claude to invoke one of your skills — with a negation guard so
# "don't do X" won't trigger it. FAIL-SILENT.
set -euo pipefail

PROMPT="$(jq -r '.prompt // empty' 2>/dev/null || true)"
[ -z "$PROMPT" ] && exit 0

# 1) Negation guard — bail if the user explicitly said NOT to.
if printf '%s' "$PROMPT" | grep -qiE "don'?t|do not|skip|<<NEGATION_WORDS>>"; then
    exit 0
fi

# 2) Positive trigger — your intent phrases (extended regex, case-insensitive).
if ! printf '%s' "$PROMPT" | grep -qiE '<<TRIGGER_REGEX — e.g. archive (this )?conversation|wrap up>>'; then
    exit 0
fi

# 3) The nudge. Keep it a single-line JSON string; \n renders as a newline.
cat <<'JSON'
{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"<system-reminder>\n<<NUDGE_TEXT — e.g. Invoke the `your-skill` skill. Do not write any files until the user confirms.>>\n</system-reminder>"}}
JSON
