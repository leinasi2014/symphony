# Issue Shaping and Routing

Use this reference when deciding whether Symphony should run a ticket directly.

## Ticket Classes

### `meta`

Parent, phase, gate, or workstream issue.

- never assign directly to Symphony
- used for scope, blockers, comments, and rollup only

### `exec-ready`

Narrow leaf ticket that is safe to run directly.

Good shape:

- one coherent deliverable
- one primary validation path
- clear stop point
- limited dependency surface

### `split-before-run`

Too broad to run directly.

Typical signs:

- backend + frontend + docs + tests mixed together
- design + implementation + acceptance mixed together
- multiple external dependencies
- no obvious “done” boundary inside one run

### `manual-env`

Requires real external environment or operator validation.

## Routing Rule

For active execution workflows:

- set `tracker.assignee: "me"`
- leave `meta` issues unassigned
- assign only one `exec-ready` ticket at a time

## Narrow Ticket Heuristic

A ticket is usually safe for Symphony if it fits all of these:

- one sentence can describe the deliverable
- one code area is primary
- one main test or command validates it
- if the run stops after 1-4 turns, the partial output is still coherent

## Example from `edict-codex`

Bad:

- `LEI-19` as one direct long-running execution ticket

Better:

- parent gate ticket stays `meta`
- split into:
  - validation command/docs/tests
  - real auth/listing smoke
  - writeback lifecycle validation
