# NetSec 3D Simulator — Spec

A first-person 3D game where the player walks a server room, cables up network
gear, and fixes broken networks and insecure servers through an IOS-style
terminal. It teaches CCNA-level networking and entry-level security by doing.

This spec says **what** the game is and how it behaves. The order of work is in
[`IMPLEMENTATION_PLAN.md`](IMPLEMENTATION_PLAN.md). Detailed CLI grammar and the
scenario JSON schema live in the project skill references, which this spec
extends:

- [`.claude/skills/netsec-sim/references/ios-cli.md`](../.claude/skills/netsec-sim/references/ios-cli.md)
- [`.claude/skills/netsec-sim/references/scenario-schema.md`](../.claude/skills/netsec-sim/references/scenario-schema.md)

Where this spec and the skill disagree on scope or ordering, this spec wins.

---

## 1. Goals and non-goals

### Goals

1. **Teach by fixing.** Every mission starts broken. The player diagnoses and
   repairs it with real-world commands and concepts (VLANs, trunks,
   router-on-a-stick, log triage, SQLi/XSS fixes).
2. **Feel authentic.** CLI commands, prompts, abbreviations and error strings
   match Cisco IOS for the commands we support.
3. **Run on weak hardware.** Target: Intel HD Graphics 4000, 2 GB RAM. Low-poly,
   stylized art.
4. **Deterministic, tested core.** All network truth lives in a pure-logic sim
   core with headless unit tests. Same state + same input = same output.
5. **Portfolio quality.** Clean architecture, CI, a playable web demo, and a
   README that explains the design.

### Non-goals (v1)

- Real packets, real timing, packet loss, or real network access. Nothing
  leaves the game.
- STP, dynamic routing (OSPF, EIGRP), IPv6, DHCP.
- Multiplayer, voice, or a level editor.
- A full IOS clone. Only the commands the missions need.
- Copying the reference game's name, branding, or assets. It is inspiration
  only.

### Working title

`netsec-3d-simulator` is the repo name. The in-game title is TBD and must not be
"Network & Cyber Security Simulator".

---

## 2. Platform and stack

| Item | Choice | Why |
| --- | --- | --- |
| Engine | Godot 4.7, Standard edition | Free, Linux-friendly, strong UI tools, web export |
| Language | GDScript, static typing everywhere | Python-like; no C# toolchain needed for web export |
| Renderer | Compatibility | Required for HD 4000-class GPUs and web export |
| Tests | GdUnit4 under `res://tests/` | Headless runner for CI |
| Scenario format | JSON (built-in `JSON` class) | No addon needed |
| Exports | Windows, Linux, Web | Web build is the hosted demo |
| CI | GitHub Actions, Godot headless on Linux | Runs tests + purity check on every push |

### Performance budget (target hardware)

- 60 fps at 1280×720, 30 fps minimum at 1920×1080.
- Under 300 draw calls and 200k visible triangles in the server room.
- Under 1.5 GB RAM in use.
- No real-time shadows by default. Baked lighting or a single directional light.

---

## 3. Architecture

Three parts. Dependencies point inward only.

```mermaid
flowchart LR
  subgraph Presentation["Presentation (Godot nodes)"]
    W[world/ — 3D room, racks, cables, player]
    U[ui/ — terminal, log viewer, threat map, HUD]
  end
  G[game/ — Sim autoload, progress, settings]
  subgraph Core["sim/ — pure logic, no Nodes"]
    C[core/ NetworkSim facade + SimEvents]
    D[devices/]
    L[cli/]
    N[net/]
    S[scenario/]
    LG[logs/]
    WB[web/]
  end
  J[(scenarios/*.json)]
  W --> G
  U --> G
  G --> C
  C --> D & L & N & S & LG & WB
  S --> J
```

### 3.1 Sim core rules (`res://sim/`)

These are hard rules. CI fails if any are broken.

1. Classes extend `RefCounted` (or `Resource` for saved data). Never `Node`.
2. No `get_tree()`, `Input`, `OS.get_ticks_*`, `Time`, timers, `await`,
   `randf()`/`randi()`, or autoload references.
3. No imports from `world/`, `ui/` or `game/`.
4. All state changes go through `NetworkSim` methods, which emit typed signals
   on `SimEvents`.
5. Anything that looks like timing (ping delays, boot time, typing effects) is
   cosmetic and lives in the UI layer.

### 3.2 The `Sim` autoload (`res://game/sim.gd`)

