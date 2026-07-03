#!/usr/bin/env bash
# SessionStart hook — stale-memory-warning.
# Surfaces memory files whose frontmatter marks them stale_risk: high and whose
# last_verified date is older than a threshold, so you re-verify before relying on
# them. Opt-in via frontmatter; inert if no memory dir is found. Never blocks.
#
# Config (env, optional):
#   GUARDRAILS_MEMORY_DIR   dir of *.md memory files  (default: $CLAUDE_PROJECT_DIR/memory)
#   GUARDRAILS_STALE_DAYS   staleness threshold in days (default: 14)
set -euo pipefail

MEMORY_DIR="${GUARDRAILS_MEMORY_DIR:-${CLAUDE_PROJECT_DIR:-}/memory}"
[ -d "$MEMORY_DIR" ] || exit 0
TODAY="$(date +%Y-%m-%d)"
STALE_DAYS="${GUARDRAILS_STALE_DAYS:-14}"
export MEMORY_DIR TODAY STALE_DAYS

python3 - <<'PY'
import json, os, re
from datetime import datetime
from pathlib import Path


def frontmatter(text):
    m = re.match(r"\A---\s*\n(.*?)\n---\s*(?:\n|\Z)", text, re.S)
    return m.group(1) if m else ""


def field(fm, key):
    m = re.search(
        rf"(?im)^\s*{re.escape(key)}\s*:\s*[\"']?([^\"'\n#]+?)[\"']?\s*(?:#.*)?$", fm
    )
    return m.group(1).strip() if m else ""


def main():
    memory_dir = Path(os.environ["MEMORY_DIR"])
    if not memory_dir.is_dir():
        return
    try:
        today = datetime.strptime(os.environ["TODAY"], "%Y-%m-%d").date()
        threshold = int(os.environ.get("STALE_DAYS", "14"))
    except Exception:
        return

    stale = []
    for path in sorted(memory_dir.glob("*.md")):
        try:
            fm = frontmatter(path.read_text(encoding="utf-8", errors="ignore"))
            if not fm or field(fm, "stale_risk").lower() != "high":
                continue
            last = datetime.strptime(field(fm, "last_verified"), "%Y-%m-%d").date()
        except Exception:
            continue
        days = (today - last).days
        if days > threshold:
            stale.append((days, field(fm, "name") or path.stem, last.isoformat()))

    if not stale:
        return
    stale.sort(reverse=True)
    n = len(stale)
    lines = [f"{n} memory entr{'y' if n == 1 else 'ies'} past their re-verify date:"]
    for days, name, last in stale[:5]:
        lines.append(f"- {name} (last_verified {last}, {days}d ago)")
    if n > 5:
        lines.append(f"- ... and {n - 5} more")
    lines.append("")
    lines.append("Re-verify these against a live source before relying on them.")

    print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart",
          "additionalContext": "<system-reminder>\n" + "\n".join(lines) + "\n</system-reminder>"}},
          ensure_ascii=False))


try:
    main()
except Exception:
    pass
PY
