# Runtime Debug and Cost Control

Use this reference when a Symphony-managed issue is taking too many turns, burning too many tokens, or appears stuck.

## Primary Inspection Points

Runtime API:

```bash
curl --max-time 20 http://127.0.0.1:4000/api/v1/state
curl --max-time 20 http://127.0.0.1:4000/api/v1/<ISSUE_IDENTIFIER>
```

Logs:

```bash
grep -RIn "issue_identifier=<KEY>" elixir/log
grep -RIn "session_id=" elixir/log
```

Workspace:

```bash
git -C /path/to/workspace status --short
git -C /path/to/workspace diff --stat
```

Monitoring priority:

1. Linear issue status
2. `/api/v1/state`
3. `/api/v1/<ISSUE_IDENTIFIER>`
4. `elixir/log/symphony.log*`
5. attached TTY output only as a secondary hint

## Read the Symptoms Correctly

- many completed turns + issue still active = not a retry loop; it is continuation
- `session_id` present + event stream moving = Codex is actively running
- no `session_id` yet + running entry exists = usually still in workspace bootstrap or before first Codex turn

## Cost Red Flags

Stop or redesign when:

- the ticket reaches many turns without a narrow validated deliverable
- input tokens become large relative to actual code/test/doc delta
- one ticket is absorbing design, implementation, validation, and external env work at the same time

## Recovery Pattern

1. stop the long run
2. inspect workspace diff
3. salvage useful changes
4. split the parent/gate ticket into narrower execution tickets
5. re-run only the next narrow ticket

## Important Lesson

Do not rely on the attached TTY stream as the main completion detector.

- TTY output can disappear when the interactive turn is interrupted
- Linear state and Symphony API/logs persist beyond the current assistant turn
- after any interruption or reconnect, do a fresh resync from:
  - Linear
  - `/api/v1/*`
  - `symphony.log*`
