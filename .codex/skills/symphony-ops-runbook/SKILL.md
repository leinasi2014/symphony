---
name: symphony-ops-runbook
description: Runbook for Symphony-specific operations, execution control, issue routing, dashboard/debug work, and experience capture. Use when the task involves starting or stopping Symphony, checking the panel or `/api/v1/*`, diagnosing orchestrator or tracker failures, tightening workflow execution cost, shaping Linear issue trees for Symphony, or recording new Symphony operating lessons.
---

# Symphony Ops Runbook

Use this skill for **Symphony-specific** work, not generic system administration. It covers:

- starting, stopping, and validating `bin/symphony`
- checking the dashboard and `/api/v1/*`
- debugging orchestrator, tracker, workspace, and Codex-run issues
- shaping Linear tickets so Symphony only runs narrow executable work
- capturing new Symphony lessons back into this skill

## Workflow

1. **Classify the task**
   - **Service / panel**: start, stop, restart, port, `/`, `/api/v1/state`, `/api/v1/:issue`
   - **Tracker / network**: Linear timeouts, proxy issues, auth, polling problems
   - **Runtime / debug**: stuck runs, session IDs, retries, token burn, workspace state
   - **Issue shaping / governance**: whether a ticket is safe for Symphony to run

2. **Open only the matching reference**
   - `references/service-and-panel.md`
   - `references/linear-and-network.md`
   - `references/monitor-loop.md`
   - `references/runtime-debug-and-cost-control.md`
   - `references/issue-shaping-and-routing.md`

3. **Operate with these hard rules**
   - Stop long-running wasteful runs before redesigning execution.
   - Treat parent / phase / gate / workstream tickets as **non-executable**.
   - Only assign Symphony tickets that are narrow enough to finish in a small number of turns.
   - After changing Elixir code that affects `bin/symphony`, run:
     - targeted tests
     - `mix compile`
     - `mix build`
   - If a workflow key is added, verify the parser actually reads it.
   - When a real operation reveals a new failure mode or recovery path, update the matching reference file in this skill.

## Core Rules

### Execution Cost Discipline

- Never let Symphony free-run on a wide ticket just because it is still active.
- Use these ticket classes:
  - **meta**: parent/gate/workstream only, never assign to Symphony
  - **exec-ready**: narrow execution leaf, safe to assign
  - **split-before-run**: too broad, must be decomposed first
  - **manual-env**: depends on real external environment or operator validation

### Rebuild Discipline

If code changes affect the running Symphony executable:

1. run targeted tests
2. run `mix compile`
3. run `mix build`
4. restart the live Symphony process

Do not assume `mix compile` updates the already-built `bin/symphony` escript.

### Routing Discipline

- Prefer `tracker.assignee: "me"` for active execution workflows.
- Keep parent/meta tickets unassigned.
- Assign only the one narrow leaf that should run now.

### Stop Conditions

Stop or redesign execution when any of these happens:

- multiple continuation turns with weak incremental output
- token burn is growing faster than validated progress
- the ticket is mixing implementation, docs, tests, external env work, and acceptance
- the current run is doing umbrella work that should be child tickets

## References

- **Service / panel**: `references/service-and-panel.md`
- **Tracker / proxy / network**: `references/linear-and-network.md`
- **Detached monitor loop**: `references/monitor-loop.md`
- **Runtime debug / token control**: `references/runtime-debug-and-cost-control.md`
- **Issue shaping / routing**: `references/issue-shaping-and-routing.md`
