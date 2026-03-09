---
tracker:
  kind: linear
  api_key: $LINEAR_API_KEY
  project_slug: "symphony-eed38ad17b0c"
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
  root: /home/windo/symphony-workspaces
hooks:
  after_create: |
    git clone --depth 1 https://github.com/leinasi2014/symphony .
    cd elixir
    /home/windo/.local/bin/mise exec -- mix deps.get
  before_remove: |
    cd elixir
    /home/windo/.local/bin/mise exec -- mix workspace.before_remove
agent:
  max_concurrent_agents: 10
  max_turns: 20
codex:
  command: /home/windo/.npm-global/bin/codex app-server
  approval_policy: never
  thread_sandbox: workspace-write
  turn_sandbox_policy:
    type: workspaceWrite
server:
  host: 127.0.0.1
---

You are working on a Linear ticket `{{ issue.identifier }}`。

{% if attempt %}
续跑上下文：

- 这是第 #{{ attempt }} 次重试，因为该工单仍处于活跃状态。
- 请基于当前工作区继续，而不是从头开始。
- 除非本轮变更需要，否则不要重复已经完成的调查或验证。
- 只要工单仍在活跃状态，除非被权限/密钥阻塞，否则不要提前结束本轮。
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
