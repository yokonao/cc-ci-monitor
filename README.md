# cc-ci-monitor

Watch a PR's CI checks and emit line-delimited JSON events, one per line:
`{"event": "...", "data": {...}}`.

Designed for [Claude Code](https://claude.com/claude-code)'s `Monitor` tool: the
stream is a wake feed carrying only actionable transitions. Green is the only
terminal state (exit 0); a red run keeps watching, since a fix push starts a new
run.

## Requirements

- [`gh`](https://cli.github.com/) authenticated (`gh auth login`)
- Ruby (stdlib only)

## Installation

Place `monitor.rb` in your `$PATH` as `cc-ci-monitor` and make it executable:

```
install -m 755 monitor.rb ~/.local/bin/cc-ci-monitor
```

## Usage

```
cc-ci-monitor <pr | url | branch> [--interval SECONDS]
```

`--interval` defaults to 30 seconds.

## Prompt

Tell Claude Code to watch CI after it pushes. In your `CLAUDE.md`:

```
After creating a PR or pushing a fix, watch its CI with the Monitor tool:

  Monitor({ command: "cc-ci-monitor <pr>", description: "PR <pr> CI" })
```

## Events

| event           | when                                | data          | exit |
| --------------- | ----------------------------------- | ------------- | ---- |
| `check_failed`  | a check went red (once per failure) | `name`, `url` | —    |
| `checks_passed` | all checks settled green            | `total`       | 0    |

```json
{"event":"check_failed","data":{"name":"test","url":"https://…"}}
{"event":"checks_passed","data":{"total":3}}
```

After `MAX_FETCH_FAILURES` consecutive `gh` failures, the process exits non-zero
with a message on stderr (not an event).

## Tests

```
ruby test/monitor_test.rb
```
