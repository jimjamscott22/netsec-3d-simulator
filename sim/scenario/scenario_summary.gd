class_name ScenarioSummary
extends RefCounted
## What mission select needs to know about one scenario file, from
## NetworkSim.summarize_scenario (SPEC §3.3): its id, title and place in the
## order. A file that does not validate has `errors` and no title, so it can be
## skipped and reported instead of half-listed. Read-only once built.

## The file's name without `.json`, as given to the summarizer ("" if none).
var source: String = ""
var id: String = ""
var title: String = ""
var sequence: int = 0
var errors: Array[String] = []


static func valid(p_source: String, p_id: String, p_title: String, p_sequence: int) -> ScenarioSummary:
	var s := ScenarioSummary.new()
	s.source = p_source
	s.id = p_id
	s.title = p_title
	s.sequence = p_sequence
	return s


static func invalid(p_source: String, p_errors: Array[String]) -> ScenarioSummary:
	var s := ScenarioSummary.new()
	s.source = p_source
	s.errors = p_errors.duplicate()
	return s


func ok() -> bool:
	return errors.is_empty()