- Owns exactly one `NetworkSim`.
- Loads a scenario, re-emits core signals, and exposes the core's public API to
  the presentation layer.
- Owns file access: it reads `res://scenarios/*.json`, so the core never does
  IO. `Sim.scenario_catalog()` returns the valid scenarios'
  `ScenarioSummary` list (via `summarize_scenario`) sorted by `sequence`,
  for mission select. Invalid files are skipped and logged.
- The only path from `world/` and `ui/` into the core.

### 3.3 `NetworkSim` public API (v1)

| Method | Returns | Milestone |
| --- | --- | --- |
| `load_scenario(data: Dictionary)` | `LoadResult` (`ok`, `errors: Array[String]`) | M1 |
| `summarize_scenario(data: Dictionary)` | `ScenarioSummary` (read-only): `id`, `title`, `sequence`, or `null` plus errors if the file is invalid. Doesn't change sim state | M2 |
| `scenario_view()` | `ScenarioView` (read-only, static scenario data): title, briefing, hints; every device's id, type, model, hostname, `rack`+`slot` or `desk`, and its **ordered canonical interface list** (socket order); links (`a`, `b`, `locked`); `reserved_ports`; M2: log descriptors (`source`, `file`, line count) and report fields (`id`, `label`, `kind`, `options`, `max_attempts`) | M1 (M2 adds logs/report) |
| `device_view(id: String)` | `DeviceView` (read-only snapshot) or `null`: sanitized viewable config (`hostname`, router/switch VLANs/routes/NAT/ACLs, host/server `ip`/`mask`/`gateway`/`locked`, server `services` metadata without `files` or `vulns`) plus each canonical interface's `admin_up`, `oper_up`, `ip`, `mask`, L2/dot1Q settings, and peer port (`<device>:<interface>` or `null`). Subinterface peers are `null`; their `oper_up` follows the parent. Server `files`, `vulns`, `accept` regexes, fixtures, and `exploit` metadata are excluded | M1 |
| `open_session(device_id: String)` | `CliSession` | M1 |
| `connect_link(a: String, b: String)` | `LinkResult` (`ok`, `reason`); uses one spare cable | M1 |
| `spare_cables()` | `int` (spare cables left) | M1 |
| `disconnect_link(port: String)` | `LinkResult` | M1 |
| `ping(src_id: String, dst_ip: String)` | `PingResult` | M1 |
| `objective_states()` | `Array[ObjectiveState]` (read-only): `id`, `type`, `description`, `order`, `locked`, `passed`, `failed` (can no longer pass), `fail_reason` (`ping` objectives; `NONE` otherwise), `hint` (the scenario hint for that reason, or `""`), `detail` (short status such as "reached, but not through R1" or "2 attempts left") | M1 |
| `debrief_view()` | `DebriefView` (read-only), or `null` until `mission_completed` or `mission_failed` has fired: the scenario's `debrief` text, each objective's result, M2 report answers with their `evidence` log lines, M3 each vuln's starting vs current region text | M1 (M2/M3 add their parts) |
| `query_logs(source_id: String, file: String, filter: LogFilter)` | `Array[LogLine]` | M2 |
| `submit_report(field: String, value: String)` | `ReportResult` | M2 |
| `report_view()` | `ReportView` (read-only, live): per field, attempts left, last value, solved or not | M2 |
| `read_file(device_id: String, path: String)` | `String` or `null` | M3 |
| `patch_views(device_id: String, path: String)` | `Array[PatchView]` (read-only): `vuln_id`, current region line range, `hint` | M3 |
| `write_patch(device_id: String, vuln_id: String, text: String)` | `bool` | M3 |
| `http_request(src_id: String, url: String)` | `HttpResult` | M3 |

**View rule.** Everything the presentation layer needs comes from a
read-only view on `Sim`: `scenario_view` for static scenario data,
`device_view` / `report_view` / `objective_states` / `patch_views` for live
state. Views are fresh copies with getters only, so changing one can't
touch sim state. The world initializes port LEDs and cable visuals from the
current `device_view()` snapshots after loading, then applies later signals;
it never relies on having observed load-time `interface_state_changed` events. The world and UI never read scenario JSON or import
`sim/` scripts (such as `models.gd`) directly, and all changes go through
the methods above or a `CliSession`. Answers and hidden server metadata (`report` objective values,
`solution`, server `files` and `vulns`, `accept` patterns, fixtures, and `exploit` metadata) are never in a `DeviceView`, `ScenarioView`, or `ReportView` during play (source files are read through `read_file` and region metadata through `patch_views`). The one
exception is `debrief_view()`, which returns `null` until the mission has
ended (completed or failed); `solution` and `accept` patterns are never
exposed at all.

