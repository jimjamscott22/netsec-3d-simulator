#!/usr/bin/env bash
# Sim-core purity check (SPEC §3.1 and §9).
#
# Scans res://sim/ and fails (exit 1) on any hit. Every hit is printed as
#   <file>:<line>: [<group>] <message>
# Groups: base, scene-tree, nondeterminism, dependency, autoload.
#
# Usage: tools/check_sim_purity.sh [project_root]   (default: the repo root)
# Needs only bash, grep, awk, sed.

set -u

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
ROOT="$(cd "$ROOT" && pwd)"
SIM="$ROOT/sim"
PROJECT_FILE="$ROOT/project.godot"

if [ ! -d "$SIM" ]; then
	echo "purity: no sim/ directory under $ROOT, nothing to check"
	exit 0
fi

FILES=()
while IFS= read -r f; do
	FILES+=("$f")
done < <(find "$SIM" -name '*.gd' | LC_ALL=C sort)

hits=0
report() { # file line group message
	local rel="${1#"$ROOT"/}"
	echo "$rel:$2: [$3] $4"
	hits=$((hits + 1))
}

# Prints "<line>:<code>" with comments removed (a '#' inside a string is kept).
# With a second argument "blank", string contents are emptied too, so words
# inside string literals never match the pattern rules. Triple-quoted strings
# (which can span lines) are always emptied.
strip_comments() {
	awk -v blank="${2:-}" '
	{
		out = ""; q = ""; n = length($0); i = 1
		while (i <= n) {
			if (tq != "") {
				j = index(substr($0, i), tq)
				if (j == 0) { i = n + 1 }
				else { i += j + 2; out = out tq; tq = "" }
			} else if (q != "") {
				c = substr($0, i, 1)
				if (c == "\\") { if (blank == "") out = out substr($0, i, 2); i += 2 }
				else if (c == q) { q = ""; out = out c; i++ }
				else { if (blank == "") out = out c; i++ }
			} else {
				c = substr($0, i, 1); t3 = substr($0, i, 3)
				if (t3 == "\"\"\"" || t3 == "\047\047\047") { tq = t3; out = out t3; i += 3 }
				else if (c == "\"" || c == "\047") { q = c; out = out c; i++ }
				else if (c == "#") break
				else { out = out c; i++ }
			}
		}
		print NR ":" out
	}' "$1"
}

# Prints "$1" with "." and ".." path segments resolved (lexically).
normpath() {
	awk -v p="$1" 'BEGIN {
		n = split(p, a, "/"); m = 0
		for (i = 1; i <= n; i++) {
			if (a[i] == "" || a[i] == ".") continue
			if (a[i] == "..") { if (m > 0) m--; continue }
			s[++m] = a[i]
		}
		out = ""
		for (i = 1; i <= m; i++) out = out "/" s[i]
		print out
	}'
}

# --- Pattern groups ---------------------------------------------------------

B='(^|[^A-Za-z0-9_])' # left word boundary; works after the "<line>:" prefix

RULES=(
	"scene-tree|${B}get_tree|get_tree (the sim must not touch the scene tree)"
	"scene-tree|${B}get_node|get_node (the sim must not touch the scene tree)"
	"scene-tree|[$][A-Za-z_\"'%]|\$ node path"
	"raw:scene-tree|/root/|/root/ node path"
	"nondeterminism|${B}Input\\.|Input"
	"nondeterminism|${B}Time\\.|Time"
	"nondeterminism|${B}OS\\.get_ticks|OS.get_ticks_*"
	"nondeterminism|Timer|Timer"
	"nondeterminism|create_timer|create_timer"
	"nondeterminism|${B}await([^A-Za-z0-9_]|$)|await"
	"nondeterminism|${B}(randf|randi|randomize|rand_from_seed)|randomness"
	"nondeterminism|RandomNumberGenerator|RandomNumberGenerator"
	"nondeterminism|\\.(shuffle|pick_random)\\(|unseeded randomness (shuffle/pick_random)"
	"raw:dependency|res://(world|ui|game)/|path into world/, ui/ or game/ (dependencies point inward only)"
	"autoload|${B}Engine\\.get_singleton|Engine.get_singleton"
)

