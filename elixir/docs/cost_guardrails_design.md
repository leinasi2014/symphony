# Symphony Cost Guardrails Design

Status: Proposed

## Problem

Symphony can currently spend very large numbers of input tokens on a single issue even when only one
agent is running.

The main failure pattern is structural:

- `AgentRunner` keeps a live Codex thread open across continuation turns.
- `Orchestrator` treats a normal worker exit on an active issue as a continuation candidate and can
  dispatch the same issue again.
- token accounting is visible, but there is no budget enforcement.
- wide or non-executable tickets can still reach the dispatch path if ticket shaping is imperfect.

This creates a bad combination: a ticket stays active, the thread history grows, input context is
re-sent, and Symphony has no hard stop other than manual intervention.

## Goals

- Stop runaway token spend without requiring Codex protocol changes.
- Make cost control deterministic and enforceable inside Symphony.
- Avoid guessing the exact token cost of each ticket up front.
- Keep the first repair small enough to implement against the current architecture.
- Provide a clear path from immediate containment to a structural continuation fix.

## Non-Goals

- Perfect prediction of total token cost before a ticket starts.
- Semantic understanding of every Codex action.
- A distributed quota system or external database.
- Replacing ticket shaping discipline; guardrails are a backstop, not an excuse to run wide tickets.

## Root Cause Summary

Current behavior is driven by these implementation points:

- `elixir/lib/symphony_elixir/agent_runner.ex`
  - reuses one live session across turns
  - continuation prompt assumes prior thread context remains available
- `elixir/lib/symphony_elixir/orchestrator.ex`
  - schedules continuation retries after normal completion while the issue stays active
  - accumulates token totals but does not act on them
- `elixir/lib/symphony_elixir/prompt_builder.ex`
  - renders the full workflow prompt, but does not support budget-aware continuation modes

The result is not primarily a concurrency bug. One issue can consume millions of input tokens by
itself.

## Design Principles

### 1. Use budgets as stop-loss controls, not predictions

Symphony should not try to guess the exact token requirement of each ticket. Instead:

- start with a small probe budget
- continue only if the first turn produced evidence of progress
- enforce both soft and hard ceilings

### 2. Enforce locally in Symphony

The first repair should rely only on capabilities Symphony already has:

- live token updates
- worker termination
- tracker comments
- tracker state transitions
- workspace inspection

### 3. Separate immediate containment from structural continuation repair

There are two distinct problems:

- lack of hard stop conditions
- long-lived continuation threads carrying too much prior context

The first can be fixed quickly. The second requires a continuation redesign.

## Proposed Solution

The repair is split into **Phase 1 containment** and **Phase 2 continuation redesign**.

## Phase 1: Containment Guardrails

Phase 1 is the minimum viable fix and should ship first.

### A. Introduce an execution budget model

Add a new typed config section under `agent.guardrails`.

Example:

```yaml
agent:
  max_turns: 3
  guardrails:
    enabled: true
    mode: observe
    stop_state: Human Review
    create_comment_on_stop: true
    warning_cooldown_seconds: 60
    executable_labels: []
    blocked_labels: ["meta", "split-before-run", "manual-env"]
    probe:
      max_total_turns_per_issue: 1
      soft_total_tokens: 25000
      hard_total_tokens: 50000
      soft_input_tokens: 20000
      hard_input_tokens: 40000
    default:
      max_total_turns_per_issue: 3
      max_continuation_runs_per_issue: 2
      no_progress_turn_limit: 1
      soft_total_tokens: 120000
      hard_total_tokens: 180000
      soft_input_tokens: 100000
      hard_input_tokens: 150000
```

This design does **not** require per-ticket cost prediction. Every ticket starts in `probe` mode.

Continuation past the probe is allowed only when Symphony sees progress.

Probe evaluation is based on the outcome of the first *completed turn*. It is not meant to fire on
the first token event of that turn.

`agent.max_turns` keeps its current meaning: per-runner turn cap inside one `AgentRunner` lifetime.
The new `agent.guardrails.*` limits are issue-level ceilings across continuation retries and worker
restarts.

If the `agent.guardrails` block is absent, Symphony should behave as if `enabled: false` and bypass
all guardrail code paths entirely. Phase 1 should provide a cheap `guardrails_enabled?/0` config
check so the orchestrator can short-circuit early.

Config validation must also reject:

- `stop_state` values that are inside the active-state set
- label overlap between `executable_labels` and `blocked_labels`

Static config validation should **not** try to prove that `stop_state` exists in the tracker. That
is a runtime tracker concern because the real state lookup is tracker-specific.

