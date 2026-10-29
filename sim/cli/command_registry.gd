class_name CommandRegistry
extends RefCounted
## Per-mode command table for the IOS-style CLI. Commands are token patterns
## ("show ip interface brief", "interface <interface>"); keywords match by
## unique prefix and `<...>` placeholders are typed arguments (CliArg).
## Handlers are `func(ctx, args: Array, negated: bool) -> CliResult`.
##
## `no`, `do` and sub-mode -> global command fallback are handled here, not in
## the handlers. A mode's keywords are the union of its own and its fallback
## chain's; when both define the same keyword the walk follows every branch.

const ERR_INCOMPLETE: String = "% Incomplete command."
const ERR_INVALID: String = "% Invalid input detected at '^' marker."
# "%%" is a literal percent sign in a format string.
const ERR_AMBIGUOUS: String = '%% Ambiguous command:  "%s"'
const ERR_UNKNOWN_WORD: String = 'Translating "%s"... %% Unknown command or computer name, or unable to find computer address'
const ERR_UNRECOGNIZED: String = "% Unrecognized command"

const KW_NO: String = "no"
const KW_DO: String = "do"
const EXTRA_HELP: Dictionary = {
	KW_NO: "Negate a command or set its defaults",
	KW_DO: "To run exec commands in config mode",
}

const ARG_TYPES: Dictionary = {
	"<interface>": CliArg.Type.INTERFACE,
	"<ipv4>": CliArg.Type.IPV4,
	"<mask>": CliArg.Type.MASK,
	"<vlan-id>": CliArg.Type.VLAN_ID,
	"<word>": CliArg.Type.WORD,
	"<line-range>": CliArg.Type.LINE_RANGE,
}

enum _Hit { NONE, ONE, AMBIGUOUS }

## Host and server shells accept a double-quoted argument; the IOS CLI doesn't.
var allow_quotes: bool = false
## IOS accepts any unique prefix of a keyword. The host shells run commands only
## by their full name, as Windows does; `?` and Tab still complete prefixes.
var allow_abbreviations: bool = true

var _roots: Dictionary = {}  # CliMode.Id -> _Node
var _no_roots: Dictionary = {}  # same, negatable commands only
var _fallback: Dictionary = {}  # CliMode.Id -> CliMode.Id
var _descriptions: Dictionary = {}  # "<mode>|<path>" -> help (describe)
var _leaf_help: Dictionary = {}  # "<mode>|<path>" -> help (register)


class _Command:
	extends RefCounted
	var pattern: String = ""
	var handler: Callable
	var help: String = ""


class _Node:
	extends RefCounted
	var mode: CliMode.Id = CliMode.Id.USER_EXEC
	var path: String = ""
	var children: Dictionary = {}  # lowercase keyword -> _Node
	var arg_child: _Node = null
	var arg_type: CliArg.Type = CliArg.Type.WORD
	var command: _Command = null


## A place in the trie plus the arguments parsed to get there.
class _Pos:
	extends RefCounted
	var node: _Node
	var args: Array = []

	static func make(p_node: _Node, p_args: Array) -> _Pos:
		var p := _Pos.new()
		p.node = p_node
		p.args = p_args
		return p


class _Walk:
	extends RefCounted
	var status: CliMatch.Status = CliMatch.Status.OK
	var error_col: int = 0
	var positions: Array[_Pos] = []
	var negated: bool = false
	var at_root: bool = true
	var mode: CliMode.Id = CliMode.Id.USER_EXEC


# --- registration -------------------------------------------------------------


## Adds a command. Returns false (and registers nothing) for an empty pattern,
## an unknown `<placeholder>`, a clash with an existing command, or two
## argument types at the same position. A negatable command also accepts
## `no <pattern>`, and for that form its trailing arguments are optional.
func register(mode: CliMode.Id, pattern: String, handler: Callable, help: String = "", negatable: bool = false) -> bool:
	var words: PackedStringArray = pattern.to_lower().split(" ", false)
	if words.is_empty():
		return false
	for w in words:
		if w.begins_with("<") and not ARG_TYPES.has(w):
			return false
	var cmd := _Command.new()
	cmd.pattern = pattern
	cmd.handler = handler
	cmd.help = help
	if not _can_insert(_root_for(_roots, mode), words):
		return false
	if negatable and not _can_insert(_root_for(_no_roots, mode), words):
		return false
	_insert(_root_for(_roots, mode), mode, words, cmd, false)
	if negatable:
		_insert(_root_for(_no_roots, mode), mode, words, cmd, true)
	if not help.is_empty():
		var key: String = _key(mode, " ".join(words))
		if not _leaf_help.has(key):
			_leaf_help[key] = help
	return true


