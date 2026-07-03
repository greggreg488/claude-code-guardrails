#!/usr/bin/env bash
# UserPromptSubmit hook — escalate-to-best-model.
# On architecture / top-level design / irreversible-decision / postmortem-root-cause /
# large-spec / deadlock intent, remind the agent to escalate the reasoning to its
# top-tier model (or record why it didn't). Advisory only; never blocks. FAIL-SILENT.
#
# Config (env, optional):
#   GUARDRAILS_TOP_MODEL   label for your best model     (default: "your top-tier model")
#   GUARDRAILS_TOP_AGENT   label for how you dispatch it (default: "your architect subagent")
set -euo pipefail

PROMPT="$(jq -r '.prompt // empty' 2>/dev/null || true)"
[ -z "$PROMPT" ] && exit 0

TOP_MODEL="${GUARDRAILS_TOP_MODEL:-your top-tier model}"
TOP_AGENT="${GUARDRAILS_TOP_AGENT:-your architect subagent}"

if printf '%s' "$PROMPT" | grep -qiE 'architect(ure)?|top-level design|system design|design decision|irreversible|postmortem|root.?cause|large spec|spec.{0,6}(prune|trim|cut)|deadlock|not converging|refactor plan|架构|顶层设计|系统设计|设计决策|技术选型|复盘|根因|大 ?spec|死锁|不收敛|重构方案|不可逆'; then
  cat <<EOF

[escalate-to-best-model — reminder]
This looks like a high-stakes reasoning task (architecture / irreversible decision /
postmortem root-cause / large-spec pruning / deadlock). Do one of:
  * Escalate it to ${TOP_MODEL} via ${TOP_AGENT}, fed a real decision pack — the
    question, why it's worth the top tier, the constraints/red-lines, the evidence
    digest you've already verified, and the required output (verdict + counter-case +
    confidence).
  * Or record "NOT_ESCALATED_BECAUSE: <reason>" so the skip is a conscious choice.

Triggering is necessary-not-sufficient: a weak pack yields a confidently wrong verdict.
The top model's verdict is advisory — re-ground it against sources and run your gates
before acting, then downgrade immediately so you don't sit on the expensive tier.
EOF
fi
exit 0
