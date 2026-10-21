#!/usr/bin/env bash
# Self-test for check_sim_purity.sh.
# Each directory in tools/purity_fixtures/ is a tiny fake project root:
#   pass_*          must pass (exit 0)
#   fail_<group>_*  must fail (exit 1) and report a "[<group>]" hit
# <group> is one of: base, scene (= scene-tree), nondeterminism, dependency, autoload.

set -u

TOOLS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
failures=0

for dir in "$TOOLS"/purity_fixtures/*/; do
	name="$(basename "$dir")"
	out="$("$TOOLS/check_sim_purity.sh" "$dir" 2>&1)"
	code=$?
	case "$name" in
		pass_*)
			if [ "$code" -ne 0 ]; then
				echo "FAIL $name: expected pass, got exit $code"
				echo "$out" | sed 's/^/    /'
				failures=$((failures + 1))
			fi
			;;
		fail_*)
			group="${name#fail_}"
			group="${group%%_*}"
			[ "$group" = "scene" ] && group="scene-tree"
			if [ "$code" -ne 1 ]; then
				echo "FAIL $name: expected exit 1, got $code"
				failures=$((failures + 1))
			elif ! grep -q "\[$group\]" <<<"$out"; then
				echo "FAIL $name: no [$group] hit in output"
				echo "$out" | sed 's/^/    /'
				failures=$((failures + 1))
			fi
			;;
	esac
done

if [ "$failures" -gt 0 ]; then
	echo "purity self-test: $failures fixture(s) misbehaved"
	exit 1
fi
echo "purity self-test: OK"
