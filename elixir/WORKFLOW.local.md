---
tracker:
  kind: memory
workspace:
  root: /home/windo/symphony-workspaces
agent:
  max_concurrent_agents: 1
  max_turns: 3
codex:
  command: /home/windo/.npm-global/bin/codex app-server
server:
  host: 127.0.0.1
---

You are working on a local Symphony memory-tracker issue.

Title: {{ issue.title }}
Body: {{ issue.description }}