if [ -f "$PROJECT_FILE" ]; then
	while IFS= read -r name; do
		[ -n "$name" ] && RULES+=("autoload|${B}${name}\\.|autoload '$name'")
	done < <(awk '
		/^\[/ { in_autoload = ($0 == "[autoload]"); next }
		in_autoload && /^[A-Za-z_][A-Za-z0-9_]*[ \t]*=/ {
			sub(/[ \t]*=.*/, ""); print
		}' "$PROJECT_FILE")
fi

# --- Base-class check (resolves extends chains inside sim/) ------------------

# Echoes the file under sim/ that declares `class_name $1`, if any.
find_class_file() {
	local f
	for f in "${FILES[@]}"; do
		if strip_comments "$f" | grep -qE ":[[:space:]]*class_name[[:space:]]+$1([[:space:]]|$)"; then
			echo "$f"
			return 0
		fi
	done
	return 1
}

# Echoes the top-level `extends` target of a file (empty if none).
top_extends() {
	strip_comments "$1" | sed -nE \
		's/^[0-9]+:(class_name[[:space:]]+[A-Za-z0-9_]+[[:space:]]+)?extends[[:space:]]+("[^"]*"|[^[:space:]:]+).*/\2/p' | head -n 1
}

# Returns 0 if `target` (as extended from `from_file`) ends in RefCounted/Resource.
# On failure sets WHY.
WHY=""
base_ok() { # target from_file depth
	local target="$1" from="$2" depth="$3" path file next
	if [ "$depth" -gt 32 ]; then WHY="extends chain too deep or cyclic"; return 1; fi
	case "$target" in
		"" | RefCounted | Resource) return 0 ;;
	esac
	case "$target" in
		\"* | \'*)
			path="${target//[\"\']/}"
			case "$path" in
				res://*) file="$ROOT/${path#res://}" ;;
				*) file="$(dirname "$from")/$path" ;;
			esac
			file="$(normpath "$file")"
			if [ ! -f "$file" ] || [[ "$file" != "$SIM"/* ]]; then
				WHY="extends $target, which is not a script under sim/"
				return 1
			fi
			;;
		*)
			# An inner class declared in the same file is checked on its own line.
			if strip_comments "$from" | grep -qE ":[[:space:]]*class[[:space:]]+$target[[:space:]]+extends"; then
				return 0
			fi
			if ! file="$(find_class_file "$target")"; then
				WHY="extends $target, which is not RefCounted, Resource or a class_name defined under sim/"
				return 1
			fi
			;;
	esac
	next="$(top_extends "$file")"
	base_ok "$next" "$file" $((depth + 1))
}

for f in "${FILES[@]}"; do
	# Top-level extends.
	target="$(top_extends "$f")"
	if ! base_ok "$target" "$f" 0; then
		line="$(strip_comments "$f" | grep -nE "^[0-9]+:(class_name[[:space:]]+[A-Za-z0-9_]+[[:space:]]+)?extends" | head -n 1 | cut -d: -f1)"
		report "$f" "${line:-1}" base "$WHY"
	fi
	# Inner classes: "class Name extends Base:".
	while IFS= read -r entry; do
		[ -z "$entry" ] && continue
		lineno="${entry%%:*}"
		inner="$(sed -E 's/^[0-9]+:[[:space:]]*class[[:space:]]+[A-Za-z0-9_]+[[:space:]]+extends[[:space:]]+("[^"]*"|[^[:space:]:]+).*/\1/' <<<"$entry")"
		if ! base_ok "$inner" "$f" 0; then
			report "$f" "$lineno" base "inner class: $WHY"
		fi
	done < <(strip_comments "$f" | grep -E "^[0-9]+:[[:space:]]*class[[:space:]]+[A-Za-z0-9_]+[[:space:]]+extends" || true)

	# Relative paths ("../") must stay inside sim/. Plain res://world|ui|game/ paths
	# are caught by the dependency rule below; this also catches "res://sim/../ui/x.gd".
	while IFS= read -r entry; do
		[ -z "$entry" ] && continue
		lit="${entry#*:}"
		case "$lit" in
			*../* | */.. | ..) ;;
			*) continue ;;
		esac
		case "$lit" in
			res://*) abs="$ROOT/${lit#res://}" ;;
			*://*) continue ;;
			*) abs="$(dirname "$f")/$lit" ;;
		esac
		abs="$(normpath "$abs")"
		if [[ "$abs" != "$SIM"/* ]]; then
			report "$f" "${entry%%:*}" dependency "path '$lit' escapes sim/ (resolves to ${abs#"$ROOT"/})"
		fi
	done < <(strip_comments "$f" | awk '{
		i = index($0, ":"); ln = substr($0, 1, i - 1); s = substr($0, i + 1)
		while (match(s, /"[^"]*"|\047[^\047]*\047/)) {
			print ln ":" substr(s, RSTART + 1, RLENGTH - 2)
			s = substr(s, RSTART + RLENGTH)
		}
	}')

	# Pattern groups.
	for rule in "${RULES[@]}"; do
		group="${rule%%|*}"
		mode=blank
		case "$group" in raw:*) group="${group#raw:}"; mode="" ;; esac
		rest="${rule#*|}"
		msg="${rest##*|}"
		pattern="${rest%|*}"
		while IFS= read -r entry; do
			[ -z "$entry" ] && continue
			report "$f" "${entry%%:*}" "$group" "$msg"
		done < <(strip_comments "$f" $mode | grep -E -- "$pattern" || true)
	done
done

if [ "$hits" -gt 0 ]; then
	echo "purity: FAILED with $hits violation(s)"
	exit 1
fi
echo "purity: OK (${#FILES[@]} file(s) scanned)"
