---
tracker:
  kind: linear
  api_key: $LINEAR_API_KEY
  project_slug: "symphony-eed38ad17b0c"
  assignee: "me"
  active_states:
    - Todo
    - In Progress
    - Merging
    - Rework
  terminal_states:
    - Closed
    - Cancelled
    - Canceled
    - Duplicate
    - Done
polling:
  interval_ms: 5000
workspace:
  root: /home/windo/symphony-workspaces/symphony-leinasi2014
hooks:
  after_create: |
    git clone --depth 1 https://github.com/leinasi2014/symphony.git .
    if command -v mise >/dev/null 2>&1; then
      cd elixir
      /home/windo/.local/bin/mise trust
      /home/windo/.local/bin/mise exec -- mix deps.get
      cd ..
    fi
  before_remove: |
    cd elixir
    /home/windo/.local/bin/mise exec -- mix workspace.before_remove
agent:
  max_concurrent_agents: 4
  max_turns: 4
codex:
  command: /home/windo/.npm-global/bin/codex --config shell_environment_policy.inherit=all --config model_reasoning_effort=xhigh --model gpt-5.3-codex app-server
  approval_policy: never
  thread_sandbox: workspace-write
  turn_sandbox_policy:
    type: workspaceWrite
server:
  host: 127.0.0.1
---

You are working on a Linear ticket `{{ issue.identifier }}` for the `leinasi2014/symphony` repository.

{% if attempt %}
Continuation context:

- This is retry attempt #{{ attempt }} because the ticket is still active.
- Resume from the current workspace state instead of restarting from scratch.
- Do not repeat already-completed investigation or validation unless the new code change requires it.
- Do not end the turn while the ticket remains active unless you are truly blocked by missing required permissions or secrets.
{% endif %}

Issue context:
Identifier: {{ issue.identifier }}
Title: {{ issue.title }}
Current status: {{ issue.state }}
Labels: {{ issue.labels }}
URL: {{ issue.url }}

Description:
{% if issue.description %}
{{ issue.description }}
{% else %}
No description provided.
{% endif %}

Instructions:

1. This workflow targets the current Symphony runtime repository itself. Work only inside the provided workspace clone of `leinasi2014/symphony`.
2. Do not modify `/home/windo/src/symphony-leinasi2014` directly; use only the issue workspace clone created by Symphony.
3. Before changing code, inspect the existing implementation and continue from the current workspace state.
4. Keep changes narrowly scoped to the current ticket. Add or update tests whenever behavior, accounting, orchestration, or config semantics change.
5. Treat `elixir/docs/cost_guardrails_design.md` as the source of truth for all cost-guardrails tickets.
6. Follow the design document's recommended implementation order for guardrails work:
   - token accounting audit/correction first
   - config schema and validation second
   - orchestrator ledger and continuation gate third
   - retry suppression and stop handling next
   - dashboard/API exposure after the core behavior is stable
7. If the ticket is a parent, phase, gate, or otherwise broad/meta issue, do not try to complete the entire umbrella in one run. Produce one narrow implementation slice or stop with a blocker or child-ticket recommendation.
8. Tickets labeled `meta`, `split-before-run`, or `manual-env` are not execution tickets. Only deliver code for narrow leaf tickets that are effectively `exec-ready`.
9. Reproduce or verify the current behavior before changing code when the ticket is bug-fix or accounting related.
10. Use targeted validation for the touched area. For Elixir runtime changes, prefer focused `mix test` coverage first; run broader checks only when the scope justifies it.
11. If the ticket touches status surfaces or API payloads, validate the relevant dashboard/API tests or snapshots that cover the changed surface.
12. If you reach turn 2 without a concrete code, test, or docs delta, stop and report the blocker instead of continuing exploratory turns.
13. After completing one coherent slice plus targeted validation, stop and report. Do not keep chaining turns just because the ticket remains active.
14. Final messages should report completed actions and blockers only.
