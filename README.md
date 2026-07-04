# cc-ci-monitor

Watch a PR's CI checks and emit line-delimited JSON events. Built to run under
[Claude Code](https://claude.com/claude-code)'s `Monitor` tool — no direct
dependency on it, but the event model is tuned for that fix-and-push loop.

## Why

The event stream is a *wake feed* for a consumer that re-reads current reality on
each event. It carries only actionable transitions — no retractions, no progress
pings. Green is the sole terminal (exit 0); a red run is not, because a fix push
starts a new run, so it keeps watching until everything is green.

## Usage

```
ruby monitor.rb <pr | url | branch> [--interval SECONDS]
```

`--interval` defaults to 15 seconds.

## Events

Each stdout line is one JSON object: `{"event": "...", "data": {...}}`.

| event | when | data | exit |
|-------|------|------|------|
| `check_failed` | a check went red (once per failure) | `name`, `url` | — |
| `checks_passed` | all checks settled green | `total` | 0 |

A check going green is silent; success is reported once, when the whole set
settles. Monitor health is out of band — after `MAX_FETCH_FAILURES` consecutive
`gh` failures the process exits non-zero with a message on **stderr**, never as
an event.

## Requirements

- [`gh`](https://cli.github.com/) authenticated (`gh auth login`)
- Ruby (uses only the stdlib)

## Claude Code

Run it under the `Monitor` tool so events arrive as notifications while you keep
working:

```
Monitor({
  command: "ruby monitor.rb 123",
  description: "PR #123 CI checks",
  timeout_ms: 3600000,
})
```

The script exits 0 on green, so the watch ends cleanly when CI is clean.
