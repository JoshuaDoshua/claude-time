# claude-time

A daily summary of how long your Claude Code sessions were working, broken out by session name.
Run it ad hoc in the terminal. It reads Claude Code's own session logs, so there is nothing to
set up and nothing running in the background.

Requires Python 3. No other packages.

`time-log`, in the same folder, builds on this. See [time-log](#time-log) at the bottom.

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

# time-log

One day of evidence from Chronoid, Chrome, your calendar, Claude Code and Codex, and a suggested
timesheet. It only reads, unless you ask it to save a day. It suggests, and you decide what to log.

Requires Python 3. No other packages. It reads macOS locations, so it only works on this Mac.

## Usage

Inside Claude Code, in this folder:

```
/time-log                  # today
/time-log 2026-11-12       # one day
```

The command reads your Google Calendar through Claude's connector, asks you whether you attended any
event you have not accepted, and then runs the script. The calendar can only be reached from inside
Claude Code, which is why the command exists. It lives in `.claude/skills/time-log/SKILL.md`.

You can also run the script yourself. Without `--calendar` it counts no meetings.

```
./time-log 2026-11-12 --calendar events.json   # events.json: a list of {"title", "start", "end"}
./time-log 2026-11-12 --show Pavus             # the evidence behind one project
./time-log --threshold 10                      # idle gap in minutes (default 5)
./time-log 2026-11-12 --save                   # also save this run (see "Saving")
./time-log 2026-11-12 --saved                  # show the latest save of that day
```

`start` and `end` are ISO timestamps that include the offset, like `2026-11-12T11:00:00-05:00`.

## Saving

`--save` writes the day to `~/.claude-time/time-log/<date>_<time>.json`: every number, the items behind
them, the calendar events you passed in, and the notes. A file is about 30 KB.

- Nothing saves on its own. It only saves when you ask.
- Each save is a new file. A save never replaces an earlier one, so every save is kept.
- `--saved` shows the latest save of a day, with the same table and suggestion, and `--show <project>`
  works with it. It does not read the sources, so it still works after Claude Code's or Codex's logs
  are cleaned up. It shows the day as it was when saved, not as it is now.

Why: Claude Code's and Codex's logs get cleaned up, and the saved copy is what stays.

Saved files hold window titles, session titles and calendar event titles. Keep that in mind if you
share the folder.

## What the output means

```
Thursday 2026-11-12
                                HANDS-ON                      AGENTS RUNNING
  PROJECT                       Chronoid    Chrome  Calendar  Claude Code     Codex
  Bechtel                         0h 13m         –         –       6h 25m         –
  Innovation Exchange (as one)    2h 11m         –         –            –         –
    IX                                 –    0h 11m         –            –         –
    IX-LZ                              –    0h 03m         –            –    1h 38m
  Pavus                           0h 48m    0h 00m         –       0h 22m         –
  ...

Suggested timesheet
  PROJECT               Hands-on   Agents*   Meeting       Sum    LOG
  Bechtel                0h 13m     6h 05m    0h 00m    6h 18m   6.25
  Innovation Exchange    2h 11m     1h 23m    0h 00m    3h 34m   3.50
  Pavus                  0h 48m     0h 13m    0h 00m    1h 01m   1.00
  ...
```

**The table.** One row per project and one column per source. Each number comes from one source.
Nothing is combined or split between sources, and a source only removes overlap with itself. A dash
means that source has nothing for that project. Durations read `1h 33m`, and under an hour `0h 09m`.

- Chronoid has one "Innovation Exchange" category, so that row cannot tell IX from IX-LZ. The indented
  IX and IX-LZ rows come from Chrome and Codex.
- Below the table, "Left out" lists Chronoid time that is not a project (Meetings, Distraction, and time
  Chronoid did not assign). Your Chronoid timers that have no category are listed there too.
- Notes say what a source did not count, such as Chrome visits to sites that are not in the config.

**The suggestion.** One row per project, as a suggestion only.

- **Hands-on** is the Chronoid time for the project. If Chronoid has none, it is the Chrome estimate,
  marked †.
- **Agents** is the Claude Code and Codex time. It is shared evenly among the sessions running at the
  same moment, so two sessions running together each get half of that stretch.
- **Meeting** is the calendar minutes for events that map to the project.
- **Sum** adds the three. It does not check whether they overlap on the clock, so a project can be
  counted twice for the same hour, and the total can pass 8 hours. Nothing is scaled to 8.
- **LOG** is the Sum rounded to the nearest 0.25 hours, with 0.25 as the minimum. `?` means the evidence
  has no project yet. It is left out of the total.
- IX and IX-LZ are added together as Innovation Exchange here, as set in the config.
- A project with under 30 seconds in total is not listed. It is named on the last line.

## Where each column comes from

| Column | Source | How it is counted |
|---|---|---|
| Chronoid | `~/Library/Application Support/com.vu.Chronoid/db.sqlite`, read only | Tracked app time, idle excluded, under the category Chronoid assigned. A span counts on the day it starts. Your manual timers are listed, not added. |
| Chrome | The `Default` profile's history, read from a temporary copy | Only sites in the config. Visits no more than the idle gap apart count as time between them. This is an estimate. |
| Calendar | Events passed with `--calendar` | The scheduled length, for events you attended. An event goes to a project only if the config has a title rule for it. |
| Claude Code | `~/.claude/projects`, through `claude-time` | Claude's own turn timer (`durationMs`, logged after each turn), placed at the end of each turn. |
| Codex | `~/.codex/sessions` | Log entries no more than the idle gap apart. Approval-review sessions (`guardian_review`) are skipped. |

`--show <project>` lists the evidence behind a project: each Chronoid app, each Chrome site with its
visit count, each calendar event, and each Claude Code and Codex session. For each Claude Code session
it also shows the 5-minute rule number, how much more the open tool calls add, and how many turn timers
there are for how many prompts. Tool calls that sat open longer than the idle gap are listed with their
start, end and length, marked "not counted". Whether any of that time counts is for you to decide.

## The config

`time-log.config.json` holds every mapping. The first rule that matches wins. Anything that matches no
rule shows as Unmapped, and the tool never guesses a project.

| Key | What it maps |
|---|---|
| `chrome` | The profile and account to read, and `sites`: a URL prefix to a project |
| `claude_sessions` | `cwd_contains` (the folder, as `claude-time` shows it) or `title_contains` to a project |
| `codex_sessions` | `cwd_contains` to a project |
| `calendar.calendars` | Which calendars `/time-log` reads |
| `calendar.events` | `title_contains` to a project |
| `non_project_categories` | Chronoid categories that are not projects |
| `rollup` | Projects added together in the suggestion |

Add a mapping when you have decided one, not before.

## Limits

- Chronoid only has data from 2026-11-12. Earlier days show "no data" for it.
- It only sees this Mac.
- The turn timer is not documented by Claude Code. It is logged only when a turn ends, so a turn that
  was interrupted or is still running has none. The table placing each timer at the end of its turn is
  an approximation.
- The log cannot tell a tool call that is running from one waiting for your approval. Both look like a
  call that has not returned yet. That is why open calls are shown and not counted.
- Hands-on time and agent time overlap on the clock. The suggestion adds them anyway.
- Chrome only counts the sites in the config.
- Meetings are the scheduled length. They do not say what you worked on during them.
- It does not know whether you were at the keyboard while an agent ran.

`DECISIONS.md` has the rulings and discussion behind these choices, in your own words, including what
was dropped and what is still open.
