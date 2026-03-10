---
tracker:
  kind: linear
  api_key: $LINEAR_API_KEY
  project_slug: "edict-codex-2c51698b34f4"
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
  root: /home/windo/symphony-workspaces/edict-codex
hooks:
  after_create: |
    git clone --depth 1 https://github.com/leinasi2014/edict-codex .
    if command -v mise >/dev/null 2>&1; then
      cd elixir
      /home/windo/.local/bin/mise trust
      /home/windo/.local/bin/mise exec -- mix deps.get
      cd ..
    fi
    if [ -d frontend ]; then
      cd frontend
      if [ -f package-lock.json ]; then
        npm ci
      else
        npm install
      fi
    fi
  before_remove: |
    cd elixir
    /home/windo/.local/bin/mise exec -- mix workspace.before_remove
agent:
  max_concurrent_agents: 6
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

You are working on a Linear ticket `{{ issue.identifier }}` for the `edict-codex` repository.

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

1. This workflow runs from the Symphony runtime repo, but the implementation target is the cloned `edict-codex` workspace.
2. Linear is used only as the development coordination layer for `edict-codex` work.
3. The `edict-codex` product runtime must still keep Plane as the only runtime tracker. Do not reintroduce Linear runtime dependencies into `edict-codex`.
4. Work only inside the provided workspace clone of `edict-codex`. Do not modify `/home/windo/src/symphony-leinasi2014` itself unless the ticket explicitly targets Symphony.
5. Preserve the current architecture direction:
   - backend: Elixir / Phoenix / Symphony runtime
   - frontend: Edict React/Vite control plane
   - runtime tracker: Plane
   - development coordination: Linear via Symphony orchestration
6. Before changing code, first inspect the existing implementation and continue from the current workspace state.
7. Keep changes narrowly scoped to the current ticket, add tests where the surrounding codebase expects them, and update docs when behavior or config changes.
8. If the ticket touches frontend behavior, ensure `cd frontend && npm run build` still succeeds.
9. Treat token budget as a hard constraint. Optimize for one coherent deliverable per run, not a broad umbrella completion attempt.
10. If the ticket is a parent / phase / gate / meta issue, do not try to complete the entire umbrella in one run. Produce one narrow implementation slice or stop with a blocker / child-ticket recommendation.
11. If you reach turn 2 without a concrete code, test, or docs delta, stop and report the blocker instead of continuing exploratory turns.
12. After completing one coherent slice plus targeted validation, stop and report; do not keep chaining turns just because the ticket remains active.
13. Final messages should report completed actions and blockers only.