Ports are addressed as `"<device_id>:<canonical interface name>"`, for example
`"S1:FastEthernet0/1"`. Short names are normalized by `net/ifname.gd`.

### 3.4 Signals (`SimEvents`)

| Signal | Payload | Fired when |
| --- | --- | --- |
| `link_changed` | `a_port, b_port, connected: bool` | A cable is connected or removed |
| `interface_state_changed` | `port, oper_up: bool` | An interface's oper state flips |
| `config_changed` | `device_id` | Any CLI command changes device state |
| `patch_applied` | `device_id, vuln_id` | The player saves a vuln's patch region (M3) |
| `http_requested` | `src_id, vuln_id, outcome` | A `curl` request finishes (M3) |
| `report_submitted` | `field, correct: bool` | The player files a report field (M2) |
| `objective_updated` | `objective_id, passed: bool` | An objective's result changes |
| `mission_completed` | `scenario_id` | All objectives pass |
| `mission_failed` | `scenario_id, objective_id` | An objective can no longer pass (M2: a report field is out of attempts) |

Objectives are re-evaluated after every `link_changed`, `config_changed`,
`report_submitted`, `patch_applied` and `http_requested`. They never poll.

---

## 4. Domain model (`sim/devices`)

As defined in the skill, summarized here.

| Class | Key state |
| --- | --- |
| `Device` | `id`, `hostname`, `interfaces: Dictionary[String, Interface]`, `enable_secret`, `users`, `vty_lines`, `domain_name`, `has_rsa_key` |
| `Router` | + `static_routes`, `nat_rules`, `acls`, `ip_routing = true` |
| `Switch` | + `vlans: Dictionary[int, String]` (VLAN 1 always exists). Ports have `mode`, `access_vlan`, `trunk_allowed` |
| `Host` | Single NIC: `ip`, `mask`, `gateway` |
| `Server` | A `Host` + `services`, `files`, `vulns` (M3) |
| `Interface` | `full_name`, `short_name`, `admin_up`, `ip`, `mask`, `peer` |
| Subinterface | An `Interface` + `parent`, `dot1q_vlan`; no `peer` |

- Physical interface **oper-up** = both ends `admin_up` and a cable exists.
- Subinterface **oper-up** = parent oper-up and itself `admin_up`.
- Host and server NICs are `admin_up` by default. Router interfaces start
  shut down, as on real IOS. Switch ports start up, in access mode, VLAN 1.
- A subinterface is created `admin_up`, as on real IOS, so its state follows
  its parent. Only the physical port needs `no shutdown`.

### Device model catalog (`sim/devices/models.gd`)

| Model | Type | Interfaces | 3D scene |
| --- | --- | --- | --- |
| `router_2port` | router | Gi0/0–Gi0/1 | `world/devices/router_2port.tscn` |
| `switch_24` | switch | Fa0/1–Fa0/24, Gi0/1–Gi0/2 | `world/devices/switch_24.tscn` |
| `pc` | host | Eth0 | `world/devices/pc.tscn` |
| `server` | server | Eth0 | `world/devices/server_1u.tscn` |

---

## 5. Terminal and CLI (`sim/cli`)

Full grammar, prompts and error strings: `references/ios-cli.md`. Key behavior:

- One `CliSession` per open terminal: device, mode stack, current
  interface/VLAN/line context, and command history.
- Unique-prefix abbreviation (`sh ip int br`, `conf t`).
- `?` help, Tab completion, `no` negation, and `do` from config modes, all
  handled by the `CommandRegistry`, not individual handlers.
- `show` output comes only from `cli/formatters.gd`, which is golden-tested.
- Ctrl+Z maps to `end`. Up/Down walks history.
- `CliResult` carries `output`, `ok`, and an `action: ShellAction` enum
  (`NONE`, `CLOSE_SESSION`, `OPEN_EDITOR`) with an `action_arg` (for
  `OPEN_EDITOR`, the device id and file path). The core only returns the action; the
  terminal UI reads it and opens the editor or closes the terminal, so the
  core never references a UI class.

### 5.1 Shells per device type

