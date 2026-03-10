# Monitor Loop

Use the bundled monitor loop when you need detached Symphony monitoring that survives the current assistant turn better than attached TTY output.

## Script

`scripts/symphony-monitor-loop.sh`

## Commands

Start:

```bash
~/.codex/skills/symphony-ops-runbook/scripts/symphony-monitor-loop.sh start
```

Stop:

```bash
~/.codex/skills/symphony-ops-runbook/scripts/symphony-monitor-loop.sh stop
```

Status:

```bash
~/.codex/skills/symphony-ops-runbook/scripts/symphony-monitor-loop.sh status
```

Tail recent log lines:

```bash
~/.codex/skills/symphony-ops-runbook/scripts/symphony-monitor-loop.sh tail
```

## Default Paths

- log: `/tmp/symphony-edict-monitor.log`
- pid: `/tmp/symphony-edict-monitor.pid`

## Notes

- This loop watches process presence, port state, and `/api/v1/state`.
- It is a background heartbeat and monitoring aid, not the only source of truth.
- Final completion should still be confirmed from Linear plus Symphony API/logs.
