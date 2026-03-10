# Linear and Network

Use this reference when Symphony can talk to Linear poorly or differently from shell tools.

## Proxy Mismatch Lesson

Observed failure mode:

- `curl` to Linear succeeds
- `Req.post` / Erlang HTTP client to Linear times out
- Symphony panel becomes slow or shows `编排器快照不可用`

Root cause seen on this machine:

- shell tools succeeded because they honored `HTTPS_PROXY` / `HTTP_PROXY`
- Erlang HTTP clients timed out until Symphony explicitly passed proxy settings into `Req`

## What to Check

```bash
env | grep -iE 'http_proxy|https_proxy|all_proxy|no_proxy'
curl --max-time 8 -H "Authorization: $LINEAR_API_KEY" -H 'Content-Type: application/json' --data '{"query":"query { viewer { id } }"}' https://api.linear.app/graphql
```

Then compare with a tiny Elixir probe using `Req.post`.

## Workflow Parser Lesson

When adding a new workflow key, verify both:

1. the schema includes it
2. the extractor actually reads it

A real bug here was:

- workflow schema supported `tracker.assignee`
- parser did not extract `assignee`
- workflow appeared configured, but routing still ignored it

## Rebuild Lesson

If you patch code used by `bin/symphony`, `mix compile` is not enough. Rebuild the escript:

```bash
mise exec -- mix build
```

Then restart the running Symphony process.