| Device | Shell | Commands (v1) |
| --- | --- | --- |
| Router, switch | IOS-style | Per milestone, see `ios-cli.md` |
| PC (`host`) | Mini Windows-style shell | `ipconfig`, `ipconfig /set <ip> <mask> <gw>` (refused with `Access is denied. Network settings are managed by IT.` when the scenario sets the host's `locked: true`), `ping <ip>`, `curl <url>` (M3), `help` |
| Server | Mini Linux-style shell | `ls [path]`, `cat <file>`, `grep [-i] <pattern> <file>`, `tail [-n N] <file>`, `edit <file>` (M3), `service <name> status`, `help` |

The host and server shells are separate small command registries that share
the same help system as the IOS CLI. Their tokenizer also accepts a
double-quoted argument (`curl "http://10.0.10.5/login.php?user=' OR '1'='1"`),
which can hold spaces and single quotes. The IOS CLI keeps plain whitespace
splitting.

### 5.2 Ping output

- IOS devices: real IOS format (`Type escape sequence to abort.`, `!!!!!` or
  `.....`, `Success rate is N percent (x/5)`). Round-trip numbers are fixed
  values derived from hop count, so output is deterministic.
- PC: Windows-style `Reply from ...` / `Request timed out.` lines.
- The UI reveals ping characters one at a time for feel. The result is already
  decided by the core before the animation starts.

---

## 6. Connectivity (`sim/net`)

No real packets. `NetworkSim.ping(src_id, dst_ip)` runs a deterministic path
search and returns:

```gdscript
class_name PingResult extends RefCounted
var success: bool
var hops: Array[String]        # device ids, in order, forward path
var fail_reason: FailReason    # NONE when success
var fail_at: String            # device id or port where it failed, "" if none
```

### 6.1 Fail reasons

| Reason | Meaning | Milestone |
| --- | --- | --- |
| `NONE` | Success | M1 |
| `NO_IP` | Source has no IP address | M1 |
| `NO_LINK` | A needed cable is missing | M1 |
| `ADMIN_DOWN` | An interface on the path is shut down | M1 |
| `VLAN_MISMATCH` | L2 path exists but not in a shared VLAN / trunk doesn't carry it | M1 |
| `WRONG_SUBNET` | Host gateway is outside its own subnet | M1 |
| `NO_GATEWAY` | Off-subnet destination and no gateway set | M1 |
| `NO_ROUTE` | A router has no matching route | M1 |
| `HOST_UNREACHABLE` | Next hop or destination IP is not owned by any reachable device | M1 |
| `ACL_DENIED` | An ACL dropped the packet | M5 |

The reason must be precise: mission hints are keyed on it.

### 6.2 Resolution order

As in the skill: L1 oper-up → next-hop decision at each L3 device → L2 BFS
within one VLAN (access VLANs, trunk allowed lists, dot1Q subinterfaces) →
router pipeline (inbound ACL, NAT outside→inside, route lookup, NAT
inside→outside, outbound ACL) → the reply path must also resolve.

### 6.3 Required behavior

- Two hosts in the same VLAN and subnet ping each other with no router.
- Router-on-a-stick across a trunk works (M1 mission).
- A router pings from the IP of its egress interface.
- When several reasons apply, report the **first** one hit in resolution order,
  walking the forward path from the source.

---

## 7. Missions and scenarios (`sim/scenario`)

Each mission is one JSON file in `res://scenarios/<id>.json`. Base schema:
`references/scenario-schema.md`. The loader validates the whole file and
returns errors with JSON paths before any state is built.

### 7.1 v1 missions

| # | Id | Title (draft) | Teaches | New systems |
| --- | --- | --- | --- | --- |
| 1 | `m1_vlan_ping` | Day One: Get Them Talking | VLANs, access/trunk ports, router-on-a-stick | Sim core, IOS CLI, 3D room, cabling |
| 2 | `m2_log_triage` | Who Knocked? | Reading auth/web logs, spotting brute force, incident reporting | Logs, log viewer, report form, threat map |
| 3 | `m3_web_patch` | Patch Tuesday | SQL injection and reflected XSS, and how to fix them | Server files, code editor, simulated HTTP |

After v1: `m4_remote_access` (SSH + static routes) and `m5_nat_acl`
(static NAT + ACLs). Their CLI commands are already listed in `ios-cli.md`.

### 7.2 Mission flow

1. **Main menu** → mission select (locked until the previous mission is done).
2. **Briefing** card with the ticket text.
3. **Play**: walk, cable, configure. The HUD lists objectives with live
   pass/fail ticks. An objective with `"order": n` is **locked** until every
   objective with a lower `order` passes. A locked objective shows as a
   greyed "next step" line and never counts as passed. Objectives with no
   `order` are always unlocked.
4. **Hints**: when a `ping` objective fails, the HUD can show the hint matching
   its `fail_reason`. A hint appears only after the player presses the hint
   key, so it never spoils the puzzle by default.
5. **Debrief**: when all objectives pass, show a summary of what was fixed
   and the commands a real admin would use. Progress is saved.
6. **Failed debrief**: when `mission_failed` fires, play stops and a
   failed-mission card shows which objective failed, the correct answers,
   and where the evidence was (e.g. the log lines that named the attacker),
   all read from `Sim.debrief_view()`.
   It offers **Retry** (reload the scenario) and **Main menu**. Progress is
   not saved.

### 7.3 Objective types

| Type | Params | Passes when | Milestone |
| --- | --- | --- | --- |
| `ping` | `from`, `to_ip`, `to_device` (optional), `via` (optional) | Ping succeeds; if `to_device` is set, that device owns `to_ip` and is the last hop; if `via` is set, that device is on the forward path | M1 |
| `config` | `device`, `path`, `equals` | Config value matches. `path` is a key (`"hostname"`) or an array of keys; interface names in it are normalized (`["interfaces", "Gi0/0.10"]`). If `equals` is an object, every key in it must match (e.g. `{"dot1q_vlan": 10, "ip": "192.168.10.1", "mask": "255.255.255.0"}`) | M1 |
| `report` | `field`, `equals` | The player's filed value for `field` matches (case-insensitive, trimmed) | M2 |
| `vuln_patched` | `device`, `vuln` | The vuln's patch region matches one of its `accept` patterns (SPEC §7.5) | M3 |
| `exploit_test` | `from`, `device`, `vuln`, `expect` (`vulnerable` \| `patched`) | Matches log entries with this `from`, `device` (the server that answered) and `vuln`. `vulnerable`: one such entry got the vulnerable response. `patched`: the vuln is patched now, and the latest such entry got the patched response **and** has the vuln's current `patch_rev` (so evidence from before the latest save doesn't count) | M3 |
| `no_ping` | `from`, `to_ip`, `expect_reason` | Ping fails with exactly that reason | M5 |
| `ssh` | `from`, `to_ip`, `user` | SSH preconditions + L3 reachability | M4 |

