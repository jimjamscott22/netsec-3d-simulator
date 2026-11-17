# M1 VLAN ping playtest

November 16, 2026. Tested commit `c381c4d034b10473dbb1f4066439d4c367d9652e`. The checklist was introduced by `d0e9bf5`.

Ubuntu 26.04.1 LTS, Intel Core i7-13700F, Godot 4.7.2, Compatibility renderer at 1280×720. The rendered run used Xvfb and Mesa llvmpipe. A temporary driver sent Godot input events and placed the player within reach of targets. Each interaction used the game’s crosshair ray and E key. The run used a fresh save directory.

| Checklist section | Result | Evidence |
|---|---|---|
| Flow | Passed with an error on keyboard Continue | Start, Settings, Quit, briefing and five-objective HUD worked. The Day One debrief displayed all five ticks. Continue returned to the completed menu, progress persisted across a fresh process, and replay reset the mission. |
| Movement and interaction | Partial | WASD, mouse look, crouch, and floor contact worked in the automated input sample. Locked and reserved targets showed rejection messages. The spare cable could be picked up, cancelled, connected, disconnected and reused. The cable mesh count and LED updated. The crosshair omitted port state. Hands-on movement feel remains unverified. |
| Terminal | Passed sampled checks | R1, S1 and both PC terminals opened through the crosshair and closed with Esc. History, Tab, question-mark help, abbreviations, the IOS-style caret error, and configuration output worked. PC network settings were locked. Router ping returned 5/5. The rendered PC terminal showed ping statistics before completion, and the PC-A shell returned 4/4 directly after completion. |
| Hints | Passed | H showed the gateway hint at mission start and after cabling PC-B. The displayed hint named the problem without giving the command. The other mission hint strings contain no commands. |
| Shortcuts | Passed | The PC-B cable was rejected at the reserved port. Both PCs refused IP and gateway edits, preventing the same-subnet shortcut. Putting both switch access ports in VLAN 10 left the mission incomplete. Putting an IP directly on router Gi0/0 with no subinterfaces also left the mission incomplete. |
| Performance | Smoke measurement only | The warm menu-to-first-room-frame result was 0.35–0.47 s. After the first sample, idle readings were 103–161 FPS across the two Xvfb runs. Target hardware performance and terminal hitching remain unverified. |
| New-player run | Open | The run used the existing solution. An independent player still needs to try the mission and record completion time and sticking points. |

## Findings

| # | Area | What happened | Severity |
|---|---|---|---|
| 1 | Interaction | Aim at uncabled PC-B Eth0 or at S1 Fa0/2 after attaching the cable. The crosshair shows the port and device without a free or connected label. `PortSocket.set_interact_label()` builds the label from the port name and device ID. | Low |
| 2 | Debrief | Complete the mission and press Enter on the debrief. The menu appears and retains completion, but `MissionCard._input()` logs a null-viewport script error at `ui/mission_card.gd:51`. The close signal switches scenes before the input handler calls `get_viewport()`. | Low |

Both findings reproduced in two rendered runs. The worktree and existing save were left untouched.

All 828 GdUnit4 tests passed across 44 suites. The simulation purity check passed across 39 files. The GdUnit4 process reported object and resource cleanup warnings on exit.

Evidence files in this directory include `playtest-confirm.log`, `playtest-restart.log`, `tests.log`, and `09-debrief.png`.
