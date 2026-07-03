# claude-code-guardrails

**Battle-tested [Claude Code](https://docs.claude.com/en/docs/claude-code) hooks that keep autonomous and heavy sessions honest.**

> 🔀 **Now cross-agent.** These guardrails also run on **OpenAI Codex** — plus a Codex `safe-full-auto` layer (hard gates that survive `danger-full-access`, a kill-switch, and an audit trail) — in the superset repo **[agent-guardrails](https://github.com/greggreg488/agent-guardrails)**. This repo stays the Claude Code–focused variant.

Small, self-contained, fail-open hooks that stop the failure modes you hit once you
let Claude Code run long and unattended: confidently asserting stale external facts,
dumping false "which one is right?" dilemmas on you, inventing timestamps, double-
dispatching a single-instance tool, and (optionally) blurring the planner/executor
line. Each was forged from a real incident and hardened over months of daily use.

> Install only what you want — every hook is independent, and the guards that can
> get in your way are **opt-in** and inert until you configure them.

---

## Why

Claude Code hooks run shell commands at lifecycle events (`UserPromptSubmit`,
`SessionStart`, `Stop`, `PreToolUse`). That's the right layer for *discipline you
can't rely on the model to remember* — because a rule that lives only in a prompt or
a memory file gets skipped exactly when you're not watching. These hooks turn
hard-won operating lessons into things the harness enforces, not things you hope for.

Design principles (kept from the private originals they were extracted from):

- **Fail-open / fail-silent** — a broken hook never bricks a session (missing `jq`,
  bad JSON, any error → allow / exit 0).
- **Narrow triggers** — advisories fire only on strong signals, so they never become
  noise you learn to ignore.
- **60-minute bypass** — `touch ~/.claude/state/guardrails_bypass` when a guard is wrong.
- **Zero secrets, zero business logic** — the payload is generic discipline.

## Hook catalog

| Hook | Event | On by default | What it does |
|---|---|:---:|---|
| `verify-before-assert` | UserPromptSubmit | ✅ | On "recommend / which is best / pricing / capability" prompts, injects the verify-before-you-assert checklist (4-tuple + as-of date + branch-if-unverified). |
| `escalate-to-best-model` | UserPromptSubmit | ✅ | On architecture / irreversible-decision / postmortem / large-spec / deadlock prompts, reminds you to escalate to your top-tier model — or record why you didn't. |
| `stale-memory-warning` | SessionStart | ✅ | Warns about memory entries whose `last_verified` date is past due (opt-in frontmatter contract). |
| `no-phantom-conflict-escalation` | Stop | ✅ | Catches replies that dump a false "X vs Y, you decide" dilemma and nudges the model to self-resolve first. |
| `planner-executor-separation` | PreToolUse | ⬜ opt-in | Blocks the planner session from writing/running code so implementation stays with a dedicated executor. Docs, config, read-only shell, tests, `python -c` stay allowed. |
| `subagent-singleton-lock` | PreToolUse | ⬜ opt-in | Blocks dispatching a subagent type while one instance is already running (for tools that can't run concurrently). |
| `no-clock-drift-guard` | PreToolUse | ⬜ opt-in | LLMs have no clock — reminds/forces timestamps to come from real `date`, not the model's imagination. |
| `intent-to-skill-nudge` | template | — | Copy-paste template: detect an intent phrase → nudge Claude to invoke one of your skills, with a negation guard. |

## Quickstart

```bash
git clone https://github.com/<you>/claude-code-guardrails
cd claude-code-guardrails
./install.sh            # copies default-on hooks to ~/.claude/hooks and prints the settings block
./install.sh --merge    # also merges the hooks block into ~/.claude/settings.json (backs it up first)
```

Then restart Claude Code. Verify with `test/smoke.sh`, which feeds each hook a sample
event and asserts a clean exit + valid JSON.

To enable an opt-in guard, add its line to `settings.example.json`'s block and set any
env it documents (e.g. `GUARDRAILS_EXECUTOR`, `GUARDRAILS_SINGLETON_PGREP`).

## The `stale-memory-warning` frontmatter contract

The memory warning is opt-in: it only flags files whose YAML frontmatter declares
they're worth re-checking.

```markdown
---
name: some-external-pricing-fact
stale_risk: high
last_verified: 2026-01-15
---
```

Files with `stale_risk: high` and a `last_verified` older than 14 days get surfaced at
session start. Everything else is ignored.

## Compatibility

- Requires `bash`, `jq`, and `python3` (all standard on macOS / most Linux).
- Targets the Claude Code hooks JSON contract. Hooks degrade to no-ops if the contract
  or a dependency is missing.

## Contributing

New hooks welcome if they're **generic** (no business/domain payload), **fail-open**,
and **narrowly triggered**. Include a sample event in `test/`.

## License

MIT — see [LICENSE](LICENSE).