**Teaching missions check the intended config, not just the outcome.**
Each round of review found another way to make a lone `ping` objective pass
without the skill being taught (re-addressing hosts, odd masks, cabling
around the switch). So a mission pairs its outcome objective with `config`
objectives for the setup it teaches, and locks host addressing it doesn't
teach. M1 requires the S1 Gi0/1 trunk, both R1 dot1Q subinterfaces with
their exact tag, gateway IP and mask, and no IP on the parent Gi0/0, and sets both PCs to
`locked: true`.

**Anti-cheese rules.** Any "it stops working" objective must name what it
expects (`no_ping.expect_reason`) and be paired with a "still works"
objective. A `ping` objective names its target with `to_device`, so giving
`to_ip` to some other device (for example a router subinterface) does not
pass. A `ping` objective that teaches routing also sets `via` to the router,
so re-addressing both hosts into one subnet and VLAN (a pure L2 path) does
not pass. A scenario also blocks topology shortcuts with `reserved_ports`
(ports no cable may use): M1 reserves `R1:Gi0/1`, so PC-B can't be cabled
straight to the router and the only way across is the trunk and
subinterfaces. When `via` is set and the ping succeeds without it, the HUD says
"reached, but not through <via>". In M3, the player can edit only each
vuln's patch region, and the region must fully match an accepted fix, so
deleting code or hiding the old query does not pass. `exploit_test`
objectives make the player prove the attack before the fix and its failure
after.

### 7.4 Schema additions for M2 (logs and reports)