The static checks that *do* belong in `Config.validate!/0` are:

- `stop_state` is present when guardrails are enabled
- `stop_state` is not part of the configured active-state set
- `executable_labels` and `blocked_labels` do not overlap

`mode` has two rollout-safe values:

- `observe`: record hits, expose them in status surfaces, but do not terminate workers or mutate
  tracker state
- `enforce`: terminate workers and execute the configured stop path

For compatibility, `executable_labels` should default to disabled (`[]`). Managed workflows that use
explicit `exec-ready` leaves should turn it on deliberately.

`executable_labels: []` means this specific allow-list check is disabled; it does **not** mean that
no issue can run.

Label matching should normalize both configured labels and tracker labels with trim + lowercase
comparison so tracker-side casing differences do not change eligibility decisions.

### B. Add a per-issue guardrail ledger

Extend orchestrator state with an issue-scoped ledger that survives worker restarts within the same
service lifetime.

Phase 1 keeps the full ledger in orchestrator memory. It is expected to survive worker restarts
inside the same Symphony process, but not arbitrary process restarts.

The ledger should mirror the corrected cumulative token values already stored on the running entry.
It should not run a second independent delta algorithm. Its job is cross-worker accumulation and
guardrail decisions, not token extraction.

Suggested shape:

```elixir
%{
  issue_id => %{
    issue_identifier: "LEI-48",
    mode: :probe | :default,
    stop_reason: nil | atom(),
    total_input_tokens: non_neg_integer(),
    total_output_tokens: non_neg_integer(),
    total_tokens: non_neg_integer(),
    total_turns: non_neg_integer(),
    continuation_runs: non_neg_integer(),
    no_progress_turns: non_neg_integer(),
    first_started_at: DateTime.t() | nil,
    last_turn_started_at: DateTime.t() | nil,
    last_turn_completed_at: DateTime.t() | nil,
    last_progress_fingerprint: term() | nil,
    last_warning_at: DateTime.t() | nil
  }
}
```

This ledger must be updated from absolute token snapshots already parsed in
`Orchestrator.integrate_codex_update/2`.

It must follow the accounting rules in `elixir/docs/token_accounting.md`:

- prefer absolute totals from `thread/tokenUsage/updated` or equivalent nested absolute totals
- do not add `turn/completed` usage on top of already-counted cumulative totals

### B0. Token accounting is a precondition

Phase 1 implementation should not assume the current token extraction path is already perfect.
Before guardrails trust `running_entry.codex_*_tokens` as enforcement input, Symphony should verify
that `extract_token_delta/2` and `turn_completed_usage_from_payload/1` do not double-count
turn-level usage on top of live thread totals. Guardrails should consume the corrected running-entry
totals after that audit, not invent a separate token accounting model.

Phase 1 persists only the stop/hold marker and related stop metadata to the workspace. It does not
persist the full in-memory ledger yet. That is an intentional scope limit for the first milestone.

### B1. Give the orchestrator control after every turn

Today `AgentRunner` can continue internally before the orchestrator regains control. That makes the
design phrase “after the current turn completes” untrue unless the execution boundary changes.

Phase 1 therefore needs an explicit orchestration gate between turns:

- `AgentRunner` may keep the current `AppServer` session alive across turns so the existing Codex
  thread context is preserved
- after each completed turn, and before starting the next continuation turn, `AgentRunner` must ask
  the orchestrator whether continuation is allowed
- continuation decisions still happen in the orchestrator, not inside `AgentRunner`

Recommended interface shape:

```elixir
request_continuation(orchestrator_pid, issue_id, turn_number) ::
  {:allow, :probe | :default} | {:deny, stop_reason}
```

Recommended transport:

- `GenServer.call/3` with an explicit timeout
- on timeout, default to `{:deny, :orchestrator_unavailable}` rather than continuing blindly

`AgentRunner` should use the existing orchestrator recipient PID rather than depending on a global
registered name lookup.

This is intentionally different from “one worker invocation equals one turn”. Destroying the worker
and `AppServer` session after every turn would start a fresh Codex thread on the next retry and
lose the thread-local context that the current continuation prompt depends on.

The Phase 1 requirement is therefore:

- preserve the live session inside one `AgentRunner` lifetime
- move the continuation decision point out of recursive local logic and into an orchestrator-owned
  synchronous permission check

Without this change, soft-budget and no-progress decisions cannot reliably run between turns. With a
forced one-turn worker boundary, continuity would break before Phase 2 summary-based continuation is
available.

### C. Enforce hard stop conditions in the orchestrator

Add a pure budget evaluation step after each Codex update and after each turn completion.