## Sets the `?` help line for a pattern prefix such as "show ip".
func describe(mode: CliMode.Id, prefix: String, help: String) -> void:
	_descriptions[_key(mode, " ".join(prefix.to_lower().split(" ", false)))] = help


## Commands of `fallback` also work in `mode` (config sub-mode -> global).
func set_fallback(mode: CliMode.Id, fallback: CliMode.Id) -> void:
	_fallback[mode] = fallback


func _key(mode: CliMode.Id, path: String) -> String:
	return "%d|%s" % [mode, path]


func _root_for(table: Dictionary, mode: CliMode.Id) -> _Node:
	if not table.has(mode):
		var root := _Node.new()
		root.mode = mode
		table[mode] = root
	return table[mode]


func _can_insert(root: _Node, words: PackedStringArray) -> bool:
	var node: _Node = root
	for w in words:
		if w.begins_with("<"):
			if node.arg_child == null:
				return true  # the rest is new
			if node.arg_type != ARG_TYPES[w]:
				return false
			node = node.arg_child
		else:
			if not node.children.has(w):
				return true
			node = node.children[w]
	return node.command == null


func _insert(root: _Node, mode: CliMode.Id, words: PackedStringArray, cmd: _Command, optional_args: bool) -> void:
	var node: _Node = root
	var before_args: _Node = null
	var path: String = ""
	for w in words:
		path = w if path.is_empty() else path + " " + w
		var next: _Node
		if w.begins_with("<"):
			if before_args == null:
				before_args = node
			if node.arg_child == null:
				node.arg_child = _new_child(mode, path)
				node.arg_type = ARG_TYPES[w]
			next = node.arg_child
		else:
			if not node.children.has(w):
				node.children[w] = _new_child(mode, path)
			next = node.children[w]
		node = next
	node.command = cmd
	if optional_args and before_args != null and before_args.command == null and before_args != root:
		before_args.command = cmd


func _new_child(mode: CliMode.Id, path: String) -> _Node:
	var n := _Node.new()
	n.mode = mode
	n.path = path
	return n


# --- matching -----------------------------------------------------------------


func lookup(mode: CliMode.Id, line: String) -> CliMatch:
	return _lookup_tokens(mode, CliTokenizer.tokenize(line, allow_quotes))


## Matches `line` and runs the handler. Errors come back as failed CliResults
## with the exact IOS strings; `prompt_width` shifts the `^` marker so it sits
## under the typed character on the terminal row.
func execute(mode: CliMode.Id, line: String, ctx: Variant = null, prompt_width: int = 0) -> CliResult:
	var tokens: Array[CliToken] = CliTokenizer.tokenize(line, allow_quotes)
	var m: CliMatch = _lookup_tokens(mode, tokens)
	match m.status:
		CliMatch.Status.EMPTY:
			return CliResult.ok_output("")
		CliMatch.Status.INCOMPLETE:
			return CliResult.failure(ERR_INCOMPLETE)
		CliMatch.Status.AMBIGUOUS:
			return CliResult.failure(ERR_AMBIGUOUS % line.strip_edges())
		CliMatch.Status.INVALID:
			if CliMode.is_exec(mode) and tokens.size() == 1:
				return CliResult.failure(ERR_UNKNOWN_WORD % tokens[0].text)
			return CliResult.failure(" ".repeat(prompt_width + m.error_col) + "^\n" + ERR_INVALID)
	var res: Variant = m.handler.call(ctx, m.args, m.negated)
	if not res is CliResult:
		return CliResult.ok_output("")
	var result: CliResult = res
	if result.error_word >= 0:
		var col: int = tokens[mini(result.error_word, tokens.size() - 1)].start
		result.output = " ".repeat(prompt_width + col) + "^\n" + ERR_INVALID
	return result