```json
"logs": [
  {
    "source": "WEB1",
    "file": "/var/log/auth.log",
    "lines": [
      { "t": "2026-03-14T02:11:05Z", "text": "sshd[811]: Failed password for root from 203.0.113.45 port 51122 ssh2", "src_ip": "203.0.113.45", "geo": "NL" }
    ]
  }
],
"report": {
  "fields": [
    { "id": "attacker_ip", "label": "Attacker IP", "kind": "ipv4",
      "evidence": [ { "source": "WEB1", "file": "/var/log/auth.log", "line": 214 } ] },
    { "id": "attack_type", "label": "Attack type", "kind": "choice",
      "options": ["Brute force", "SQL injection", "Port scan", "Phishing"] },
    { "id": "compromised_user", "label": "Compromised account", "kind": "text" }
  ],
  "max_attempts": 3
}
```

- Log lines are static data with timestamps written in the file. The core
  never reads the clock.
- `src_ip` and `geo` (ISO 3166 alpha-2) are optional. They feed the threat map.
- Lines are shown in file order. `t` is display-only.
- `report.max_attempts` (default 3) limits wrong submissions per field. When a
  field runs out, its objective fails for good, the sim emits
  `mission_failed`, and the failed debrief (§7.2 step 6) shows the answers
  and offers Retry.
- Validator: every `report` objective's `field` must exist in `report.fields`;
  a `choice` objective's `equals` must be one of its `options`; each log
  `source` must be a device id; every declared `(source, file)` log pair must
  be unique across `logs` (whether or not any `evidence` references it); every
  supplied report evidence `(source, file)` pair must identify a declared log,
  and `line` must be an integer from 1 through that log's line count. Evidence
  may be omitted or empty, but every supplied reference must resolve to
  exactly one log line.

### 7.5 Schema additions for M3 (files, services, vulns)

Regex blacklists over a whole file can always be dodged (split keywords,
dummy statements, unused code). So M3 uses **guided patching**: each vuln
marks a small patch region, the rest of the file is read-only, and the
region must **fully match** one of a few accepted fixes.

```json
{
  "id": "WEB1", "type": "server", "model": "server", "hostname": "web1",
  "rack": "rack_a", "slot": 5,
  "config": {
    "ip": "10.0.10.5", "mask": "255.255.255.0", "gateway": "10.0.10.1",
    "files": {
      "/var/www/login.php": "<?php\nfunction check_login($db) {\n  $user = $_POST['user'];\n  $q = \"SELECT * FROM users WHERE name = '\" . $user . \"'\";\n  $res = $db->query($q);\n  return $res->fetch();\n}\n"
    },
    "services": [ { "id": "http", "port": 80, "root": "/var/www" } ],
    "vulns": [
      { "id": "sqli_login", "kind": "sqli", "service": "http", "route": "/login.php",
        "region": { "file": "/var/www/login.php", "first_line": 4, "last_line": 5 },
        "accept": [
          "\\$res=\\$db->prepare\\(([\"'])SELECT \\* FROM users WHERE name = \\?\\1\\);\\$res->execute\\((\\[\\$user\\]|array\\(\\$user\\))\\);"
        ],
        "accept_fixtures": [
          "$res = $db->prepare(\"SELECT * FROM users WHERE name = ?\");\n$res->execute([$user]);",
          "$res = $db->prepare( 'SELECT * FROM users WHERE name = ?' ); // safe\n$res->execute(array($user));"
        ],
        "reject_fixtures": [
          "$q = \"SELECT * FROM users WHERE name = '$user'\";\n$res = $db->query($q);",
          "$q = \"SE\" . \"LECT * FROM users WHERE name = '\" . $user . \"'\";\n$res = $db->prepare($q);\n$d = $db->prepare(\"?\");\n$d->execute([$user]);",
          ""
        ],
        "hint": "Use a prepared statement with a ? placeholder, then pass $user to execute().",
        "exploit": { "param": "user", "payload": "' OR '1'='1",
                     "vulnerable_body": "Welcome, admin!", "patched_body": "Login failed." } }
    ]
  }
}
```

- `files` holds short source files (under 60 lines each). Code is PHP-flavored
  pseudo-code, since PHP is the classic teaching example for SQLi and XSS.
- `region` is a 1-based, inclusive line range in the **starting** file. The
  sim stores the file as read-only prefix + editable region + read-only
  suffix, so regions survive edits that change the line count. A scenario may
  declare at most one patch region for each `(device, file)` pair. The loader
  rejects duplicate or overlapping regions (including identical boundaries)
  and reports both vuln ids and the file path before building state. Regions
  in different files are independent.
- `NetworkSim.write_patch(device, vuln, text)` replaces only the region text
  and bumps that vuln's `patch_rev` counter.
