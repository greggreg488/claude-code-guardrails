#!/usr/bin/env bash
# UserPromptSubmit hook — verify-before-assert.
# When the prompt asks for a recommendation / "which is best" / pricing / quota /
# subscription / capability of an EXTERNAL tool/model/service, inject a reminder to
# verify current facts before asserting. LLMs confidently state stale external facts.
# Advisory only; never blocks. FAIL-SILENT.
set -euo pipefail

PROMPT="$(jq -r '.prompt // empty' 2>/dev/null || true)"
[ -z "$PROMPT" ] && exit 0

HIT=0
if printf '%s' "$PROMPT" | grep -qiE '\brecommend(ed|ation)?\b|\bbest\b|\boptimal\b|\bcheapest\b|\bfastest\b|\bwhich (one|is)\b|\bpricing\b|\bcost(s)?\b|\bquota\b|\blimit(s)?\b|\bsubscription\b|\bplan\b|\btier\b|\bsupport(s)?\b|\binclude(s)?\b|\bversus\b|\bvs\b|\bcompar(e|ison)\b'; then
    HIT=1
fi
# Optional bilingual triggers — delete this block if you work in English only.
if printf '%s' "$PROMPT" | grep -qE '推荐|哪个好|最好|最优|最便宜|价格|多少钱|配额|限额|订阅|套餐|是否支持|对比|比较'; then
    HIT=1
fi
[ "$HIT" -eq 0 ] && exit 0

python3 - <<'PY'
import json
reminder = """Detected an "assert an external capability / recommend / pricing" intent.
Before stating it as fact:

1. Four-tuple — WHICH exact object (model/service/tool + version) + WHICH account/env
   (CLI/desktop/API/subscription tier/region) + AS-OF date (YYYY-MM-DD) + SOURCE (how you know).
2. A product name can't be the subject alone: not "X lacks feature Y", but
   "X CLI v1.2.3 in sandbox mode has no Y (as-of 2026-01-01)".
3. Any memory/notes you cite must carry an as-of date AND be re-verified before use.
4. Recommendation gate: if a ranking depends on a CURRENT external capability you
   have NOT verified, don't say "use X" — say "branch: if A -> X, if B -> Y; A/B
   unverified, verify first."
5. Uncertain tone + a firm action recommendation is a forbidden combination.

Verification priority: ask the tool itself (--help / dry-run / list) > official docs >
real dry-run > memory (lowest — may be stale)."""
print(json.dumps({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit",
      "additionalContext": "<system-reminder>\n" + reminder + "\n</system-reminder>"}},
      ensure_ascii=False))
PY
