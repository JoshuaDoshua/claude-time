# claude-time

A daily summary of how long your Claude Code sessions were working, broken out by session name.
Run it ad hoc in the terminal. It reads Claude Code's own session logs, so there is nothing to
set up and nothing running in the background.

Requires Python 3. No other packages.

## Usage

```
./claude-time                      # today
./claude-time 2026-11-10           # one day
./claude-time --days 7             # the last 7 days that had activity
./claude-time --threshold 10       # idle gap in minutes (default 5)
./claude-time --save               # also save each shown day (see "Saving")
./claude-time --json               # machine-readable output
```

`--days` cannot be combined with a single date.

## What the output means

```
Tuesday 2026-11-10
  SESSION                                PROJECT      RUNNING  ACTIVE BETWEEN
  translations                           bechtel        1h45m  10:02–22:24
  pavus-memory                           pavus          0h40m  10:01–18:00
  [auto] Rebuild sail docker containers  scc            0h11m  14:30–15:53

  By project (overlaps removed)
                                         bechtel        1h45m
                                         pavus          0h40m
                                         scc            0h11m

  Clock time 2h20m (overlaps removed)  ·  Sum of sessions 2h49m  ·  Open span 24h26m
```

- **RUNNING** is how long that one session was working, counted on its own. Other sessions
  running at the same time do not change it.
- **ACTIVE BETWEEN** is the first and last message of the session on that day.
- **By project** merges the sessions of each project. When two sessions in a project were
  working at the same moment, that time is counted once.
- **Clock time** merges every session on the day the same way. This is the real amount of
  time during which at least one session was working.
- **Sum of sessions** adds up every session's running time. Parallel sessions stack, so it
  can be larger than clock time.
- **Open span** adds up each session's first-to-last-message time. A session left open all
  day makes this large, so it is not a measure of work.

Sessions are listed longest first. A session that crosses midnight is split, and each day
counts only its own part.

### How "working" is counted

Each Claude Code log entry has a timestamp. Two entries in the same session that are no more
than `--threshold` minutes apart (default 5) count as working time between them. A longer gap
is treated as idle and not counted. Subagent activity counts toward the session that started it.

This shows when Claude was working. It does not show whether you were at the keyboard.

## Session names

The tool uses the name you gave the session, with `claude -n "<name>"` at launch or `/rename
<name>` inside the session. A session you have not named shows Claude's generated title with
`[auto]` in front, so you can see which ones still need a name when you fill in your time
tracking. A session with no title at all shows as `(untitled)`.

A rename is written to the session's log, so it also applies to the days that session ran
before you renamed it.

The project is the folder the session was started in, shown by its last folder name.

## Where the data comes from

Claude Code writes one log file per session:

```
~/.claude/projects/<project folder>/<session id>.jsonl
~/.claude/projects/<project folder>/<session id>/subagents/<agent id>.jsonl
```

The tool stores nothing of its own unless you use `--save`. Each run reads those files again
and recomputes everything. Times are shown in your local timezone.

## Saving

`--save` writes each day it shows to `~/.claude-time/<date>.json`.

```
./claude-time --days 400 --save    # save every day the logs currently cover
./claude-time --save               # save today
```

Why: if Claude Code's logs are ever cleaned up, or you move to another machine, the raw
history goes with them. Saved days stay.

- A day that Claude Code's logs no longer cover is shown from its saved file, with a note at
  the bottom.
- A save never replaces a saved day with one that has less session time. This protects an
  archive from logs that were partly deleted.
- Saving today again later in the day replaces the earlier copy of today.
- The tool picks the log copy or the saved copy of a day. It does not merge the two. If the
  logs lose some of a day's sessions and you then add a new session that same day, the new
  session will not show until the logs hold more session time than the saved copy.
- Nothing runs `--save` on its own.

Saved files hold session titles and project folders. Keep that in mind if you share the folder.

## Limits

- It only sees sessions on this machine, in `~/.claude/projects`.
- It only sees Claude Code activity. Meetings, Slack, browser and other work are not tracked.
- It does not know whether you were watching. A session running tools while you were in a
  meeting counts as running.
- The idle threshold is a guess. Check a day against your own memory before relying on it, and
  adjust `--threshold` if the numbers look too high or too low.
- Days saved with one threshold and viewed with another are not recalculated. Each saved file
  records the threshold it used (`threshold_minutes`).