- The code editor gets the file from `read_file` and the vuln ids, region
  line ranges and hints from `patch_views(device, path)`. It shows the whole
  file but locks lines outside the regions.
- **Normalization** before matching: strip comments (`//`, `#`, `/* */`)
  outside string literals, then remove all whitespace outside string
  literals. Whitespace inside strings is kept.
- The region is patched when its normalized text **fully matches** (anchored
  at both ends) at least one `accept` regex. Anything else is unpatched:
  extra statements, split keywords, deleted code, and an empty region all
  fail. Regexes use Godot's `RegEx` (deterministic, `RefCounted`).
- When a save doesn't match, the editor shows the vuln's `hint`, so a
  correct but unlisted fix gets steered to the expected form rather than
  failing silently.
- The validator compiles every regex and rejects the scenario if: the
  starting region already matches `accept`; any `accept_fixtures` entry is
  rejected; or any `reject_fixtures` entry is accepted. Every bypass found
  in playtesting becomes a new reject fixture.
- The smoke test's `solution` gains two step types:
  `{ "device": "WEB1", "patch": { "vuln": "sqli_login", "text": "..." } }` and
  `{ "device": "PC-1", "http": "http://10.0.10.5/login.php?user=..." }`.

### 7.6 Simulated HTTP (M3)

`NetworkSim.http_request(src_id, url)` lets the player test an exploit from a
PC with `curl`:

1. Parse the URL (`http://<ipv4>[:port]/<route>?<query>`). Query values are
   URL-decoded (`%27` → `'`, `+` → space) before any comparison, so a quoted
   raw payload and a percent-encoded one behave the same.
2. Resolve L3 reachability with the ping resolver. On failure, print a
   curl-style error, for example `curl: (7) Failed to connect to 10.0.10.5 port 80`.
3. Find the service on that port. None → connection refused.
4. If the route matches a vuln and the decoded `param` value equals its
   exploit payload (trimmed), return `vulnerable_body` or `patched_body`
   based on the vuln's state.
5. Otherwise return a fixed `200 OK` page for the route.
6. Append an entry to the sim's **HTTP log** (`src_id`, `dst_device`,
   `vuln_id` or `""`, that vuln's `patch_rev` at request time, `outcome`:
   `VULNERABLE` | `PATCHED` | `NORMAL` | `ERROR`) and emit `http_requested`.

The HTTP log is ordinary sim state, so `exploit_test` objectives stay pure
predicates. M3 orders them per vuln with `order`: (1) show the exploit works,
(2) patch, (3) show the exploit now fails.

No real HTTP is sent. It is a lookup over sim state.

---

## 8. Presentation layer

### 8.1 World (`res://world/`)

- **Room:** one low-poly server room with 2 racks, 2 desks, and a wall
  monitor. Built from free assets (Kenney, Quaternius, Poly Haven textures)
  plus simple Blender racks/switches.
- **Spawning:** `world/room_builder.gd` reads the loaded scenario through
  `Sim` and instantiates each device's model scene at its `rack`/`slot` or
  `desk` marker (`Marker3D` nodes in the room scene).
- **Port sockets:** each model scene has ordered socket markers. The spawner
  assigns `device_id` and canonical interface names from the device's
  ordered interface list in `Sim.scenario_view()`, in order. Names are never
  typed into scenes by hand, and the world never reads `models.gd`.
- **Port LEDs:** off (no cable), amber (cable, not oper-up), green (oper-up).
  They react to `interface_state_changed`.
- **Player:** `CharacterBody3D` with WASD + mouse look, crouch, and an
  interact raycast. A crosshair prompt names the target ("Fa0/2 — S1",
  "Open console").

### 8.2 Cabling

1. Look at a free socket and press interact to pick up a cable end. The
   world checks `Sim.spare_cables() > 0` first; the count itself lives in
   the core.
2. Look at a second free socket and press interact. The world calls
   `Sim.connect_link(a, b)`.
3. If the sim accepts, a cable mesh is drawn between the sockets with a
   simple sag curve. If it rejects (port in use, same device, port
   reserved), the cable end returns and a toast shows the reason.
   Reserved ports (scenario `reserved_ports`) show a dust cap and a
   "reserved" label, so the player can see them before trying.
4. Interact on an unlocked plugged cable unplugs it and returns it to the
   spare count. Locked cables can't be unplugged: `disconnect_link`
   rejects them in the core, so no caller can change fixed topology.
5. Press cancel to drop a held cable end.

