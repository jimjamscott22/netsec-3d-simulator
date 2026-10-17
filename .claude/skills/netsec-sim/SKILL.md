---
name: netsec-sim
description: Architecture rules for the Godot 4 network and cyber security sim game. Use for any work in this project - sim core, Cisco IOS-style CLI commands, connectivity, scenarios/missions, 3D world, terminal UI, or tests.
---

# NetSec Sim — project architecture

A first-person Godot 4 game where the player cables up network gear in a server
room and configures it through an IOS-style terminal. The game is two layers:
a **pure-logic sim core** that owns all network truth, and a **presentation
layer** (3D world + UI) that only displays it and forwards player input.

If `SPEC.md` or `IMPLEMENTATION_PLAN.md` exist at the repo root, they win over
this skill on scope and ordering. Work the plan top-down and tick tasks off as
you finish them.

## Stack

- Godot 4.7 (Standard edition), **GDScript only**, static typing everywhere.
- Renderer: **Compatibility** (target is Intel HD 4000-class GPUs, and the web
  export requires it). Don't switch to Forward+.
- Tests: GdUnit4, under `res://tests/`.
- Scenarios: **JSON**, parsed with Godot's built-in `JSON` class. No YAML
  (it would need an addon).

## Layout

```
res://
  sim/                 # PURE LOGIC — see rules below
    core/              # NetworkSim facade, SimEvents, result types
    devices/           # Device, Router, Switch, Host, Interface
    cli/               # CliSession, mode enum, command registry, handlers
    net/               # Connectivity resolver, addressing helpers
    scenario/          # Loader, validator, objective evaluator
  game/                # Autoloads + glue (Sim autoload wraps NetworkSim)
  world/               # 3D: room, racks, devices, cables, player controller
  ui/                  # Terminal, threat map, log viewer, mission HUD
  scenarios/           # *.json mission files
  tests/               # GdUnit4 suites mirroring sim/
```

## The one rule that matters: the sim core is pure

Everything under `res://sim/` must obey these, no exceptions:

1. Classes extend `RefCounted` (or `Resource` for saved data). **Never `Node`.**
2. No `get_tree()`, `Input`, `OS.get_ticks_*`, `Time`, timers, `await`, `randf()`,
   or autoload references. The core is deterministic: same state + same input
   = same output, always.
3. No imports from `world/`, `ui/`, or `game/`. Dependencies point inward only.
4. All state changes go through `NetworkSim` methods, which emit typed signals
   on `SimEvents` (`link_changed`, `config_changed`, `objective_updated`).
5. Anything that looks like timing (ping latency, ARP's first dropped ping,
   boot delays) is **cosmetic and belongs in the UI layer**, never the core.

Why: the core must be unit-testable headless, portable if the engine changes,
and reusable for a possible web or real-container backend later.

The presentation layer talks to the core only through the `Sim` autoload
(`game/sim.gd`), which owns one `NetworkSim` instance and re-emits its events.

## Domain model (sim/devices)

- `Device` — `id`, `hostname`, `interfaces: Dictionary[String, Interface]`,
  plus `enable_secret`, `users`, `vty_lines`, `domain_name`, `has_rsa_key`.
- `Router` — adds `static_routes`, `nat_rules`, `acls`, and `ip_routing = true`.
- `Switch` — adds `vlans: Dictionary[int, String]` (VLAN 1 always exists).
  Ports are L2: `mode` (access/trunk), `access_vlan`, `trunk_allowed`.
- `Host` — a PC or server with a single NIC: `ip`, `mask`, `gateway`.
  Servers can carry `services` and `vulns` for security missions.
- `Interface` — `full_name` ("GigabitEthernet0/1"), `short_name` ("Gi0/1"),
  `admin_up`, `ip`, `mask`, `peer` (the other end, or null).
  An interface is **oper-up** only if both ends are `admin_up` and a cable exists.

Interface names are always stored in canonical full form. Normalize user input
with `net/ifname.gd` (`g0/1`, `gi0/1`, `gig0/1`, `GigabitEthernet0/1` all map
to the same port). Never compare raw user strings to interface names.

## CLI (sim/cli)

