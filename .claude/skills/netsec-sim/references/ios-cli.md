# IOS-style CLI grammar

The CLI should feel like Cisco IOS to someone studying for CCNA or Network+.
It doesn't need to be a full clone, but it should be consistent. When in doubt,
match real IOS behavior for whatever the command set covers.

## Modes

```gdscript
enum CliMode { USER_EXEC, PRIV_EXEC, GLOBAL_CONFIG, INTERFACE_CONFIG, VLAN_CONFIG, LINE_CONFIG }
```

| Mode | Prompt | Entered by | Leaves to |
| --- | --- | --- | --- |
| USER_EXEC | `R1>` | session start, `disable` | — (`exit` closes session) |
| PRIV_EXEC | `R1#` | `enable` (asks for password if `enable_secret` set) | `disable` → USER_EXEC |
| GLOBAL_CONFIG | `R1(config)#` | `configure terminal` | `exit` / `end` → PRIV_EXEC |
| INTERFACE_CONFIG | `R1(config-if)#` | `interface <name>` | `exit` → GLOBAL_CONFIG, `end` → PRIV_EXEC |
| VLAN_CONFIG | `S1(config-vlan)#` | `vlan <id>` (switches only) | same as above |
| LINE_CONFIG | `R1(config-line)#` | `line vty 0 4`, `line console 0` | same as above |

- The prompt uses the device's **current** hostname, so it updates immediately after `hostname`.
- `end` from any config mode goes to PRIV_EXEC. Ctrl+Z in the terminal UI maps to `end`.
- In a sub-mode, a GLOBAL_CONFIG command (e.g. `interface g0/2` while in
  `config-if`) switches context directly, as real IOS does.
- `do <exec command>` runs a PRIV_EXEC command from any config mode.

## Token matching

- Input is split on whitespace. Matching is case-insensitive for keywords.
- **Unique-prefix abbreviation:** each keyword token matches if the user's
  token is a prefix of exactly one keyword valid at that position.
  `conf t`, `sh ip int br`, and `int g0/1` must all work.
- Argument tokens are typed: `<interface>`, `<ipv4>`, `<mask>`, `<vlan-id 1-4094>`,
  `<word>`, `<line-range>`. Validation happens at parse time.
- `no` as the first token negates the command that follows, if that command is
  registered as negatable.
- `?` lists valid next tokens with one-line help. `sh ?` and `show ip ?` both work.
- Tab completes a unique prefix; if it's ambiguous, Tab does nothing.

## Error output

Print these exactly, so the CLI stays consistent:

| Case | Output |
| --- | --- |
| Unknown keyword or bad argument | `% Invalid input detected at '^' marker.`, preceded by a line with `^` under the first bad character |
| Prefix matches several keywords | `% Ambiguous command:  "<input>"` |
| Missing required tokens | `% Incomplete command.` |
| Valid command, wrong mode | `% Invalid input detected at '^' marker.` (as IOS does) |
| Unknown command in USER/PRIV EXEC with one word | `Translating "<word>"... % Unknown command or computer name, or unable to find computer address` |

## Command set by milestone

Only implement what the current milestone needs. Each row needs a handler,
parse tests, state tests, and (for `show`) golden output tests.

### M1 — VLAN ping (vertical slice)

| Mode | Command | Effect |
| --- | --- | --- |
| USER_EXEC | `enable` | → PRIV_EXEC |
| PRIV_EXEC | `disable` | → USER_EXEC |
| PRIV_EXEC | `configure terminal` | → GLOBAL_CONFIG |
| PRIV_EXEC | `show running-config` | config formatter |
| PRIV_EXEC | `show ip interface brief` | table: Interface, IP-Address, OK?, Method, Status, Protocol |
| PRIV_EXEC | `show vlan brief` | switches: VLAN, Name, Status, Ports |
| PRIV_EXEC | `ping <ipv4>` | runs resolver, prints `!!!!!` or `.....` + success rate line |
| GLOBAL_CONFIG | `hostname <word>` | sets hostname |
| GLOBAL_CONFIG | `interface <interface>` | → INTERFACE_CONFIG |
| GLOBAL_CONFIG | `vlan <vlan-id>` | creates VLAN, → VLAN_CONFIG |
| VLAN_CONFIG | `name <word>` | names VLAN |
| INTERFACE_CONFIG | `[no] shutdown` | admin up/down |
| INTERFACE_CONFIG | `ip address <ipv4> <mask>` / `no ip address` | routers only |
| INTERFACE_CONFIG | `switchport mode access` / `switchport mode trunk` | switches only |
| INTERFACE_CONFIG | `switchport access vlan <vlan-id>` | switches only |
| GLOBAL_CONFIG | `interface <interface>.<sub>` | routers only: creates the subinterface if needed, → INTERFACE_CONFIG |
| INTERFACE_CONFIG | `encapsulation dot1Q <vlan-id>` | subinterfaces only: sets `dot1q_vlan` (router-on-a-stick) |

Hosts don't use IOS; their terminal gets a tiny shell: `ipconfig`,
`ipconfig /set <ip> <mask> <gw>` (game-specific; refused with
`Access is denied. Network settings are managed by IT.` when the host's
scenario config sets `locked: true`), and `ping <ip>`.

### M4 — Remote access and routing (post-v1)

`enable secret <word>`, `username <word> secret <word>`, `ip domain-name <word>`,
`crypto key generate rsa`, `line vty 0 4`, `transport input ssh`,
`login local`, `ip route <net> <mask> <next-hop>`, `show ip route`,
`ssh -l <user> <ipv4>` (PRIV_EXEC). SSH succeeds only if the target has all
of: a hostname other than the default, a domain name, an RSA key, a local user,
vty lines with `transport input ssh` + `login local`, and L3 reachability.

### M5 — NAT and ACLs (post-v1)

`ip nat inside` / `ip nat outside` (INTERFACE_CONFIG),
`ip nat inside source static <ipv4> <ipv4>`,
`access-list <1-99> {permit|deny} <ipv4> <wildcard>`,
`ip access-group <1-99> {in|out}`, `show ip nat translations`,
`show access-lists`.

## Show output style

- Column-aligned plain text with fixed widths, written in `cli/formatters.gd`.
- `show running-config` lists sections in a stable order: hostname, enable
  secret (shown hashed as `5 $1$...`), users, VLANs, interfaces in
  canonical order, routes, NAT, ACLs, lines, `end`.
- Golden tests compare the full output strings. When you change a formatter,
  update the goldens deliberately and say so in your summary.