The 3D cable is only a view of sim state. On `link_changed` the world adds
or removes cable meshes to match.

### 8.3 UI (`res://ui/`)

| Screen | Contents | Milestone |
| --- | --- | --- |
| Terminal | Full-screen monospace console bound to a `CliSession`. Esc closes. Shows the device hostname in the title bar | M1 |
| Mission HUD | Objective list with ticks, spare cable count, hint key prompt | M1 |
| Briefing / debrief | Ticket-style cards | M1 |
| Main menu + mission select | Locked/unlocked missions, settings | M1 (single mission), M2 (select) |
| Log viewer | Opened from the SOC desk monitor. File list, scrolling view, text filter, highlight on match | M2 |
| Report form | Fields from `report.fields`; shows remaining attempts | M2 |
| Threat map | 2D world map; arcs from `geo` countries for log lines with `src_ip`; click an arc to jump to the line | M2 (should-have) |
| Code editor | `CodeEdit` with line numbers and basic PHP highlighting; lines outside the patch region are locked; Save calls `Sim.write_patch` and shows the hint if the patch isn't accepted | M3 |

UI scripts read state only through `Sim` and react to its signals. No UI
script stores its own copy of network truth.

### 8.4 Input map

| Action | Default |
| --- | --- |
| Move | WASD |
| Look | Mouse |
| Interact | E / left click |
| Cancel / close | Esc |
| Hint | H |
| Objectives toggle | Tab (outside terminal) |
| Crouch | Ctrl |

### 8.5 Saving

`game/progress.gd` saves completed mission ids and settings to
`user://progress.json`. Mid-mission state is not saved in v1. Leaving a
mission restarts it.

---

## 9. Testing

- **Unit (GdUnit4, headless):** everything under `sim/`. Suites mirror the
  folder layout under `res://tests/`.
- **CLI commands:** each one is tested for parsing (including
  abbreviations), state change, and `show` output against golden strings.
- **Connectivity:** same-subnet no-router; router-on-a-stick; each M1 fail
  reason; reply-path failure; first-reason-wins ordering.
- **Objectives:** a passing case and each documented failing case per type.
- **Scenarios:** a smoke test per file: load, apply `solution`, assert all
  objectives pass. Plus: the unsolved starting state has at least one
  objective failing.
- **Purity check:** `tools/check_sim_purity.sh` scans `sim/` and fails CI
  on any hit for every rule in §3.1:
  - Base classes: each script's `extends` must be `RefCounted`,
    `Resource`, nothing (Godot's default `RefCounted`), or a `class_name` /
    path defined under `sim/` whose chain ends in those. Any other base
    (`Node`, `Control`, `CanvasLayer`, a custom Node subclass) fails.
  - Scene tree: `get_tree`, `get_node`, `$` node paths, `/root/`.
  - Input, time and randomness: `Input.`, `Time.`, `OS.get_ticks`, `Timer`,
    `create_timer`, `await`, `randf`, `randi`, `RandomNumberGenerator`.
  - Dependency direction: any `res://world/`, `res://ui/` or `res://game/`
    path (`preload`, `load`, `extends`).
  - Autoloads: `Engine.get_singleton`, plus `\b<Name>\.` for every
    autoload name the script reads from the `[autoload]` section of
    `project.godot`.
- **Manual playtest checklist** per mission, kept in
  `docs/playtest/<mission>.md`.

Run tests:

- Linux/macOS: `addons/gdUnit4/runtest.sh -a res://tests`
- Windows: `addons\gdUnit4\runtest.cmd -a res://tests`

(Check the installed GdUnit4 version's docs if the path differs.)

---

## 10. Future work (after v1)

- **M4 Remote access & routing:** SSH setup, static routes, `show ip route`.
- **M5 NAT & ACLs:** static NAT, standard ACLs, `no_ping` objectives. Retrofit
  M2 with an optional "block the attacker with an ACL" bonus objective.
- **Real backend (stretch):** a `NetworkBackend` interface so a terminal can
  attach to real FRRouting or VyOS containers in a homelab instead of the sim.
  The core stays the default backend.
- More missions: DHCP starvation, ARP spoofing, firewall rules, phishing
  triage.

---

## 11. Open questions

- Final game title and art direction (colors, UI theme).
- Whether the threat map ships in v1 or slides to v1.1.
- Hosting for the web demo (itch.io vs GitHub Pages).
- Whether hints cost score, or are free.