There are two enforcement timings:

#### Real-time checks during a turn

- ticket total tokens exceed `hard_total_tokens`
- ticket input tokens exceed `hard_input_tokens`

These should be checked from token events as they arrive so Symphony does not wait for a natural
turn end after the budget is already blown.

#### Turn-boundary checks before continuation

- continuation runs exceed `max_continuation_runs_per_issue`
- total turns exceed `max_total_turns_per_issue`
- no-progress turns exceed `no_progress_turn_limit`

Probe-mode promotion and no-progress evaluation also happen here, after a full turn completes.

Hard stop conditions therefore include:

- ticket total tokens exceed `hard_total_tokens`
- ticket input tokens exceed `hard_input_tokens`
- continuation runs exceed `max_continuation_runs_per_issue`
- total turns exceed `max_total_turns_per_issue`
- no-progress turns exceed `no_progress_turn_limit`

`max_wall_clock_minutes` can be added later as an optional policy, but it should not block
Milestone 1.

When a hard stop trips in `enforce` mode:

1. prefer a graceful stop signal at the next safe turn boundary when possible
2. if immediate termination is required, terminate the worker using the last known absolute token
   totals already recorded by the orchestrator
3. add a tracker comment with the stop reason and measured usage
4. move the issue to `stop_state`
5. mark the ledger as stopped
6. make the issue ineligible for redispatch

If tracker state transition fails, Symphony should still:

- terminate the worker
- log the stop failure
- persist `shared/guardrail_state.json` so the same issue is not immediately redispatched in the
  current process or after a restart

The guardrail stop path must suppress the normal retry path. In practice this means the orchestrator
needs an explicit “stopped by guardrail” terminal branch rather than letting the worker appear to
crash and fall into the generic retry logic.

Guardrail stop must take precedence over all ordinary continuation and retry scheduling:

- once the ledger is marked `held` or `stopped_by_guardrail`, both continuation and retry are
  short-circuited
- `:DOWN` handling should identify guardrail stops by consulting the pre-marked ledger state instead
  of relying only on exit-reason semantics
- the hold is cleared only when the issue leaves the active-state set, or when an operator
  explicitly resets the hold

Because forced termination can race with the final app-server token messages, guardrail comments and
telemetry should explicitly use the orchestrator's last known absolute totals. Exact final token
parity is not required once the hard limit has already been breached.

### D. Add soft budget warnings

Soft thresholds should not stop execution immediately. They should:

- emit a structured warning log
- appear in dashboard/API payloads
- force stricter continuation checks after the current turn completes

Soft thresholds are the trigger for “prove that continuing is worth it”.

Warnings must be rate-limited so one noisy token stream does not flood logs or the dashboard.

`last_warning_at` should use a configurable or default cooldown. Phase 1 default: `60` seconds.

If an issue has already crossed a soft threshold and the remaining hard-token budget is very small,
the orchestrator may skip further continuation and convert the next decision into a hard stop rather
than spending the remainder on low-confidence progress.

### E. Gate dispatch by executable labels

Symphony should refuse to dispatch issues unless they are explicitly executable.

Rule:

- if `executable_labels` is configured, the issue must contain at least one of them
- if the issue contains any `blocked_labels`, it is never executable

This is a direct protection against parent/gate/workstream tickets entering execution.

The same eligibility check must also run during reconciliation so an already-running issue is
stopped if its labels or state change and make it ineligible.

Implementation should centralize this in one pure predicate, for example
`Guardrails.executable_issue?/2`, so dispatch and reconciliation cannot drift apart.

### F. Add a minimal progress detector

Progress detection should be cheap and deterministic.

For Phase 1, progress is defined as a change in workspace fingerprint across completed turns.

Suggested fingerprint:

- changed file count
- added/removed line totals from `git diff --numstat`
- sorted changed file list hash

The fingerprint does not need to prove correctness. It only needs to answer:

“Did this turn create a materially different reviewable workspace state?”

If a turn completes and the fingerprint is unchanged from the previous completed turn:

- increment `no_progress_turns`

If it changed:

- reset `no_progress_turns`
- promote from `probe` to `default` budget mode if the issue was still in probe

The first completed turn establishes the fingerprint baseline. It does not count as no-progress even
if the resulting workspace is unchanged.

If the workspace is not a Git repository, the fallback fingerprint should use:

- relative file list hash
- file size totals
- content hashes for non-ignored files

Fallback scanning should honor the same ignore set used for workspace hygiene and may enforce a
reasonable file-count cap if future profiling shows a need. Phase 1 should optimize for correctness
over premature micro-optimization.