## Text for `?`. `line` is what was typed before the `?`: a trailing space
## lists the possible next tokens, otherwise it lists completions of the
## last word.
func help(mode: CliMode.Id, line: String) -> String:
	var tokens: Array[CliToken] = CliTokenizer.tokenize(line, allow_quotes)
	var partial_word: bool = not tokens.is_empty() and not CliTokenizer.ends_with_whitespace(line)
	var w: _Walk = _walk(mode, tokens, tokens.size() - (1 if partial_word else 0))
	if w.status == CliMatch.Status.AMBIGUOUS:
		return ERR_AMBIGUOUS % line.strip_edges()
	if w.status == CliMatch.Status.INVALID:
		return ERR_UNRECOGNIZED
	var keywords: Dictionary = _keywords_at(w)
	if partial_word:
		var prefix: String = tokens[tokens.size() - 1].text.to_lower()
		var names: Array = keywords.keys().filter(func(k: String) -> bool: return k.begins_with(prefix))
		if names.is_empty():
			return ERR_UNRECOGNIZED
		names.sort()
		return "  ".join(PackedStringArray(names))
	var entries: Array = []
	var names: Array = keywords.keys()
	names.sort()
	for k: String in names:
		entries.append([k, keywords[k]])
	var has_cr: bool = false
	for p in w.positions:
		if p.node.arg_child != null:
			var an: _Node = p.node.arg_child
			entries.append([CliArg.placeholder(p.node.arg_type), _description(an)])
		if p.node.command != null:
			has_cr = true
	if has_cr:
		entries.append(["<cr>", ""])
	return _format_entries(entries)


## Tab completion: completes the last word if it is a unique keyword prefix,
## otherwise returns the line unchanged.
func complete(mode: CliMode.Id, line: String) -> String:
	var tokens: Array[CliToken] = CliTokenizer.tokenize(line, allow_quotes)
	if tokens.is_empty() or CliTokenizer.ends_with_whitespace(line):
		return line
	var w: _Walk = _walk(mode, tokens, tokens.size() - 1)
	if w.status == CliMatch.Status.INVALID or w.status == CliMatch.Status.AMBIGUOUS:
		return line
	var last: CliToken = tokens[tokens.size() - 1]
	var hit: Array = _resolve(last.text.to_lower(), _keywords_at(w).keys())
	if hit[0] != _Hit.ONE:
		return line
	return line.substr(0, last.start) + str(hit[1]) + " "


func _lookup_tokens(mode: CliMode.Id, tokens: Array[CliToken]) -> CliMatch:
	var m := CliMatch.new()
	m.token_count = tokens.size()
	if tokens.is_empty():
		m.status = CliMatch.Status.EMPTY
		return m
	var w: _Walk = _walk(mode, tokens, tokens.size())
	m.status = w.status
	m.error_col = w.error_col
	if w.status != CliMatch.Status.OK:
		return m
	for p in w.positions:
		var cmd: _Command = p.node.command
		if cmd != null:
			m.handler = cmd.handler
			m.pattern = cmd.pattern
			m.args = p.args
			m.negated = w.negated
			return m
	m.status = CliMatch.Status.INCOMPLETE
	return m


