# Scenario schema

Each mission is one JSON file in `res://scenarios/`, named `<id>.json`.
`sim/scenario/loader.gd` validates the whole file before building any state.
If validation fails, it returns a list of errors with JSON paths, such as
`devices[2].interfaces[0].name: unknown interface "Gi0/9"`.

## Top level

| Key | Type | Required | Notes |
| --- | --- | --- | --- |
| `schema_version` | int | yes | Currently `1`. Bump it on breaking changes and migrate files. |
| `id` | string | yes | snake_case, matches the file name |
| `sequence` | int | yes | Position in the campaign (1, 2, 3…), unique across files. Mission select sorts by it and unlocks a mission once the previous one is done |
| `title` | string | yes | Shown in the mission HUD |
| `briefing` | string | yes | 1–4 sentences, written in the voice of the in-game boss/ticket |
| `devices` | array | yes | See Devices |
| `links` | array | yes | Cables present at start; may be empty |
| `spare_cables` | int | no | Cables the player can place; default 0 |
| `reserved_ports` | array of `"<device>:<port>"` | no | Ports no cable may use (start links included). Use them to block topology shortcuts |
| `logs` | array | M2 | Log files; each entry has `source` (device id), `file` (path), and `lines` |
| `report` | object | M2 | Report fields and optional `max_attempts`; see Logs and reports |
| `objectives` | array | yes | At least one |
| `hints` | array | no | Keyed by fail reason (see Hints) |
| `debrief` | string | no | Shown after the mission ends, via `debrief_view()`: what was fixed and how a real admin would do it |
| `solution` | array | yes | Known solution, used by the smoke test only — never shown in game |

## Devices

```json
{
  "id": "S1",
  "type": "switch",
  "model": "switch_24",
  "hostname": "S1",
  "rack": "rack_a",
  "slot": 3,
  "config": { }
}
```

- `type`: `router` | `switch` | `host` | `server`.
- `model` picks the interface list and the 3D model from a model catalog in
  `sim/devices/models.gd`, for example:
  - `router_2port`: Gi0/0–Gi0/1
  - `switch_24`: Fa0/1–Fa0/24, Gi0/1–Gi0/2
  - `pc`: Eth0
  - `server`: Eth0
- `rack` + `slot` place it in the world. Hosts use `desk` instead of `rack`/`slot`.
- `config` is the **starting** state, which is often deliberately broken:
  - Router/switch: `interfaces` (by canonical or short name), `vlans`,
    `routes`, `enable_secret`, `users`, `domain_name`, `lines`.
  - Host: `ip`, `mask`, `gateway`, and `locked` (default false; true means
    the player can't change the host's addressing).
  - Server: as host, plus `files`, `services` and `vulns` (M3; see docs/SPEC.md §7.5).
- Interface names in the file may be short form; the loader normalizes them.

## Links

```json
{ "a": "S1:Fa0/1", "b": "PC-A:Eth0", "locked": false }
```

- `locked: true` means the player can't unplug it.
- Every endpoint must exist, and each port can be used once.
- No link may use a port listed in `reserved_ports`, and `connect_link`
  rejects them during play.

## Logs and reports (M2)

A log entry has a `source` device id, a `file` path, and a `lines` array. Every
declared `(source, file)` pair must be unique across `logs`, whether or not any
report `evidence` references it, so `query_logs(source_id, file, ...)` always
identifies a single log. Each report field may include `evidence`, an array of
`{ "source", "file", "line" }` references. Every supplied pair must identify a
declared log, and `line` must be an integer from 1 through that log's line
count. Evidence may be omitted or empty; every supplied reference must resolve
to exactly one line. The loader rejects duplicate `(source, file)` pairs and
invalid evidence references before building state.

## Objectives

Every objective has `id`, `type`, `description` (player-facing), and its
type's params. All objective types are pure predicates over sim state.

| `type` | Params | Passes when |
| --- | --- | --- |
| `ping` | `from`, `to_ip`, `to_device` (optional), `via` (optional) | `NetworkSim.ping(from, to_ip).success`; if `to_device` is set, it is the last entry in `hops`; if `via` is set, that device is in `hops` |
| `no_ping` | `from`, `to_ip`, `expect_reason` (required) | ping fails **with exactly that `fail_reason`**, e.g. `ACL_DENIED` |
| `ssh` | `from`, `to_ip`, `user` | SSH preconditions met + L3 reachable (M4) |
| `config` | `device`, `path`, `equals` | a config value matches. `path` is a key (`"hostname"`) or an array of keys, with interface names normalized (`["interfaces", "Gi0/1", "mode"]`). An object `equals` matches when every key in it matches |
| `vuln_patched` | `device`, `vuln` | the vuln's patch region fully matches an `accept` pattern (M3; see docs/SPEC.md §7.5) |
| `exploit_test` | `from`, `device`, `vuln`, `expect` | the HTTP log shows the exploit working (`vulnerable`) or, after the fix, failing (`patched`) (M3; see docs/SPEC.md §7.6) |

**Isolation objectives must not be cheesable.** A bare "ping fails" check
would pass if the player unplugged a cable, shut a port or deleted a route.
So `no_ping` always names the failure the mission is teaching, and the
validator rejects a `no_ping` without `expect_reason`. A `no_ping` objective
should also be paired with a `ping` objective that has to keep working
(e.g. block Sales → Server while Accounting → Server still succeeds), so
breaking the network wholesale fails the mission.