This is intentionally a coarse stop-loss signal. It should not be documented as a correctness or
semantic progress detector. In Phase 1 it is only a secondary stop condition behind token and
continuation limits.

Workflows that legitimately have low-file-change turns should be able to disable this condition by
setting `no_progress_turn_limit` to `0`.

### G. Make continuation limits apply across worker lifetimes

`agent.max_turns` currently caps turns only inside one `AgentRunner` invocation. It does not cap
the total number of continuation runs for the issue.

Add a new issue-level limit:

- `max_total_turns_per_issue`
- `max_continuation_runs_per_issue`

This closes the current loophole where the worker returns control to the orchestrator and the same
issue is scheduled again with fresh room to continue.

`continuation_runs` should increment only when the orchestrator dispatches a new run because a prior
run ended normally and requested continuation. It should not increment for generic failure retries.

## Phase 2: Continuation Redesign

Phase 1 stops runaway spend. Phase 2 reduces spend by construction.

### A. Stop relying on long-lived thread history

Current continuation assumes:

- “the original task instructions and prior turn context are already present in this thread”

That assumption is exactly what makes input cost grow.

The redesign should switch to **fresh-session continuation**:

- one Codex turn per session
- continuation uses workspace state plus explicit summary artifacts
- prior full thread history is not assumed to remain in context

### B. Add workspace continuation artifacts

Persist structured continuation state under the issue workspace, for example:

- `shared/context_summary.md`
- `shared/guardrail_state.json`

These files should be produced by Symphony, not left to agent convention alone.

Minimum contents:

- issue identifier and title
- last completed turn number
- changed files
- validation commands observed or expected
- open blockers
- latest stop/warning reasons

These artifacts should be generated deterministically from Symphony state and workspace inspection.
Do not introduce a second LLM summarization step just to build continuation context.

### C. Introduce budget-aware prompt modes

`PromptBuilder` should support at least:

- `:initial`
- `:continuation_summary`

`continuation_summary` must tell Codex to rely on:

- workspace files
- summary artifacts
- the remaining scoped task

It must **not** claim that the full old thread is still present.

Authority order for continuation input should be explicit:

1. current workflow prompt template
2. current workspace state
3. `shared/context_summary.md`
4. `shared/guardrail_state.json`

The summary artifacts refine the continuation context; they do not replace the workflow contract.

### D. Prefer stateless continuation when cost risk is high

If a ticket has already hit a soft budget or a prior stop condition, the next automated run should
start from a fresh session with the summary artifacts rather than continuing the old thread.

## Proposed Module Changes

### New modules

- `elixir/lib/symphony_elixir/guardrails.ex`
  - pure budget evaluation
  - stop reason formatting
  - label-based execution eligibility
- `elixir/lib/symphony_elixir/workspace_progress.ex`
  - workspace fingerprint capture and comparison

### Extend existing modules

- `elixir/lib/symphony_elixir/config.ex`
  - parse `agent.guardrails`
- `elixir/lib/symphony_elixir/orchestrator.ex`
  - own guardrail ledger
  - enforce hard and soft thresholds
  - annotate comments and stop-state transitions
  - suppress retry scheduling for deliberate guardrail stops
  - persist and reload `shared/guardrail_state.json`
  - load persisted holds during startup, not on every poll loop
- `elixir/lib/symphony_elixir/agent_runner.ex`
  - surface turn lifecycle data cleanly
  - ask the orchestrator for continuation permission between turns while preserving the live session
  - stop assuming unlimited continuation is always valid
- `elixir/lib/symphony_elixir/prompt_builder.ex`
  - support continuation prompt modes
- `elixir/lib/symphony_elixir/status_dashboard.ex`
  - show budget mode, warnings, and stop reasons
- `elixir/lib/symphony_elixir_web/presenter.ex`
  - expose guardrail status and budget usage through `/api/v1/*`

## API and Dashboard Changes

Add these fields to running issue payloads:

```json
{
  "guardrails": {
    "mode": "probe",
    "soft_limit_reached": false,
    "hard_limit_reached": false,
    "stop_reason": null,
    "continuation_runs": 1,
    "total_turns": 1,
    "no_progress_turns": 0,
    "budget": {
      "soft_total_tokens": 25000,
      "hard_total_tokens": 50000,
      "soft_input_tokens": 20000,
      "hard_input_tokens": 40000
    }
  }
}
```

This makes the cost decision inspectable rather than implicit.

`/api/v1/state` and `/api/v1/:issue` also need a stopped/held projection, for example
`guardrail_holds` or `recent_guardrail_stops`, so a ticket remains inspectable after it leaves the
`running` set.