The full grammar, modes, prompts, error strings and the per-milestone command
list are in **`references/ios-cli.md`**. Read it before adding or changing any
command. Core points:

- One `CliSession` per open terminal. It holds the device, the mode stack, and
  the current interface/VLAN/line context.
- Commands are registered per mode in a `CommandRegistry` as token patterns
  with a handler `Callable`. A handler returns a `CliResult`
  (`output: String`, `ok: bool`), and mutates state only via `NetworkSim`.
- Token matching uses **unique-prefix abbreviation** (`sh ip int br`), as IOS does.
- `no <cmd>` negation is handled by the registry, not ad hoc in each handler.
- Never print IOS output by string concatenation scattered through handlers.
  `show` output comes from formatter functions in `cli/formatters.gd`, which
  are golden-tested.

## Connectivity (sim/net)

No real packets. `NetworkSim.ping(src_id, dst_ip) -> PingResult` runs a
deterministic path search over current state and returns `success`, `hops`,
and a `fail_reason` enum (`NO_LINK`, `ADMIN_DOWN`, `VLAN_MISMATCH`,
`NO_ROUTE`, `NO_GATEWAY`, `ACL_DENIED`, `WRONG_SUBNET`, …). The reason drives
mission hints, so keep it precise.

Resolution order:
1. **L1:** both interfaces have a cable and are admin-up.
2. **L2:** BFS across switches within one VLAN, honoring access VLANs and trunk
   allowed lists.
3. **L3:** host → gateway, then router hops by longest-prefix match over
   connected + static routes. Apply ACLs and NAT where configured.
4. The reply path must also resolve; asymmetric failure is a fail.

Out of scope unless the plan adds it: STP, dynamic routing protocols, IPv6,
DHCP, timing, packet loss.

## Scenarios (sim/scenario)

The JSON schema, objective types, and a full example are in
**`references/scenario-schema.md`**. Rules:

- The loader validates a scenario fully before building state and returns
  readable errors. Never let a half-built network reach the game.
- Objectives are **pure predicates over state**, re-evaluated after every
  `config_changed` or `link_changed` event. No objective polls or uses timers.
- Every new objective type gets a validator entry, an evaluator, and tests.

## Presentation layer (world/, ui/)

- Cable plugging: raycast from the camera, snap the cable end to the nearest
  free port socket, then call `Sim.connect_link(a_port, b_port)`. The 3D cable
  is a view of sim state; if the sim rejects the link, the cable doesn't stay.
- A port socket node stores `device_id` + canonical interface name, set from
  scenario data, never typed into the scene by hand.
- Terminal: interacting with a console zooms into a full-screen `ui/terminal`
  scene bound to a `CliSession`. Up/down history, Tab completion (via the
  registry), and `?` help all live in the session, not the UI.
- UI reads state only through `Sim` and reacts to its signals. No UI script
  holds its own copy of network truth.

## Conventions

- `class_name` on every reusable script. snake_case files, PascalCase classes.
- Static typing on all vars, params and returns (`var x: int`, `-> void`).
- Enums for modes and fail reasons, never string literals.
- Signals are past tense (`link_changed`, `objective_completed`).
- Treat `.tscn` files as editor-owned. Small, surgical text edits are fine;
  build anything big in code or tell the user what to wire in the editor.
  Never touch `.godot/` or `*.import` files.

## Testing

- Every sim change ships with GdUnit4 tests. A command needs three things
  tested: it parses (including abbreviations), it changes state correctly,
  and the related `show` output is right (golden strings).
- Every objective type: a passing case and each documented failing case.
- Each scenario in `res://scenarios/` gets a smoke test that loads it, applies
  the known solution, and asserts every objective passes.
- Run headless from the project root (Windows):
  `addons\gdUnit4\runtest.cmd -a res://tests`
  If that path differs in the installed GdUnit4 version, check its docs rather
  than guessing.

## Before you finish any task

1. Grep `res://sim/` for `extends Node`, `get_tree`, `Input.`, `randf`, `await`.
   Any hit is a bug.
2. Run the test suite and report results.
3. If you added a command or objective type, update the matching reference file.
