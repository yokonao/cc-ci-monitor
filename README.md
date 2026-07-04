# cc-ci-monitor

Watch a PR's CI checks and emit line-delimited JSON events, one per line:
`{"event": "...", "data": {...}}`.

Designed for [Claude Code](https://claude.com/claude-code)'s `Monitor` tool: the
stream is a wake feed carrying only actionable transitions. Green is the only
terminal state (exit 0); a red run keeps watching, since a fix push starts a new
run.

## Usage

```
ruby monitor.rb <pr | url | branch> [--interval SECONDS]
```

`--interval` defaults to 15 seconds.

## Events

| event | when | data | exit |
|-------|------|------|------|
| `check_failed` | a check went red (once per failure) | `name`, `url` | — |
| `checks_passed` | all checks settled green | `total` | 0 |

After `MAX_FETCH_FAILURES` consecutive `gh` failures, the process exits non-zero
with a message on stderr (not an event).

## Requirements

- [`gh`](https://cli.github.com/) authenticated (`gh auth login`)
- Ruby (stdlib only)
