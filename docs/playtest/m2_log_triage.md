# Playtest checklist: m2_log_triage

Plan task 2.12. Run on the lowest-spec machine available (Compatibility
renderer, Intel HD 4000-class target). Ideally one run is by someone who has
not read the solution or the logs' story. Record findings under "Findings"; each
bug becomes a fix commit plus a regression test where it touches the sim.

Setup: `godot --path .`, start from the main menu with a save that has not
completed M2 (delete `user://progress.json` for a clean run). Note machine, OS,
build. The answers are in `scenarios/m2_log_triage.json`; a new-player run
should not open it.

## 1. Flow
- [ ] Mission select lists "Day One: Get Them Talking" and "Who Knocked?" in
      that order. With a fresh save, mission 2 reads Locked and its Start
      button is disabled.
- [ ] After completing mission 1, mission 2 reads Not started and starts.
- [ ] Briefing card (ticket SEC-2231) appears, is readable, and closes with a
      clear key.
- [ ] HUD shows 3 objectives, each with "(3 attempts left)". It shows "Tab
      objectives" only: no "H hint" prompt and no "Spare cables" line, and
      pressing H does nothing.
- [ ] Debrief card appears on completion with the report answers and the cited
      log lines, and Continue returns to the menu.
- [ ] Progress is saved (`user://progress.json`) and the menu shows mission 2
      as Completed.

## 2. The room and the SOC desk
- [ ] Two server models sit in rack A (slots 1 and 2), with a socket and a
      console port on the front.
- [ ] A third desk stands between the two PC desks with a monitor on it. The
      monitor is lit, and the crosshair reads "SOC monitor" when aimed at it.
- [ ] On mission 1 the same monitor is dark and shows no prompt.
- [ ] Interacting with the monitor opens the log viewer; Esc returns to the room.

## 3. Log viewer
- [ ] Three files are listed, each with its device, path and line count, and
      none is cut off. Up/Down change the file.
- [ ] Lines show their file line numbers and are readable at 1280x720.
- [ ] Typing in the filter keeps only matching lines (any letter case) and
      highlights each match; the count line says "N of M lines".
- [ ] A filter with no match says so. A filter containing `[` and `]` works.
- [ ] The filter text stays when switching files and clears when the viewer is
      reopened.
- [ ] PgUp/PgDn scroll. F2 (or the "File report" button) opens the report form.

## 4. Server consoles
- [ ] The console port on WEB1 and DB1 opens a shell with prompt `analyst@web1:/$`;
      Esc closes it.
- [ ] `ls /var/log`, `cat`, `grep` (with and without `-i`), `tail -n` and `help`
      work and match what the viewer shows.
- [ ] Errors read sensibly (unknown file, wrong usage, unknown command).

## 5. Report form
- [ ] One row per field: Attacker IP (an IPv4 box), Attack type (a list of six
      options), Compromised account (a text box).
- [ ] A wrong answer says "Not correct." and the attempts drop by one.
- [ ] A malformed IP, an empty box or an unpicked option is explained and costs
      nothing.
- [ ] A right answer shows "Solved", locks the row, and keeps the answer shown.
- [ ] Enter in a box submits that field; Esc closes the form.
- [ ] Completing the last field ends the mission; the debrief waits until the
      form is closed.

## 6. Failing and retrying
- [ ] Using up the attempts on any field closes any open window at once and
      shows the failed card: "TICKET FAILED", the failed objective marked `[!]`,
      the answers, what you filed and the evidence lines.
- [ ] Esc does not dismiss the card. Tab moves focus between Retry and Main menu,
      and Enter picks the button with focus (Retry to start with).
- [ ] Retry reloads the mission with 3 attempts on every field and shows the
      briefing again. Main menu leaves for the menu. Nothing is saved as completed.

## 7. Fairness (the answer must come from the logs)
- [ ] The answers do not appear in the briefing, the HUD, the form or any view
      during play.
- [ ] One address (203.0.113.45) fails dozens of logins and then gets in as
      `deploy`; no other address does both.
- [ ] The scanner (192.0.2.88, a handful of failures, never gets in) and the
      legitimate `deploy` key logins from the CI server do not confuse a careful
      reader into a wrong answer.
- [ ] The attack-type list has six options, so guessing it is not a coin flip.

## 8. Performance (lowest machine)
- [ ] Steady frame rate in the room (record FPS: ____).
- [ ] No hitch opening or closing the viewer, the form or the terminal, or
      scrolling a 100-line log.
- [ ] Load time from menu to room (record: ____ s).

## 9. New-player run (exit criterion)
- [ ] Finished from mission select without reading the solution. Time: ____ min.
- [ ] Which clue did they find first, and where did they get stuck? ____

## Findings

First scripted run: see `results/m2_log_triage/PLAYTEST.md`.
| # | Area | What happened | Severity | Fix / test |
|---|------|---------------|----------|------------|
|   |      |               |          |            |
