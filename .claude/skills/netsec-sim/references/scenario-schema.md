# Scenario schema

Each mission is one JSON file in `res://scenarios/`, named `<id>.json`.
`sim/scenario/validator.gd` (`ScenarioValidator.validate(data, file_id)`)
checks the whole file before the loader builds any state. It returns every
problem at once as `<json path>: <problem>` strings, such as
`devices[1].config.interfaces["Gi0/9"]: unknown interface "GigabitEthernet0/9" for model switch_24`
(an empty list means valid). A mistake is reported once: a device with a bad
model doesn't also flag its links and objectives. JSON numbers arrive as floats,
and a whole-number float counts as an integer. Passing `file_id` checks `id`
against the file name.

Keys and objective types that belong to a later milestone are rejected with
`is not supported yet (arrives in M<n>)` until that milestone adds their rules:
`logs` and `report` (M2), server `files`/`services`/`vulns` (M3), router/switch
`users`/`domain_name`/`lines` and `ssh` objectives (M4), `no_ping` (M5), plus the
`report`, `vuln_patched` and `exploit_test` objective types. Any other
unknown key is an error, which catches typos.

## Loading

`NetworkSim.load_scenario(data, file_id = "")` runs the validator and returns a
`LoadResult` (`ok`, `errors`). A bad file changes nothing. A good one replaces
the whole sim state: devices with their starting config (a router's physical
ports start shut, hostname defaults to the id), start links (`locked` defaults
to false), reserved ports and `spare_cables`. Loading emits no signals; the
world reads `scenario_view()` (title, briefing, hints, each device's placement
and ordered physical interface list, links, reserved ports, never objectives or
`solution`) and `device_view()` afterwards.

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
- `id` is letters, digits, `-` and `_` (ports are written `<id>:<interface>`),
  unique. `hostname` is optional, one word. `type` and `model` must agree.
- `rack` + `slot` (integer from 1) place a router, switch or server in the world.
  Hosts use `desk` instead, never `rack`/`slot`. Two devices can't share a
  rack slot or a desk.
- `config` is the **starting** state, which is often deliberately broken:
  - Router: `interfaces`, `routes`, `enable_secret`. Switch: `interfaces`,
    `vlans`, `enable_secret`. (`users`, `domain_name`, `lines` arrive in M4.)
  - Host: `ip`, `mask`, `gateway`, and `locked` (default false; true means
    the player can't change the host's addressing). `ip` and `mask` come together.
  - Server: as host, plus `files`, `services` and `vulns` (M3; see docs/SPEC.md §7.5).
- Interface names in the file may be short form; the loader normalizes them.
  Two spellings of one interface are an error.

### Interface fields

`interfaces` maps a name to an object of these fields (all optional):

| Device | Field | Value |
| --- | --- | --- |
| router | `admin_up` | true / false (a router's physical ports start shut) |
| router | `ip` + `mask` | an IPv4 address and a contiguous mask, given together |
| router subinterface | `dot1q_vlan` | VLAN id 1 to 4094 (subinterfaces only) |
| switch | `admin_up` | true / false |
| switch | `mode` | `"access"` or `"trunk"` |
| switch | `access_vlan` | VLAN id 1 to 4094 |
| switch | `trunk_allowed` | non-empty list of VLAN ids, each once; leave out to allow all |

A router may start with subinterfaces (`Gi0/0.10`) of its real ports; a switch
may not. The same tables are `ScenarioFields.ROUTER_INTERFACE_FIELDS` /
`SWITCH_INTERFACE_FIELDS` / `HOST_FIELDS`.

`vlans` is `{ "<id>": "<name>" }` (a one-word name). `routes` is a list of
`{ "network", "mask", "next_hop" }`; `network` must be a network address for
`mask`.

## Links

```json
{ "a": "S1:Fa0/1", "b": "PC-A:Eth0", "locked": false }
```

- `locked: true` means the player can't unplug it.
- Every endpoint must exist, and each port can be used once. Only physical
  interfaces have sockets (not subinterfaces), and a cable joins two different devices.
- No link may use a port listed in `reserved_ports`, and `connect_link`
  rejects them during play. A port can be reserved once.

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

Objective `id`s are snake_case and unique. `ping`: `from` must be a device that
can send (not a switch), `to_ip` an IPv4 address, `via` a router.

**`config` paths.** `path` is a key or a list of keys:

| Device | Path | `equals` |
| --- | --- | --- |
| any | `["hostname"]` | one word |
| router, switch | `["interfaces", <name>]` | an object of interface fields (each may be null), or null for "doesn't exist" |
| router, switch | `["interfaces", <name>, <field>]` | that field's value, or null for "not set" |
| switch | `["vlans", <id>]` | the VLAN's name, or null for "doesn't exist" |
| host, server | `["ip"]`, `["mask"]`, `["gateway"]`, `["locked"]` | the value, or null |

`<name>` may be short form. A router path may name a subinterface that doesn't
exist yet (the player creates it). `dot1q_vlan` is for subinterfaces only.
`equals` is required; `null` is a real value.

Objectives can set `"order": n` (an integer from 1) for missions that unlock steps one at a time.
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
`reason` is a `PingResult.FailReason` name other than `NONE`, with at most one
hint per reason.

## Solution

A non-empty list of `{ "device": "...", "commands": [ ... ] }` and/or
`{ "link": { "a": "...", "b": "..." } }` steps. The smoke test applies these
in order, then asserts that every objective passes. The validator also checks
that the solution is playable: a link step can't use a reserved port or a port
that is already cabled (by a start link or an earlier step), and the link steps
can't outnumber `spare_cables`.

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
