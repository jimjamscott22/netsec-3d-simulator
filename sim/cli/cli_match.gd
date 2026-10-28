class_name CliMatch
extends RefCounted
## Outcome of matching one input line against a mode's commands. On OK the
## handler, parsed args and negation flag are set; on an error `error_col` is
## the column of the first bad character (INVALID) and the rest is empty.

enum Status { OK, EMPTY, INVALID, AMBIGUOUS, INCOMPLETE }

var status: Status = Status.OK
var error_col: int = 0
var token_count: int = 0
var handler: Callable
var pattern: String = ""
var args: Array = []
var negated: bool = false
