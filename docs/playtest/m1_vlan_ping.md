# Playtest checklist: m1_vlan_ping

Plan task 1.33. Run on the lowest-spec machine available (Compatibility
renderer, Intel HD 4000-class target). Ideally one run is by someone who has
not read the solution. Record findings under "Findings"; each bug becomes a
fix commit plus a regression test where it touches the sim.

Setup: `godot --path .`, start from the main menu. Note machine, OS, build.

## 1. Flow
- [ ] Game starts on the main menu; Start, Settings and Quit all work.
- [ ] Briefing card appears, is readable, and closes with a clear key.
- [ ] HUD shows 5 objectives, 1 spare cable, and the H-key hint line.
- [ ] Debrief card appears on completion with the Day One text.
- [ ] Progress is saved (`user://progress.json`) and the menu reflects it.
- [ ] After debrief, the player can return to the menu or replay.

## 2. Movement and interaction
- [ ] WASD, mouse look and crouch feel right; no falling through the floor.
- [ ] Crosshair prompt names the target (port or device) and its state.
- [ ] Locked cables cannot be unplugged; the reason is shown.
- [ ] The spare cable can be picked up, plugged in, unplugged and reused.
- [ ] Plugging into `R1:Gi0/1` (reserved) is rejected with a clear message.
- [ ] Cancelling a held cable returns it; spare count stays correct.
- [ ] Cable meshes and port LEDs match sim state after each change.

## 3. Terminal
- [ ] Console port (R1, S1) and PC screens open the terminal; Esc closes.
- [ ] PC-A and PC-B are locked: no config changes are possible from them.
- [ ] Up/down history, Tab completion and `?` work.
- [ ] Abbreviations work (`sh ip int br`, `conf t`, `int g0/0.10`).
- [ ] Error strings match real IOS (`% Invalid input detected ...`).
- [ ] `show vlan brief`, `show ip interface brief`, `show running-config`
      read correctly after each step.
- [ ] `ping` output and PC `ping` read well.

## 4. Hints (press H)
- [ ] At mission start: a hint is shown (parking lot: HOST_UNREACHABLE has
      none today, so H says "No hint for this step").
- [ ] After cabling PC-B: hint is about the VLAN or gateway.
- [ ] Hints never reveal the exact commands.

## 5. Shortcuts (must not complete the mission)
- [ ] Plugging PC-B straight into R1:Gi0/1 is rejected.
- [ ] Changing PC-A/PC-B IPs or gateways is impossible.
- [ ] Putting both PCs in one VLAN and subnet does not finish it.
- [ ] Router IP on Gi0/0 directly (no subinterfaces) does not finish it.

## 6. Performance (lowest machine)
- [ ] Steady frame rate in the room (record FPS: ____).
- [ ] No hitch opening or closing the terminal.
- [ ] Load time from menu to room (record: ____ s).

## 7. New-player run (exit criterion)
- [ ] Finished without reading the solution. Time: ____ min.
- [ ] Where did they get stuck? ____

## Findings
| # | Area | What happened | Severity | Fix / test |
|---|------|---------------|----------|------------|
|   |      |               |          |            |
