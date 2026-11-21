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
server `files`/`services`/`vulns` (M3), router/switch
`users`/`domain_name`/`lines` and `ssh` objectives (M4), `no_ping` (M5), plus the
`vuln_patched` and `exploit_test` objective types. Any other
unknown key is an error, which catches typos.

## Loading

`NetworkSim.load_scenario(data, file_id = "")` runs the validator and returns a
`LoadResult` (`ok`, `errors`). A bad file changes nothing. A good one replaces
the whole sim state: devices with their starting config (a router's physical
ports start shut, hostname defaults to the id), start links (`locked` defaults
to false), reserved ports, `spare_cables`, log files (read with `query_logs`) and the
player's report (filed with `submit_report`, read with `report_view`). Loading
emits no signals; the world reads `scenario_view()` (title, briefing, hints, each
device's placement and ordered physical interface list, links, reserved ports,
log descriptors `{source, file, lines}`, report fields `{id, label, kind,
options}` and `report_max_attempts()`; never objectives, report answers or
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
| `logs` | array | no | Log files; each entry has `source` (device id), `file` (path), and `lines`. See Logs and reports |
| `report` | object | no | Report `fields` and optional `max_attempts`. See Logs and reports |
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

```json
"logs": [
  { "source": "WEB1", "file": "/var/log/auth.log",
    "lines": [
      { "t": "2026-03-14T02:11:05Z", "text": "sshd[811]: Failed password for root from 203.0.113.45", "src_ip": "203.0.113.45", "geo": "NL" }
    ] }
],
"report": {
  "fields": [
    { "id": "attacker_ip", "label": "Attacker IP", "kind": "ipv4",
      "evidence": [ { "source": "WEB1", "file": "/var/log/auth.log", "line": 1 } ] },
    { "id": "attack_type", "label": "Attack type", "kind": "choice", "options": ["Brute force", "Port scan"] }
  ],
  "max_attempts": 3
}
```

**Logs.** A log entry has a `source` device id (any device in the file), a
`file` path, and a `lines` array (it may be empty). Every declared
`(source, file)` pair must be unique across `logs`, whether or not any report
`evidence` references it, so `query_logs(source_id, file, ...)` always
identifies a single log. The same path on two devices is two logs.

- `file`: an absolute path with no spaces and no trailing `/`
  (`/var/log/auth.log`), so the server shell can take it as one token. The
  shell shows a device's files as one tree, so no path may sit inside another on
  the same device: `/var/log` can't be a log when `/var/log/auth.log` is one
  (`/var/log/auth.log.1` is fine).
- Each line is an object: `text` (required, one line), `t` (optional timestamp
  text, one line; display only, the sim never reads the clock), `src_ip`
  (optional IPv4, feeds the threat map and the `src_ip` filter), `geo`
  (optional, two uppercase letters, ISO 3166 alpha-2).
- Lines are numbered from 1 in file order. `LogFilter` substring and regex
  filters test the line as the player sees it: `t`, a space, then `text`.

**Report.** `fields` is a non-empty array; `max_attempts` (integer from 1,
default 3) limits wrong submissions per field.

- `id`: snake_case, unique. `label`: non-empty string.
- `kind`: `ipv4`, `choice` or `text`. A `choice` field needs `options`, an array
  of at least two different non-empty strings; other kinds must not have them.
- `evidence` (optional, may be empty): an array of
  `{ "source", "file", "line" }` references. Every supplied pair must identify a
  declared log, and `line` must be an integer from 1 through that log's line
  count. The loader rejects invalid evidence references before building state.

**Answers.** A report field's expected answer is the `equals` of its `report`
objective (see Objectives). Every field needs exactly one such objective: a
field with none has no answer, and two for one field would disagree.

**Filing.** `NetworkSim.submit_report(field, value)` returns a `ReportResult`.
Answers match case-insensitively with surrounding whitespace trimmed and inner
runs of it collapsed (`"  brute   FORCE "` is `"Brute force"`). A `choice` value
must be one of the options (it is filed in the option's own spelling) and an
`ipv4` value an address; text must be non-empty. A value that cannot be an answer
is refused with `INVALID_VALUE` and costs nothing, as do unknown fields, a field
already solved and a field out of attempts. A right answer solves the field; a
wrong one costs an attempt. Either emits `report_submitted(field, correct)` and
re-checks the objectives. Once the mission has ended (completed or failed) every
submission is refused with `MISSION_OVER`. `report_view()` shows per field `attempts_left`,
`last_value` and `solved`, never the answers.

The validator reports each mistake once. When a log's own `source` or `file` is
invalid, evidence that matches no log is not flagged on top of it; a bad report
`kind` doesn't also flag `options`; and when the field list is malformed, or a
`report` objective's `field` matches nothing, neither the objective nor the field
it meant is flagged again.

## Objectives

Every objective has `id`, `type`, `description` (player-facing), and its
type's params. All objective types are pure predicates over sim state.

| `type` | Params | Passes when |
| --- | --- | --- |
| `ping` | `from`, `to_ip`, `to_device` (optional), `via` (optional) | `NetworkSim.ping(from, to_ip).success`; if `to_device` is set, it is the last entry in `hops`; if `via` is set, that device is in `hops` |
| `no_ping` | `from`, `to_ip`, `expect_reason` (required) | ping fails **with exactly that `fail_reason`**, e.g. `ACL_DENIED` |
| `ssh` | `from`, `to_ip`, `user` | SSH preconditions met + L3 reachable (M4) |
| `report` | `field`, `equals` | the player has filed the right answer for report field `field` (M2). `equals` must suit the field's kind: an IPv4 address, exactly one of a `choice`'s `options`, or non-empty text. At most one per field |
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

## Evaluation

`NetworkSim.objective_states()` returns one `ObjectiveState` per objective, in
file order, computed fresh from live state (empty until a scenario loads).
`ObjectiveEvaluator` re-checks everything after every `link_changed`,
`config_changed` and `report_submitted` (never polled), emits `objective_updated(id, passed)` for each
objective whose `passed` changed, in file order, then `mission_completed(id)`
once, the first time all pass. Loading signals nothing; reloading resets this.

- `ping`: a failed ping sets `fail_reason` and the matching `hint`. A ping that
  succeeds but misses a condition has `fail_reason` NONE and a `detail`:
  `reached, but <last hop> answered, not <to_device>` (checked first), or
  `reached, but not through <via>`.
- `config` values: "not set" reads as null (no `ip`, `dot1q_vlan` 0, a trunk
  that allows every VLAN, an empty host gateway), so `equals: null` passes
  exactly then. A missing interface or VLAN is null too. An object `equals`
  needs every key it names to match, and ignores the rest. `trunk_allowed`
  compares as a set.
- `order`: an objective is locked while any objective with a lower `order` has
  not passed. A locked objective is never passed and has no `fail_reason`,
  `hint` or ping result; a locked one holds back the ones above it too, so a
  step re-locks if an earlier one stops passing. No `order` means never locked.
- `report`: passes once the field is solved. Until then `detail` reads
  `3 attempts left` (`1 attempt left`). A field that runs out of attempts
  unsolved can never pass: its objective is `failed` (`detail` "out of
  attempts"), even while locked, and stays failed until the scenario reloads.
- Failing the mission: the first time any objective is `failed`, the sim fills
  `debrief_view()` (`completed()` false; each objective carries `passed` and
  `failed`) and emits `mission_failed(scenario_id, objective_id)` for the first
  failed objective in file order, once. The mission has then ended:
  `submit_report` refuses with `MISSION_OVER`, as it does after completion, and
  `mission_completed` can no longer fire. Reloading resets all of it.

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
`{ "link": { "a": "...", "b": "..." } }` steps. The smoke test
(`tests/scenario/test_scenario_smoke.gd`, replay logic in
`tests/support/scenario_runner.gd`) runs for every `*.json` in `scenarios/`
with no registration. It asserts the file loads (its `id` must equal the file
name), that at least one objective fails at the start, then applies the steps
in order through `connect_link` and CLI sessions (stopping at the first step
the sim refuses), then asserts that every objective passes and that
`mission_completed` fired once. When a later milestone adds a solution step
type, add it to `ScenarioRunner._apply_step`. The validator also checks
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
