# Repo Additions

This repository already uses broader Codex defaults outside this file.

## System Operations

Repo-local `AGENTS.md` should not duplicate environment/login/browser/Git
operational SOPs.

- Use the global `system-ops-runbook` skill for environment setup, login flows,
  browser takeover, SSH/Git credentials, proxy/CDP diagnostics, and similar
  system-operation tasks.
- When those tasks uncover a new step, failure mode, or recovery path, update
  the matching runbook in `~/.codex/skills/system-ops-runbook` instead of
  expanding this repo file.

Keep this repository `AGENTS.md` focused on repo-specific instructions only.

## Symphony Operations

For Symphony-specific work in this repository, prefer the repo-local
`symphony-ops-runbook` skill.

Use it when the task involves:

- starting, stopping, or validating `bin/symphony`
- checking the Symphony dashboard or `/api/v1/*`
- debugging orchestrator, tracker, workspace, or Codex execution behavior
- shaping Linear issues for safe Symphony execution
- capturing new Symphony runbooks, guardrails, or failure lessons
- monitoring Symphony execution state and task completion

## Delegation Policy

- For implementation review, ticket triage, acceptance checks, and similar
  project-management work, prefer delegating concrete checks to sub-agents.
- The main agent should act as the coordinator:
  - assign narrow, well-scoped subtasks to sub-agents
  - collect and compare their outputs
  - make the final decision
  - update Linear or repo state based on the delegated results
- Do not do the full analysis locally by default when the work can be cleanly
  split across sub-agents.

## Continuous Managed Loop

- When the user explicitly delegates ongoing project execution, default to a
  continuous managed loop rather than one-ticket-at-a-time waiting for user
  reminders.
- The main agent should keep advancing work until blocked by one of:
  - missing external credentials or environment access
  - a genuinely ambiguous product decision
  - a high-risk action that requires explicit confirmation
- Normal loop behavior:
  - pick the next `exec-ready` ticket in dependency order
  - assign or run only one active execution ticket at a time unless parallelism
    is clearly safe
  - use sub-agents for review and acceptance checks
  - automatically update Linear status/comments based on delegated review
  - after a ticket reaches a terminal state, immediately advance to the next
    eligible ticket without waiting for the user to prompt again
- Do not pause the managed loop merely because an attached terminal session or
  TTY watcher ended; resync from Linear, `/api/v1/*`, and logs, then continue.

## Monitoring Policy

- Do not treat attached TTY output as the primary source of truth for task
  completion.
- Primary monitoring for Symphony-managed work must use, in order:
  - Linear issue status
  - `/api/v1/state` and `/api/v1/:issue`
  - `elixir/log/symphony.log*`
- Process/port checks (`pgrep`, `ss`) are heartbeat signals only.
- TTY output is secondary and may disappear when the session is interrupted.

## Execution Environment

- Default execution environment is Ubuntu with `bash`.
- Prefer Ubuntu/Linux commands, paths, and tooling by default.
- Do not switch to Windows-specific commands unless the user explicitly asks.
