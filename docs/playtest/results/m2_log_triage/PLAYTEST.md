# M2 log triage playtest

November 24, 2026. Tested `dd464b1` plus the three fixes in the commit that adds this file. The checklist is `docs/playtest/m2_log_triage.md`.

Linux container, Godot 4.7.2, Compatibility renderer at 1280×720. The rendered run used Xvfb and Mesa llvmpipe (software OpenGL, no GPU). A temporary driver script, kept outside the repository, sent real key and action events through the viewport and placed the player within reach of targets; each interaction used the game's crosshair ray and the interact action. The run used a fresh save file and removed it afterwards. It was run twice, before and after the fixes below; the second run had 25 passing checks and none failing.

| Checklist section | Result | Evidence |
|---|---|---|
| Flow | Passed | The menu listed both missions in order. Mission 2 read Locked on a fresh save with a disabled Start button, and starting it was refused. After completing mission 1 it read Not started and started. The briefing showed and closed with Enter. The debrief card showed the report answers and evidence, waited for the open form, and progress for mission 2 saved. The HUD problem is finding 3. |
| Room and SOC desk | Passed | Both servers were placed in rack A. The monitor was online and the crosshair read "SOC monitor"; interact opened the viewer. The dark monitor on mission 1 is covered by `tests/world/test_room.gd`, not this run. |
| Log viewer | Passed after a fix | Three files; 103, 65 and 25 lines. Filtering "Accepted" kept 7 lines and the attacker's IP kept 55 of 103, with highlights and the count line. Switching files kept the filter. F2 opened the form. The file list clipped one name (finding 1). |
| Server consoles | Passed with a note | WEB1's console opened. `ls`, `grep`, `tail -n 3` and `service ssh status` ("unrecognized service", as designed for M2) behaved. `grep -c` is not supported (finding 4). |
| Report form | Passed | A wrong IP said "Not correct." and dropped to 2 attempts; a malformed IP was explained and cost nothing; the right IP read Solved. The last answer completed the mission and the debrief waited for Esc. |
| Failing and retrying | Passed after a fix | Three wrong answers closed the form and showed the failed card with the answers and evidence. Esc did not dismiss it. Tab moved focus to Main menu and Enter asked for the menu; on a fresh failure Enter asked for Retry, which restored 3 attempts and showed the briefing. The card's colors are finding 2. |
| Fairness | Passed | `tests/scenario/test_m2_log_triage.gd` pins it: exactly one address fails 10 or more times and then gets in, the scanner and the CI key logins are not the answer, evidence lines say what each field claims, and no live view shows an answer. |
| Performance | Smoke measurement only | Software rendering gave about 40 FPS idle in the room and 1.1–4.0 s from menu to the first room frames (shader compilation on the CPU). These say nothing about the target hardware. |
| New-player run | Open | The run used the known answers. |

## Findings

| # | Area | What happened | Severity |
|---|---|---|---|
| 1 | Log viewer | The file list was 340 px wide and showed each entry on one line, so "WEB1 /var/log/nginx/access.log (65 lines)" was cut off. **Resolution: fixed.** The list is 420 px wide and reads "WEB1  /var/log/nginx/access.log  (65)"; test `test_every_file_label_names_the_device_path_and_line_count`. | Low |
| 2 | Failed card | The objectives were drawn in the green used for a resolved ticket, so an unfinished `[ ]` and a failed `[!]` objective read as success. **Resolution: fixed.** A failed card uses the dark ink; test `test_a_failed_card_does_not_use_the_resolved_green`. | Medium |
| 3 | HUD | On a mission with no hints and no cable the HUD still showed "Spare cables: 0" and an "H hint" prompt, and H answered "No hint for this step". **Resolution: fixed.** The HUD hides the spare-cable line when the mission gives no cable, shows "Tab objectives" alone when it has no hints, and H does nothing there; tests `test_a_mission_without_hints_or_cables_hides_those_lines` and `test_a_mission_with_hints_and_a_cable_keeps_those_lines`. | Low |
| 4 | Server shell | `grep -c` and any counting (`wc -l`, `sort | uniq -c`) are not available, so counting failures per address has to be done by eye or with the viewer's "N of M lines" line. **Resolution: no change.** SPEC task 2.5 scopes the shell to `ls`, `cat`, `grep [-i]`, `tail [-n]`, `service` and `help`; the idea is in the plan's parking lot. | Low |
| 5 | Report form | The attack-type list shows a blank box until an option is picked. **Resolution: no change.** The field label says "pick one" and an unpicked list is refused with an explanation. | Low |

All 1,131 GdUnit4 tests passed across 59 suites after the fixes, and the simulation purity check passed.

## Still open for a human

This run was scripted under Xvfb with software rendering, so these are unverified: movement feel, frame rate and hitching on the lowest-spec machine, whether the logs read as a fair puzzle to someone who has not seen the answers, and the new-player run. Task 2.12 stays unticked until they are done.
