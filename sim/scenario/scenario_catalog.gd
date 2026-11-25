class_name ScenarioCatalog
extends RefCounted
## The missions the player can pick, built from the summaries of every scenario
## file (task 2.10). Pure: the `Sim` autoload reads the files, this decides what
## the list is.
##
## A file that does not validate is left out and reported. So are all files that
## share one `sequence`, because mission order and locking depend on it being
## unique and the sim cannot tell which file was meant.

## The listed missions, sorted by `sequence`.
var missions: Array[ScenarioSummary] = []
## One line per file or sequence that was left out and why.
var problems: Array[String] = []


static func build(summaries: Array[ScenarioSummary]) -> ScenarioCatalog:
	var catalog := ScenarioCatalog.new()
	var by_sequence: Dictionary = {}
	for summary: ScenarioSummary in summaries:
		if not summary.ok():
			catalog.problems.append("%s.json is not a valid scenario and is left out: %s" % [
				summary.source, "; ".join(PackedStringArray(summary.errors))
			])
			continue
		var group: Array = by_sequence.get(summary.sequence, [])
		group.append(summary)
		by_sequence[summary.sequence] = group
	var sequences: Array = by_sequence.keys()
	sequences.sort()
	for sequence: int in sequences:
		var group: Array = by_sequence[sequence]
		if group.size() == 1:
			catalog.missions.append(group[0])
			continue
		var names: PackedStringArray = []
		for summary: ScenarioSummary in group:
			names.append("%s.json" % summary.source)
		catalog.problems.append("sequence %d is used by %s; none of them is listed" % [
			sequence, " and ".join(names)
		])
	return catalog


## True when mission `index` of `missions` is locked: every mission but the first
## waits until the one before it is in `completed`.
static func is_locked(list: Array[ScenarioSummary], index: int, completed: Array[String]) -> bool:
	if index <= 0 or index >= list.size():
		return false
	return not completed.has(list[index - 1].id)
