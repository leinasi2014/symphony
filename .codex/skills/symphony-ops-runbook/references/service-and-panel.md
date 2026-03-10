# Service and Panel

Use this reference when Symphony needs to be started, stopped, restarted, or when the panel/API looks wrong.

## Start

From `elixir/`:

```bash
mise exec -- ./bin/symphony ./WORKFLOW.linear.edict-codex.local.md --port 4000 --i-understand-that-this-will-be-running-without-the-usual-guardrails
```

## Stop

Prefer killing only the specific `bin/symphony ... WORKFLOW...` BEAM process, then confirm port release:

```bash
pgrep -af 'bin/symphony ./WORKFLOW.linear.edict-codex.local.md'
ss -ltnp | grep ':4000 '
kill -9 <pid>
```

## Validate

Use both routes:

```bash
curl --max-time 20 http://127.0.0.1:4000/api/v1/state
curl --max-time 20 http://127.0.0.1:4000/
```

Interpretation:

- `503` right after boot: app may still be starting
- `snapshot_timeout`: orchestrator is alive but blocked or too slow
- `200` with empty `running`: service is up but no issue is running
- `200` with `running`: service is active and panel should reflect it

## When the Panel Looks Dead

Check in this order:

1. Is the port listening?
2. Does `/api/v1/state` return?
3. Does the local TTY status output show `编排器快照不可用` or `当前没有活跃 Agent`?
4. Do `log/symphony.log*` show tracker timeouts or stale startup behavior?

## Important Lesson

If the panel is slow or inconsistent, it may still be the backend waiting on the tracker rather than the HTTP server being down.
