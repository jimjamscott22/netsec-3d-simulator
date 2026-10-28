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
| INTERFACE_CONFIG | `R1(config-if)#` (`R1(config-subif)#` for a subinterface) | `interface <name>` | `exit` → GLOBAL_CONFIG, `end` → PRIV_EXEC |
| VLAN_CONFIG | `S1(config-vlan)#` | `vlan <id>` (switches only) | same as above |
| LINE_CONFIG | `R1(config-line)#` | `line vty 0 4`, `line console 0` | same as above |

- The prompt uses the device's **current** hostname, so it updates immediately after `hostname`.
- `end` from any config mode goes to PRIV_EXEC. Ctrl+Z in the terminal UI maps to `end`.
- In a sub-mode, a GLOBAL_CONFIG command (e.g. `interface g0/2` while in
  `config-if`) switches context directly, as real IOS does.
- `do <exec command>` runs a PRIV_EXEC command from any config mode.

`CliSession` (`cli/cli_session.gd`) owns this: `submit(line)`, `prompt()`,
`ctrl_z()`, `help(line)`, `complete(line)`, `history()` / `history_prev()` /
`history_next()`. It is the `ctx` passed to command handlers, which call
`enter_interface` / `enter_vlan` / `enter_line` to enter a sub-mode (from
another sub-mode this replaces it instead of nesting). `CliSession.register_core`
registers `enable`, `disable`, `configure terminal`, `exit`, `end` and the
sub-mode fallbacks.

- `enable` with an `enable_secret` set shows the `Password:` prompt
  (`is_password_prompt()` tells the UI to mask input). A wrong password
  re-prompts; the third wrong one prints `% Bad secrets` and stays in USER_EXEC.
  Passwords never enter the history. `enable` in PRIV_EXEC is a no-op.
- `exit` in USER/PRIV EXEC returns `ShellAction.CLOSE_SESSION`. `end` and
  Ctrl+Z (config modes only) go straight to PRIV_EXEC.
- History keeps the last 100 non-blank lines, skips consecutive duplicates,
  and includes lines that failed.

## Token matching

- Input is split on whitespace. Matching is case-insensitive for keywords.
- **Unique-prefix abbreviation:** each keyword token matches if the user's
  token is a prefix of exactly one keyword valid at that position.
  `conf t`, `sh ip int br`, and `int g0/1` must all work.
- Argument tokens are typed: `<interface>`, `<ipv4>`, `<mask>`, `<vlan-id 1-4094>`,
  `<word>`, `<line-range>`. Validation happens at parse time.
  `<line-range>` takes two words (`line vty 0 4` → first 0, last 4, both 0-15,
  last >= first); the other types take one. Typed args live in `cli/cli_arg.gd`
  and the line splitter in `cli/cli_tokenizer.gd`.
- `no` as the first token negates the command that follows, if that command is
  registered as negatable.
- `?` lists valid next tokens with one-line help. `sh ?` and `show ip ?` both work.
- Tab completes a unique prefix; if it's ambiguous, Tab does nothing.

`CommandRegistry` (`cli/command_registry.gd`) implements this. Patterns are
strings (`"ip address <ipv4> <mask>"`); handlers are
`func(ctx, args: Array, negated: bool) -> CliResult`. Details worth knowing:

- A negatable command (`register(..., negatable = true)`) also accepts
  `no <pattern>`, and for that form its trailing arguments are optional
  (`no ip address` and `no ip address 10.0.0.1 255.255.255.0` both work).
- `set_fallback(sub_mode, global_mode)` makes the fallback mode's commands
  work in the sub-mode. Keywords from both modes are matched together, so `i`
  in `config-if` is ambiguous (`ip`, `interface`), as on IOS. A keyword defined
  in both (`ip address` / `ip route`) follows both branches.
- `no` and `do` are pseudo-keywords of the first word. `do` exists in config
  modes only and runs the PRIV_EXEC table.
- `execute(mode, line, ctx, prompt_width)` takes the prompt width so the `^`
  sits under the typed character. A single unknown word in USER/PRIV EXEC gets
  the `Translating "<word>"...` message instead of the `^` marker.
- `help(mode, line)` takes the text before the `?` (trailing space lists next
  tokens plus `<cr>`, no space lists completions); `complete(mode, line)` is Tab.
  `describe(mode, "show ip", "text")` sets the help line for a keyword prefix;
  the help passed to `register` is shown on the pattern's last token.

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

`IosCommands` (`cli/ios_commands.gd`) registers these. `IosCommands.registry_for(device)`
returns the shared command table for a router or a switch (null for hosts and
servers). Router and switch tables are separate, so a command that only exists
on the other kind (`switchport` on a router, `ip address` or `encapsulation` on
a switch) is rejected by the parser with the `^` marker under its first word, as
on IOS, and is absent from `?` help. Handlers change state only through
`NetworkSim` config calls (`set_hostname`, `set_admin_up`, `set_ip_address`,
`clear_ip_address`, `create_subinterface`, `set_dot1q_vlan`, `create_vlan`,
`set_vlan_name`, `set_switchport_mode`, `set_access_vlan`), which return a
`ConfigResult` and emit `config_changed` once per real change. A repeated
command that changes nothing emits nothing.

- A handler that finds the input unusable in context (an `interface` name the
  device doesn't have, `encapsulation` on a physical port) returns
  `CliResult.invalid_input(word_index)`; `CommandRegistry.execute` turns it into
  the `^` marker under that typed word (`no` counts as word 0).
- `interface <name>` on a router creates a missing subinterface (admin up, no
  `dot1q_vlan` yet) if its physical parent exists. On a switch, or for a port
  that doesn't exist, it is invalid input under the name.
- `vlan <id>` creates the VLAN with IOS's default name (`VLAN0010`) and
  enters VLAN_CONFIG; re-entering keeps the name. `switchport access vlan <id>`
  does not create the VLAN: the port carries nothing until the VLAN exists
  (`show vlan brief` will list it as inactive).
- `ip address` / `no ip address` is router-only (also on subinterfaces).
  `no ip address` takes optional trailing arguments, as on IOS.
- Not yet implemented: any other `no` form (`no vlan`, `no hostname`).

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