Minimum extra fields:

- guardrail `mode`: `observe` or `enforce`
- tracker writeback outcome: `comment_ok`, `state_ok`, or failure detail
- last hold timestamp
- whether the hold came from token limit, no-progress, continuation ceiling, or reconciliation

Example stopped/held projection:

```json
{
  "guardrail_holds": [
    {
      "issue_id": "issue-123",
      "identifier": "LEI-48",
      "stop_reason": "hard_input_token_limit",
      "stopped_at": "2026-03-10T11:00:00Z",
      "input_tokens": 4939357,
      "total_tokens": 4987997,
      "writeback": {
        "comment": "ok",
        "state": "failed"
      }
    }
  ]
}
```

## Tracker Writeback Contract

Guardrail stop comments should be machine-readable and concise.

The reported token fields should use the orchestrator's last known absolute totals. They are
expected to be accurate enough for enforcement and audit, but they do not need to match the final
post-kill app-server counters exactly.

Suggested format:

```markdown
Symphony stopped this run automatically.

- reason: hard_input_token_limit
- issue: LEI-48
- mode: probe
- total_tokens: 4987997
- input_tokens: 4939357
- total_turns: 3
- continuation_runs: 2
- next_action: split the ticket or resume from human review with a narrower scope
```

## Validation Plan

### Unit tests

- `Guardrails` budget evaluation
- config parsing for `agent.guardrails`
- label eligibility checks
- workspace fingerprint comparison
- continuation-run counting across retries

### Integration tests

- stop issue on hard total token limit
- stop issue on hard input token limit
- stop issue on no-progress limit
- refuse meta/manual-env tickets at dispatch time
- preserve issue hold when tracker stop-state write fails
- suppress retry scheduling after deliberate guardrail stop
- stop running issue when eligibility labels change during reconciliation
- observe mode records hits without terminating workers
- restart after guardrail hold does not redispatch the held issue
- startup hold scan restores persisted holds without per-poll workspace scanning
- stop-state runtime lookup failure leaves the issue held and inspectable

### Manual verification

- dashboard shows guardrail mode and warning state
- `/api/v1/state` exposes guardrail fields
- a stopped issue moves to `Human Review` and does not redispatch immediately

### Restart behavior

Phase 1 should persist a minimal stop marker under the issue workspace, for example
`shared/guardrail_state.json`, when a guardrail stop occurs. On restart, the orchestrator should
perform a one-time startup scan of `Config.workspace_root()` and load any persisted hold markers
into memory before normal polling begins. This avoids losing the local hold across process restarts
without introducing per-poll workspace I/O into the hot path.

If the tracker has already moved the issue to a non-active state, Symphony may clear the persisted
hold and resume normal eligibility checks. If the tracker still shows an active state, the hold
remains in force until an operator intervenes.

This restart behavior applies to the persisted hold marker, not the full in-memory ledger. Phase 1
does not attempt to reconstruct full historical token totals after a Symphony process restart.

## Rollout Plan

## Recommended Implementation Order

Phase 1 should be split and implemented in this order:

1. token accounting audit and correction of any `turn/completed` double-count risk
2. `Config` schema, getters, and static guardrail validation
3. orchestrator guardrail ledger plus continuation permission call API
4. explicit `:DOWN` guardrail-stop branch and retry suppression
5. presenter/dashboard held-issue projections

This order reduces rework because later steps depend on trustworthy token totals and stable
guardrail state shapes.

### Milestone 1

Ship Phase 1 only:

- config parsing
- in-session orchestrator continuation gate between turns
- execution eligibility gate
- budget ledger
- hard/soft stop enforcement
- stop comment/state transition
- dashboard/API exposure

Rollout should start on one guarded workflow first, then become the default once:

- the stop path has been exercised successfully
- dashboard/API fields are stable
- the new limits stop an intentionally wasteful ticket without causing retry loops

Recommended rollout gates:

1. `observe` only
2. `enforce` with comment-only writeback
3. `enforce` with worker stop + local persisted hold
4. `enforce` with tracker state transition
5. Phase 2 fresh-session continuation

### Milestone 2

Ship Phase 2:

- fresh-session continuation
- summary artifacts
- continuation prompt modes

## Why this design is feasible

The first milestone does not depend on:

- Codex protocol changes
- new infrastructure
- external persistence

It reuses capabilities Symphony already has:

- token updates
- worker termination
- tracker comments and state updates
- workspace access
- status surface APIs

That makes it an appropriate repair target for the current codebase rather than a speculative
rewrite.
