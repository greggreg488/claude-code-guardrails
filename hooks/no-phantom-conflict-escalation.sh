#!/usr/bin/env bash
# Stop hook — no-phantom-conflict-escalation.
# Scans the latest assistant reply for the pattern of dumping a false "X vs Y, which
# is authoritative? you decide" dilemma on the user instead of self-resolving, and
# injects a self-check reminder. Narrow by design. FAIL-SILENT (any error -> exit 0).
set -euo pipefail

INPUT_FILE="$(mktemp "${TMPDIR:-/tmp}/no-phantom-conflict.XXXXXX")"
trap 'rm -f "$INPUT_FILE"' EXIT
cat > "$INPUT_FILE" || true
export INPUT_FILE

python3 - <<'PY'
import json, os, re
from pathlib import Path


def content_to_text(value):
    if value is None:
        return ""
    if isinstance(value, str):
        return value
    if isinstance(value, list):
        return "\n".join(content_to_text(i) for i in value)
    if isinstance(value, dict):
        parts = []
        for key in ("text", "content", "message", "delta"):
            if key in value:
                parts.append(content_to_text(value.get(key)))
        return "\n".join(p for p in parts if p)
    return ""


def role_of(message):
    if not isinstance(message, dict):
        return ""
    nested = message.get("message")
    return (
        message.get("role")
        or message.get("type")
        or (nested.get("role") if isinstance(nested, dict) else "")
        or ""
    )


def text_of_message(message):
    if not isinstance(message, dict):
        return ""
    if "content" in message:
        return content_to_text(message.get("content"))
    nested = message.get("message")
    if isinstance(nested, dict):
        return content_to_text(nested.get("content"))
    return content_to_text(message)


def latest_assistant_from_messages(messages):
    if not isinstance(messages, list):
        return ""
    for m in reversed(messages):
        if role_of(m) == "assistant":
            t = text_of_message(m)
            if t.strip():
                return t
    return ""


def latest_assistant_from_transcript(path):
    try:
        lines = Path(path).read_text(encoding="utf-8", errors="ignore").splitlines()
    except Exception:
        return ""
    for line in reversed(lines):
        try:
            item = json.loads(line)
        except Exception:
            continue
        if role_of(item) == "assistant":
            t = text_of_message(item)
            if t.strip():
                return t
    return ""


def extract_latest_assistant(payload):
    t = latest_assistant_from_messages(payload.get("messages"))
    if t:
        return t
    tp = payload.get("transcript_path") or payload.get("transcriptPath")
    if tp:
        t = latest_assistant_from_transcript(tp)
        if t:
            return t
    for key in ("assistant_response", "assistantResponse", "response", "message", "content"):
        t = content_to_text(payload.get(key))
        if t.strip():
            return t
    return ""


def main():
    try:
        with open(os.environ["INPUT_FILE"], encoding="utf-8") as f:
            payload = json.load(f)
    except Exception:
        return
    if not isinstance(payload, dict):
        return
    text = extract_latest_assistant(payload)
    if not text.strip():
        return

    # Narrow: only strong "dumping a false dilemma on the user" signals.
    pattern = re.compile(
        r"which (is|one is) authoritative|which .{0,20} should i use|"
        r"you decide between|please (pick|choose|decide) between|"
        r"哪一?份为准|哪个为准|谁为准|二选一[^。\n]*?(你定|拍板|请定|定夺)",
        re.IGNORECASE,
    )
    if not pattern.search(text):
        return

    reminder = (
        "Detected a 'conflict / either-or / you-decide' escalation to the user. "
        "Self-check before shipping it: "
        "(1) Is this a REAL conflict, or a mis-classification (e.g. treating a flat "
        "mixed list as one category)? "
        "(2) Can you resolve it item-by-item from an authority you already hold "
        "(task files, a profile, your own output this session)? If so, resolve it — "
        "don't escalate. "
        "(3) Are the two premises even comparable, and did YOU sanity-check that? "
        "A verify pass only checks inside the frame you give it."
    )
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "Stop",
          "additionalContext": "<system-reminder>\n" + reminder + "\n</system-reminder>"}},
          ensure_ascii=False))


try:
    main()
except Exception:
    pass
PY