## Consumes the first `limit` tokens. Every trie branch still alive after a
## token stays in `positions`, so a keyword defined in both a mode and its
## fallback is followed in both.
func _walk(mode: CliMode.Id, tokens: Array[CliToken], limit: int) -> _Walk:
	var w := _Walk.new()
	w.mode = mode
	w.positions = _roots_of(_roots, mode)
	var i: int = 0
	while i < limit:
		var tok: CliToken = tokens[i]
		var extras: Array[String] = _extras(w)
		var hit: Array = _resolve(tok.text.to_lower(), _keywords_at(w).keys(), allow_abbreviations)
		if hit[0] == _Hit.AMBIGUOUS:
			w.status = CliMatch.Status.AMBIGUOUS
			w.error_col = tok.start
			return w
		if hit[0] == _Hit.ONE:
			var kw: String = hit[1]
			if extras.has(kw):
				if kw == KW_NO:
					w.negated = true
					w.positions = _roots_of(_no_roots, w.mode)
				else:
					w.mode = CliMode.Id.PRIV_EXEC
					w.positions = _roots_of(_roots, w.mode)
			else:
				var next: Array[_Pos] = []
				for p in w.positions:
					var child: _Node = p.node.children.get(kw)
					if child != null:
						next.append(_Pos.make(child, p.args))
				w.positions = next
				w.at_root = false
			i += 1
			continue
		var advanced: Array[_Pos] = []
		var step: int = 0
		var short: bool = false
		for p in w.positions:
			var an: _Node = p.node.arg_child
			if an == null:
				continue
			var arity: int = CliArg.arity(p.node.arg_type)
			if i + arity > limit:
				short = true
				continue
			var words := PackedStringArray()
			for k in arity:
				words.append(tokens[i + k].text)
			var parsed: CliArgResult = CliArg.parse(p.node.arg_type, words)
			if parsed.ok:
				var new_args: Array = p.args.duplicate()
				new_args.append(parsed.value)
				advanced.append(_Pos.make(an, new_args))
				if step == 0:
					step = arity
		if advanced.is_empty():
			w.status = CliMatch.Status.INCOMPLETE if short else CliMatch.Status.INVALID
			w.error_col = tok.start
			return w
		w.positions = advanced
		w.at_root = false
		i += step
	return w


func _roots_of(table: Dictionary, mode: CliMode.Id) -> Array[_Pos]:
	var out: Array[_Pos] = []
	for m in _chain(mode):
		var root: _Node = table.get(m)
		if root != null:
			out.append(_Pos.make(root, []))
	return out


func _chain(mode: CliMode.Id) -> Array[CliMode.Id]:
	var out: Array[CliMode.Id] = [mode]
	var cur: CliMode.Id = mode
	while _fallback.has(cur) and out.size() < 8:
		cur = _fallback[cur]
		out.append(cur)
	return out


## `no` and `do` are only keywords as the first word of a command.
func _extras(w: _Walk) -> Array[String]:
	var out: Array[String] = []
	if not w.at_root or w.negated:
		return out
	for m in _chain(w.mode):
		var root: _Node = _no_roots.get(m)
		if root != null and not root.children.is_empty():
			out.append(KW_NO)
			break
	if CliMode.is_config(w.mode):
		out.append(KW_DO)
	return out


## Keywords valid at the walk's current position -> their help text.
func _keywords_at(w: _Walk) -> Dictionary:
	var out: Dictionary = {}
	for p in w.positions:
		for k: String in p.node.children:
			var text: String = _description(p.node.children[k])
			if not out.has(k) or (str(out[k]).is_empty() and not text.is_empty()):
				out[k] = text
	for e in _extras(w):
		out[e] = EXTRA_HELP[e]
	return out


func _description(node: _Node) -> String:
	var key: String = _key(node.mode, node.path)
	if _descriptions.has(key):
		return _descriptions[key]
	return _leaf_help.get(key, "")


## Exact keyword wins, else a unique prefix. Returns [_Hit, word].
func _resolve(word: String, candidates: Array, prefixes: bool = true) -> Array:
	if candidates.has(word):
		return [_Hit.ONE, word]
	if not prefixes:
		return [_Hit.NONE, ""]
	var found: Array = candidates.filter(func(c: String) -> bool: return c.begins_with(word))
	if found.is_empty():
		return [_Hit.NONE, ""]
	if found.size() > 1:
		return [_Hit.AMBIGUOUS, ""]
	return [_Hit.ONE, found[0]]


func _format_entries(entries: Array) -> String:
	var width: int = 0
	for e: Array in entries:
		width = maxi(width, str(e[0]).length())
	var lines := PackedStringArray()
	for e: Array in entries:
		var name: String = str(e[0])
		var text: String = str(e[1])
		if text.is_empty():
			lines.append("  " + name)
		else:
			lines.append("  " + name + " ".repeat(width - name.length()) + "  " + text)
	return "\n".join(lines)
