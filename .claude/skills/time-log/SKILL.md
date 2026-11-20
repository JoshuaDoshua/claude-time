---
name: time-log
description: Show the evidence for one day of work and a suggested timesheet. Use when the user asks for their time log, timesheet, or a day's time summary.
argument-hint: "[YYYY-MM-DD]"
---

Run from the repo root of claude-time. The day is the argument, or today if none is given.

1. Load the Google Calendar tools with ToolSearch, then list that day's events for each calendar in
   `time-log.config.json` under `calendar.calendars`. Use only those calendars.
2. Keep the title, start and end of every event, and the user's own response to it (`accepted`, `declined`,
   `needsAction` or `tentative`). If the conference is not Zoom, also keep its platform (`Google Meet`,
   `Microsoft Teams`). Do not ask the user about attendance. `time-log` marks events the user has not accepted
   as unaccepted, guesses attendance from the Zoom meeting window in Chronoid, and labels the guess as a guess.
3. Write every event, not only accepted ones, to a JSON file in the scratchpad: a list of
   `{"title", "start", "end", "response"}` plus `"platform"` when it is not Zoom. Start and end are ISO timestamps
   that include the offset.
4. Run `./time-log <date> --calendar <file>` and show its output as it is, including the lines about unaccepted events.
5. `./time-log <date> --show <project>` lists the evidence behind one project. Use it when the user asks to see proof.
6. Add `--save` to the run only when the user asks to save the day. `./time-log <date> --saved` shows the latest
   save of a day without reading the sources.

Rules:
- The output is a suggestion only. Never write it anywhere, and never change the numbers to reach 8 hours.
- Do not split or combine time between projects or sources, and do not add mapping rules. Mappings live in
  `time-log.config.json` and change only when the user states one.
- Ask about one unmapped item at a time, and only when the user wants it mapped.
- Keep replies short. No long explanations.
