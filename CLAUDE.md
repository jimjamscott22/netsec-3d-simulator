# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project state

A Godot 4.7 (GDScript, Compatibility renderer) first-person game that teaches
CCNA-level networking and entry-level security: the player cables gear in a
server room and fixes it through an IOS-style terminal.

The Godot project exists (`project.godot`, empty `game/main.tscn`, folder
layout from the plan). There is no sim code or test runner yet. Work continues
at task 0.2 of the plan (install GdUnit4).

## Source of truth (read before working)

- `docs/SPEC.md`: what the game is. It wins over everything else on scope.
- `docs/IMPLEMENTATION_PLAN.md`: the order of work. Do tasks top-down, one at a
  time. Tick the box (`- [x]`) in the same commit that finishes a task. Put
  ideas that come up mid-task in the plan's "Parking lot", not in the current
  task.
- `.claude/skills/netsec-sim/SKILL.md`: the architecture rules. Load the
  `netsec-sim` skill for any work here. Its references hold the detailed
  contracts:
  - `references/ios-cli.md`: CLI modes, prompts, exact error strings, commands per milestone.
  - `references/scenario-schema.md`: scenario JSON schema and objective types.
  When you add a command or objective type, update the matching reference file.

Note: the SPEC adds `sim/logs/` and `sim/web/` (M2/M3), which the skill's
layout diagram leaves out.

## Commands

These are the commands the plan sets up (GdUnit4 in `addons/gdUnit4`, purity script in `tools/`):

```sh
# Run all tests headless (Linux/macOS)
addons/gdUnit4/runtest.sh -a res://tests
# Run one suite or directory (example path; suites mirror sim/)
addons/gdUnit4/runtest.sh -a res://tests/net/test_resolver.gd
# Sim-core purity check (CI fails on any hit)
tools/check_sim_purity.sh
```

If the GdUnit4 runner path or flags differ in the installed version, check its
docs instead of guessing. CI (`.github/workflows/ci.yml`, task 0.4) runs Godot
headless on Ubuntu: it imports the project, then runs the purity check, then GdUnit4.

## Architecture in one screen

Dependencies only point inward: `world/` and `ui/` → `game/` (the `Sim` autoload) → `sim/`.

- **`sim/` is a pure, deterministic core.** Classes are `RefCounted`/`Resource`,
  never `Node`. No `get_tree`, `Input`, `Time`, `OS.get_ticks_*`, timers,
  `await`, randomness, autoloads, or imports from `world/`/`ui/`/`game/`. Any
  timing (ping animation, boot delay) is cosmetic and lives in the UI.
- **`NetworkSim`** (`sim/core/`) is the only entry point for state changes. It emits
  past-tense signals on `SimEvents`. Its public API and signal table are in
  SPEC §3.3–3.4.
- **`game/sim.gd` (`Sim` autoload)** owns one `NetworkSim`, does all file IO
  (scenario JSON), and re-emits signals. It is the only path from the
  presentation layer into the core.
- **Read-only views** (`scenario_view`, `device_view`, `objective_states`,
  `report_view`, `patch_views`, `debrief_view`) are how the world and UI see
  state. The presentation layer never reads scenario JSON or imports `sim/`
  scripts (not even `models.gd`). Views never contain answers, `solution`,
  `accept` regexes, server `files`/`vulns`, or exploit metadata. The exception
  is `debrief_view`, which only returns data once the mission has ended.
- **Connectivity has no packets.** `ping()` does a deterministic path search
  (L1 oper-up → next-hop decision → L2 BFS within a VLAN → router pipeline →
  the reply path must also resolve). It returns a precise `FailReason`, and the
  first reason hit wins, because mission hints are keyed on it.
- **Scenarios** are JSON in `scenarios/`. They are fully validated (errors
  carry JSON paths, and all errors are reported at once) before any state is
  built. Objectives are pure predicates, re-evaluated on events and never polled.
- **Interface names** are stored in canonical full form. Normalize all input
  through `sim/net/ifname.gd`. Ports are addressed as `"<device_id>:<FullName>"`.
- **The CLI** uses a `CommandRegistry` that handles unique-prefix abbreviation,
  `no`, `?`, Tab and `do` centrally. All `show` output comes from
  `sim/cli/formatters.gd` and is golden-tested. A handler returns a `CliResult`
  whose `ShellAction` asks the UI to act (for example to open the editor). The
  core never references UI classes.

## Rules that are easy to miss

- **Missions must resist shortcuts.** A teaching mission pairs its `ping`
  objective with `config` objectives, `to_device`/`via`, `locked` hosts and
  `reserved_ports` (SPEC §7.3). Every known bypass becomes a regression test
  or a `reject_fixtures` entry.
- Every sim change ships with GdUnit4 tests in the same commit. A CLI command
  needs three kinds of test: parse (with abbreviations), state change, and
  `show` golden. Every scenario file needs a smoke test: it fails at the
  start, then passes after applying its `solution`.
- Use static typing everywhere, `class_name` on reusable scripts, and enums
  (never string literals) for modes and fail reasons.
- `.tscn` files belong to the editor: only make small, surgical text edits.
  Never touch `.godot/` or `*.import`.
- Line endings are LF everywhere except `*.cmd`/`*.bat`/`*.ps1` (CRLF, see
  `.gitattributes`).
- Before finishing any task, run the purity check and the full test suite and
  report the results.