Objectives can set `"order": n` for missions that unlock steps one at a time.
An ordered objective is locked (shown greyed, never passes) until every
objective with a lower `order` passes. By default, all objectives are
visible and can be completed in any order.

## Patch regions (M3)

Each vuln's region is a 1-based inclusive range in its starting file. A
scenario may declare at most one patch region for each `(device, file)` pair;
the loader rejects duplicate or overlapping ranges, including identical
boundaries, and reports both vuln ids and the file path before state is built.
Regions in different files are independent.

## Hints

```json
"hints": [
  { "reason": "VLAN_MISMATCH", "text": "PC-A and PC-B are plugged into different VLANs." },
  { "reason": "ADMIN_DOWN", "text": "Something is plugged in but administratively down." }
]
```

When a `ping` objective fails, the HUD can show the hint matching the
resolver's `fail_reason`. Hints are optional; reasons without one show nothing.

## Solution

A list of `{ "device": "...", "commands": [ ... ] }` and/or
`{ "link": { "a": "...", "b": "..." } }` steps. The smoke test applies these
in order, then asserts that every objective passes.

## Full example (M1)

```json
{
  "schema_version": 1,
  "id": "m1_vlan_ping",
  "sequence": 1,
  "title": "Day One: Get Them Talking",
  "briefing": "Accounting (PC-A) and Sales (PC-B) can't reach each other. The router is racked and cabled to the switch. Make PC-A ping PC-B.",
  "devices": [
    { "id": "R1", "type": "router", "model": "router_2port", "hostname": "Router", "rack": "rack_a", "slot": 1, "config": {} },
    { "id": "S1", "type": "switch", "model": "switch_24", "hostname": "Switch", "rack": "rack_a", "slot": 3,
      "config": { "vlans": { "10": "ACCOUNTING" },
                  "interfaces": { "Fa0/1": { "mode": "access", "access_vlan": 10 } } } },
    { "id": "PC-A", "type": "host", "model": "pc", "hostname": "PC-A", "desk": "desk_1",
      "config": { "ip": "192.168.10.10", "mask": "255.255.255.0", "gateway": "192.168.10.1", "locked": true } },
    { "id": "PC-B", "type": "host", "model": "pc", "hostname": "PC-B", "desk": "desk_2",
      "config": { "ip": "192.168.20.10", "mask": "255.255.255.0", "gateway": "192.168.20.1", "locked": true } }
  ],
  "links": [
    { "a": "R1:Gi0/0", "b": "S1:Gi0/1", "locked": true },
    { "a": "S1:Fa0/1", "b": "PC-A:Eth0", "locked": true }
  ],
  "spare_cables": 1,
  "reserved_ports": ["R1:Gi0/1"],
  "objectives": [
    { "id": "ping_ab", "type": "ping", "from": "PC-A", "to_ip": "192.168.20.10", "to_device": "PC-B", "via": "R1",
      "description": "PC-A can ping PC-B through the router" },
    { "id": "trunk", "type": "config", "device": "S1", "path": ["interfaces", "Gi0/1", "mode"], "equals": "trunk",
      "description": "S1 Gi0/1 is a trunk" },
    { "id": "sub10", "type": "config", "device": "R1", "path": ["interfaces", "Gi0/0.10"],
      "equals": { "dot1q_vlan": 10, "ip": "192.168.10.1", "mask": "255.255.255.0" },
      "description": "Gi0/0.10 is VLAN 10's gateway (192.168.10.1/24)" },
    { "id": "sub20", "type": "config", "device": "R1", "path": ["interfaces", "Gi0/0.20"],
      "equals": { "dot1q_vlan": 20, "ip": "192.168.20.1", "mask": "255.255.255.0" },
      "description": "Gi0/0.20 is VLAN 20's gateway (192.168.20.1/24)" },
    { "id": "parent_noip", "type": "config", "device": "R1", "path": ["interfaces", "Gi0/0", "ip"], "equals": null,
      "description": "Gi0/0 itself has no IP address" }
  ],
  "hints": [
    { "reason": "NO_LINK", "text": "PC-B isn't cabled to anything yet." },
    { "reason": "NO_GATEWAY", "text": "Hosts in different subnets need a router to reach each other." },
    { "reason": "VLAN_MISMATCH", "text": "Check which VLAN each switch port is in." }
  ],
  "solution": [
    { "link": { "a": "S1:Fa0/2", "b": "PC-B:Eth0" } },
    { "device": "S1", "commands": [
      "enable", "configure terminal",
      "vlan 20", "name SALES", "exit",
      "interface fa0/2", "switchport mode access", "switchport access vlan 20", "exit",
      "interface gi0/1", "switchport mode trunk", "end" ] },
    { "device": "R1", "commands": [
      "enable", "configure terminal",
      "interface gi0/0", "no shutdown", "exit",
      "interface gi0/0.10", "encapsulation dot1Q 10", "ip address 192.168.10.1 255.255.255.0", "exit",
      "interface gi0/0.20", "encapsulation dot1Q 20", "ip address 192.168.20.1 255.255.255.0", "end" ] }
  ]
}
```
