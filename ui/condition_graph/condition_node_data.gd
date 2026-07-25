class_name ConditionNodeData
extends RefCounted
## Data model for one node in a condition graph.
##
## kind: "logic" | "compare" | "timing" | "query" | "property" | "literal" | "vector"
## op:   logic  -> and/or/not/xor
##       compare-> lt/gt/eq/le/ge/ne
##       timing -> delay/hold/pulse/cooldown/latch
##       query  -> distance/count/exists/mass
##       vector -> const/from_angle/add/sub/scale/rotate/normalize/length/angle/dot
## type: "bool" | "float" | "int"
##
## Evaluation is UI-free: pass a Dictionary of variable values to [method tick].
## Timing nodes carry runtime state, so a subtree must be ticked ONCE per frame
## through a shared cache - see [method tick].

const LOGIC_OPS: Array[String] = ["and", "or", "not", "xor"]
const CMP_OPS: Array[String] = ["lt", "gt", "eq", "le", "ge", "ne"]
const TIMING_OPS: Array[String] = ["delay", "hold", "pulse", "cooldown", "latch"]
const QUERY_MEASURES: Array[String] = [
	"distance", "count", "exists", "mass", "direction", "offset",
]
const VECTOR_OPS: Array[String] = [
	"const", "from_angle", "add", "sub", "scale", "rotate", "normalize",
	"length", "angle", "dot",
]

## Result type of each vector-kind operation.
const VECTOR_TYPES: Dictionary = {
	"const": "vector", "from_angle": "vector", "add": "vector", "sub": "vector",
	"scale": "vector", "rotate": "vector", "normalize": "vector",
	"length": "float", "angle": "float", "dot": "float",
}
## Inputs each vector op consumes, in wiring order, with the type each must be.
const VECTOR_INPUTS: Dictionary = {
	"const": [], "from_angle": ["float"], "add": ["vector", "vector"],
	"sub": ["vector", "vector"], "scale": ["vector", "float"],
	"rotate": ["vector", "float"], "normalize": ["vector"],
	"length": ["vector"], "angle": ["vector"], "dot": ["vector", "vector"],
}
const VECTOR_NAMES: Dictionary = {
	"const": "fixed vector", "from_angle": "vector from angle",
	"add": "add vectors", "sub": "subtract vectors", "scale": "scale vector",
	"rotate": "rotate vector", "normalize": "unit vector",
	"length": "length of vector", "angle": "angle of vector",
	"dot": "dot product",
}
const VECTOR_HELP: Dictionary = {
	"const": "A vector you type in. Degrees are measured clockwise from east.",
	"from_angle": "Turns a number of degrees into a unit vector.",
	"add": "Vector sum of both inputs.",
	"sub": "First input minus the second.",
	"scale": "Stretches a vector by a number.",
	"rotate": "Turns a vector by a number of degrees.",
	"normalize": "Same direction, length 1. A zero vector stays zero.",
	"length": "How long the vector is - 0 means nothing was sensed.",
	"angle": "Degrees from east, in the range -180 to 180.",
	"dot": "Positive when the two vectors broadly agree, negative when opposed.",
}
const QUERY_SUBJECTS: Array[String] = [
	"food", "ant", "enemy", "nestmate", "colony", "pheromone",
]
const QUERY_SCOPES: Array[String] = ["reach", "visible", "smell", "any"]

const GLYPHS: Dictionary = {
	"and": "\u2227", "or": "\u2228", "not": "\u00ac", "xor": "\u2295",
	"lt": "<", "gt": ">", "eq": "=", "le": "\u2264", "ge": "\u2265", "ne": "\u2260",
	"delay": "T+", "hold": "T-", "pulse": "1\u00d7", "cooldown": "CD", "latch": "SR",
	"query": "\u25ce", "property": "\u25c6", "literal": "#",
	"const": "V", "from_angle": "\u2220", "add": "+", "sub": "\u2212",
	"scale": "\u00d7", "rotate": "\u21bb", "normalize": "\u00fb",
	"length": "|v|", "angle": "\u03b8", "dot": "\u00b7",
}
## Fallback set used when the active font is missing the unicode glyphs.
const ASCII_GLYPHS: Dictionary = {
	"and": "&", "or": "|", "not": "!", "xor": "^",
	"lt": "<", "gt": ">", "eq": "=", "le": "<=", "ge": ">=", "ne": "!=",
	"delay": "T+", "hold": "T-", "pulse": "1x", "cooldown": "CD", "latch": "SR",
	"query": "@", "property": "*", "literal": "#",
	"const": "V", "from_angle": "<)", "add": "+", "sub": "-",
	"scale": "*", "rotate": "@", "normalize": "^v",
	"length": "|v|", "angle": "th", "dot": ".",
}
const OP_WORDS: Dictionary = {
	"lt": "less", "gt": "greater", "eq": "equal",
	"le": "at most", "ge": "at least", "ne": "not equal",
}
const OP_SUBS: Dictionary = {
	"and": "all true", "or": "any true", "not": "invert", "xor": "one true",
}

## Plain-English name for each timing behaviour, shown in menus and inspectors.
const TIMING_NAMES: Dictionary = {
	"delay": "true after", "hold": "stay true for", "pulse": "pulse for",
	"cooldown": "at most once per", "latch": "latch until reset",
}
const TIMING_HELP: Dictionary = {
	"delay": "Input must hold true this long before the output turns true. Debounce.",
	"hold": "Output turns true with the input and stays true this long after it drops. Reset ends it early.",
	"pulse": "A rising input fires one burst of this length, then waits for the input to drop and rise again.",
	"cooldown": "Output can only turn true once per interval, however often the input fires.",
	"latch": "The first true input sticks. Only the reset input clears it; the duration is unused.",
}

const SUBJECT_WORDS: Dictionary = {
	"food": "food", "ant": "ant", "enemy": "enemy ant", "nestmate": "nestmate",
	"colony": "colony", "pheromone": "pheromone trail",
}
const SUBJECT_PLURAL: Dictionary = {
	"food": "food items", "ant": "ants", "enemy": "enemy ants",
	"nestmate": "nestmates", "colony": "colonies", "pheromone": "pheromone trails",
}
const SCOPE_WORDS: Dictionary = {
	"reach": "within reach", "visible": "visible", "smell": "detectable", "any": "known",
}
const MEASURE_WORDS: Dictionary = {
	"distance": "distance to nearest", "count": "number of",
	"exists": "presence of", "mass": "mass of nearest",
	"direction": "direction to nearest", "offset": "offset to nearest",
}

## Set to true by the editor if the UI font lacks the unicode glyph set.
static var ascii_mode: bool = false

static var _next_id: int = 1000

var id: String = ""
var kind: String = "logic"
var op: String = ""
var type: String = "bool"
var label: String = ""
var children: Array[ConditionNodeData] = []
## Library-package link. Empty string = not a package instance.
var pkg_id: String = ""
var pkg_name: String = ""
## Timing nodes: the interval in seconds.
var seconds: float = 1.0
## Query nodes: what is being sensed and how far out to look.
var subject: String = "food"
## Vector nodes with op "const": the literal value.
var vec: Vector2 = Vector2.ZERO
var scope: String = "visible"

# --- timing runtime state (never serialised) ---------------------------------
var _timer: float = 0.0
var _out: bool = false
var _prev_in: bool = false


static func new_id() -> String:
	_next_id += 1
	return "n%d" % _next_id


## Keep the id counter ahead of anything restored from disk so fresh nodes can
## never collide with loaded ones.
static func bump_id_floor(p_id: String) -> void:
	if not p_id.begins_with("n"):
		return
	var digits: String = p_id.substr(1)
	if not digits.is_valid_int():
		return
	_next_id = maxi(_next_id, digits.to_int())


static func create(p_kind: String, p_op: String = "") -> ConditionNodeData:
	var n: ConditionNodeData = ConditionNodeData.new()
	n.id = new_id()
	n.kind = p_kind
	match p_kind:
		"logic":
			n.op = p_op if p_op != "" else "and"
			n.type = "bool"
			n.label = n.op.to_upper()
		"compare":
			n.op = p_op if p_op != "" else "lt"
			n.type = "bool"
			n.children.append(create("property"))
			n.children.append(create("literal"))
			n.label = n.display_label()
		"timing":
			n.op = p_op if p_op != "" else "hold"
			n.type = "bool"
			n.seconds = 2.0
			n.label = ""
		"query":
			n.op = p_op if p_op != "" else "distance"
			n.subject = "food"
			n.scope = "visible"
			n.type = n.measure_type()
			n.label = ""
		"property":
			n.type = "float"
			n.label = "new_property"
		"literal":
			n.type = "float"
			n.label = "0.0"
		"vector":
			n.op = p_op if p_op != "" else "const"
			n.type = vector_type_of(n.op)
			n.label = ""
	return n


## Convenience for building trees by hand.
static func make(p_kind: String, p_op: String, p_type: String, p_label: String,
		p_children: Array = []) -> ConditionNodeData:
	var n: ConditionNodeData = ConditionNodeData.new()
	n.id = new_id()
	n.kind = p_kind
	n.op = p_op
	n.type = p_type
	n.label = p_label
	for c: Variant in p_children:
		n.children.append(c)
	return n


## Build a sense query directly, e.g. sense("distance", "food", "visible").
static func sense(p_measure: String, p_subject: String, p_scope: String,
		p_children: Array = []) -> ConditionNodeData:
	var n: ConditionNodeData = make("query", p_measure, "float", "", p_children)
	n.subject = p_subject
	n.scope = p_scope
	n.type = n.measure_type()
	return n


## Build a timing node, e.g. timer("hold", 2.5, [input, reset]).
static func timer(p_op: String, p_seconds: float,
		p_children: Array = []) -> ConditionNodeData:
	var n: ConditionNodeData = make("timing", p_op, "bool", "", p_children)
	n.seconds = p_seconds
	return n


static func glyph_for(key: String) -> String:
	if ascii_mode:
		return ASCII_GLYPHS.get(key, "?")
	return GLYPHS.get(key, "?")


## Human-readable operator name, e.g. "AND", "<= at most", "stay true for".
static func op_name(p_op: String) -> String:
	if p_op in LOGIC_OPS:
		return p_op.to_upper()
	if p_op in TIMING_OPS:
		return "%s %s" % [glyph_for(p_op), TIMING_NAMES.get(p_op, p_op)]
	if p_op in QUERY_MEASURES:
		return MEASURE_WORDS.get(p_op, p_op)
	if p_op in VECTOR_OPS:
		return "%s %s" % [glyph_for(p_op), VECTOR_NAMES.get(p_op, p_op)]
	return "%s %s" % [glyph_for(p_op), OP_WORDS.get(p_op, p_op)]


static func subject_name(p_subject: String) -> String:
	return SUBJECT_WORDS.get(p_subject, p_subject)


static func scope_name(p_scope: String) -> String:
	return SCOPE_WORDS.get(p_scope, p_scope)


## Gates accept inputs, can be entered, and can be wired into.
func is_gate() -> bool:
	return kind == "logic" or kind == "compare" or kind == "timing" or kind == "vector"


func is_timing() -> bool:
	return kind == "timing"


func glyph() -> String:
	if kind == "query":
		return glyph_for("query")
	return glyph_for(op if is_gate() else kind)


func kind_title() -> String:
	match kind:
		"logic":
			return (op if op != "" else "and").to_upper()
		"compare":
			return "Compare"
		"timing":
			return "Timing"
		"query":
			return "Sense"
		"property":
			return "Property"
		"vector":
			return "Vector"
	return "Constant"


## Value type a query measure produces.
func measure_type() -> String:
	match op:
		"exists":
			return "bool"
		"direction", "offset":
			return "vector"
	return "float"


## The variable key a query reads, e.g. "food.visible.distance".
func var_key() -> String:
	return "%s.%s.%s" % [subject, scope, op]


func display_label() -> String:
	match kind:
		"compare":
			if children.size() >= 2:
				return "%s %s %s" % [children[0].label, glyph_for(op), children[1].label]
			return "comparison (needs 2 inputs)"
		"timing":
			if label != "":
				return label
			if op == "latch":
				return "latch until reset"
			return "%s %ss" % [TIMING_NAMES.get(op, op), _trim_number(seconds)]
		"query":
			if label != "":
				return label
			var scope_word: String = SCOPE_WORDS.get(scope, scope)
			match op:
				"distance":
					return "distance to nearest %s %s" % [
						scope_word, SUBJECT_WORDS.get(subject, subject)]
				"count":
					return "number of %s %s" % [
						scope_word, SUBJECT_PLURAL.get(subject, subject)]
				"exists":
					return "any %s %s" % [scope_word, SUBJECT_WORDS.get(subject, subject)]
				"mass":
					return "mass of nearest %s %s" % [
						scope_word, SUBJECT_WORDS.get(subject, subject)]
				"direction":
					return "direction to nearest %s %s" % [
						scope_word, SUBJECT_WORDS.get(subject, subject)]
				"offset":
					return "offset to nearest %s %s" % [
						scope_word, SUBJECT_WORDS.get(subject, subject)]
			return var_key()
		"vector":
			if label != "":
				return label
			if op == "const":
				return "(%s, %s)" % [_trim_number(vec.x), _trim_number(vec.y)]
			return VECTOR_NAMES.get(op, op)
	return label


static func _trim_number(v: float) -> String:
	if is_equal_approx(v, roundf(v)):
		return str(roundi(v))
	return "%.1f" % v


# ============================================================================
# Serialisation
# ============================================================================
func to_dict() -> Dictionary:
	var kids: Array = []
	for c: ConditionNodeData in children:
		kids.append(c.to_dict())
	return {
		"id": id, "kind": kind, "op": op, "type": type, "label": label,
		"pkg_id": pkg_id, "pkg_name": pkg_name,
		"seconds": seconds, "subject": subject, "scope": scope,
		"vec": [vec.x, vec.y],
		"children": kids,
	}


## Rebuild a node (and its subtree) from to_dict() output. Returns null if the
## payload is not a Dictionary.
static func from_dict(data: Variant) -> ConditionNodeData:
	if not (data is Dictionary):
		return null
	var d: Dictionary = data
	var n: ConditionNodeData = ConditionNodeData.new()
	n.id = str(d.get("id", ""))
	if n.id == "":
		n.id = new_id()
	bump_id_floor(n.id)
	n.kind = str(d.get("kind", "logic"))
	n.op = str(d.get("op", ""))
	n.type = str(d.get("type", "bool"))
	n.label = str(d.get("label", ""))
	n.pkg_id = str(d.get("pkg_id", ""))
	n.pkg_name = str(d.get("pkg_name", ""))
	n.seconds = maxf(0.0, float(d.get("seconds", 1.0)))
	n.subject = str(d.get("subject", "food"))
	n.scope = str(d.get("scope", "visible"))
	var raw_vec: Variant = d.get("vec", [])
	if raw_vec is Array and (raw_vec as Array).size() == 2:
		var vec_parts: Array = raw_vec
		n.vec = Vector2(float(vec_parts[0]), float(vec_parts[1]))
	var kids: Variant = d.get("children", [])
	if kids is Array:
		for raw: Variant in (kids as Array):
			var c: ConditionNodeData = from_dict(raw)
			if c != null:
				n.children.append(c)
	return n


# ============================================================================
# Tree utilities
# ============================================================================
## Deep clone with fresh ids. Runtime timer state is deliberately not copied.
func clone_new() -> ConditionNodeData:
	var c: ConditionNodeData = clone_exact()
	c._relabel_ids()
	return c


## Deep clone preserving ids.
func clone_exact() -> ConditionNodeData:
	var c: ConditionNodeData = ConditionNodeData.new()
	c.id = id
	c.kind = kind
	c.op = op
	c.type = type
	c.label = label
	c.pkg_id = pkg_id
	c.pkg_name = pkg_name
	c.seconds = seconds
	c.subject = subject
	c.scope = scope
	c.vec = vec
	for child: ConditionNodeData in children:
		c.children.append(child.clone_exact())
	return c


func _relabel_ids() -> void:
	id = new_id()
	for c: ConditionNodeData in children:
		c._relabel_ids()


## Depth-first search; returns {"node": ..., "parent": ...} or empty Dictionary.
func find_with_parent(target_id: String, parent: ConditionNodeData = null) -> Dictionary:
	if id == target_id:
		return {"node": self, "parent": parent}
	for c: ConditionNodeData in children:
		var r: Dictionary = c.find_with_parent(target_id, self)
		if not r.is_empty():
			return r
	return {}


func contains_id(target_id: String) -> bool:
	if id == target_id:
		return true
	for c: ConditionNodeData in children:
		if c.contains_id(target_id):
			return true
	return false


## Collect all descendants (self included) whose pkg_id matches.
func collect_instances(target_pkg_id: String, out: Array) -> void:
	if pkg_id == target_pkg_id:
		out.append(self)
	for c: ConditionNodeData in children:
		c.collect_instances(target_pkg_id, out)


func has_timing() -> bool:
	if is_timing():
		return true
	for c: ConditionNodeData in children:
		if c.has_timing():
			return true
	return false


## Clear every timer in this subtree.
func reset_runtime() -> void:
	_timer = 0.0
	_out = false
	_prev_in = false
	for c: ConditionNodeData in children:
		c.reset_runtime()


## Ensure every variable this subtree reads exists in `vars`, using the schema's
## defaults so new sense queries arrive with a sensible starting value.
func seed_vars(vars: Dictionary) -> void:
	if kind == "property" and label != "" and not vars.has(label):
		vars[label] = AntSchema.default_for(label)
	elif kind == "query":
		var key: String = var_key()
		if not vars.has(key):
			vars[key] = AntSchema.default_for(key)
	for c: ConditionNodeData in children:
		c.seed_vars(vars)


# ============================================================================
# Evaluation
# ============================================================================
static func _truthy(v: Variant) -> bool:
	if v is bool:
		return v
	if v is float or v is int:
		return not is_zero_approx(v)
	return false

static func _as_vector(v: Variant) -> Vector2:
	if v is Vector2:
		return v
	return Vector2.ZERO

## Standard result envelope. "is_bool" is derived and kept only for older call
## sites - read "type" in new code.
static func _result(value: Variant, vtype: String) -> Dictionary:
	return {"value": value, "type": vtype, "is_bool": vtype == "bool"}

## A node that cannot produce an answer: missing inputs, or inputs of the wrong
## type. Propagates upward instead of guessing.
static func _undefined() -> Dictionary:
	return _result(null, "bool")
	
static func _as_number(v: Variant) -> float:
	if v is bool:
		return 1.0 if v else 0.0
	if v is float or v is int:
		return float(v)
	return 0.0


## Advance this subtree by `delta` seconds and return
## {"value": Variant (null = undefined), "is_bool": bool}.
##
## `cache` is shared across one pass and keyed by node id. It exists because a
## node is usually reachable through several ancestors, and a timing node must
## only advance once per frame - pass the SAME cache for a whole tick, and a
## fresh one for the next.
func tick(vars: Dictionary, delta: float, cache: Dictionary) -> Dictionary:
	if cache.has(id):
		return cache[id]
	var result: Dictionary = _compute(vars, delta, cache)
	cache[id] = result
	return result


## Stateless one-shot read. Timers report their current value without advancing.
func evaluate(vars: Dictionary) -> Dictionary:
	return tick(vars, 0.0, {})


func _compute(vars: Dictionary, delta: float, cache: Dictionary) -> Dictionary:
	match kind:
		"literal":
			return _result(label.to_float(), "float")
		"property":
			var val: Variant = vars.get(label)
			match type:
				"bool":
					return _result(_truthy(val), "bool")
				"vector":
					return _result(_as_vector(val), "vector")
			return _result(_as_number(val), "float")
		"query":
			var key: String = var_key()
			var raw: Variant = vars.get(key, AntSchema.default_for(key))
			match measure_type():
				"bool":
					return _result(_truthy(raw), "bool")
				"vector":
					return _result(_as_vector(raw), "vector")
			return _result(_as_number(raw), "float")
		"vector":
			return _compute_vector(vars, delta, cache)
		"compare":
			if children.size() < 2:
				return _undefined()
			var ar: Dictionary = children[0].tick(vars, delta, cache)
			var br: Dictionary = children[1].tick(vars, delta, cache)
			if ar["value"] == null or br["value"] == null:
				return _undefined()
			# Vectors are not ordered. Take a length or an angle first.
			if ar["type"] == "vector" or br["type"] == "vector":
				return _undefined()
			var a: float = _as_number(ar["value"])
			var b: float = _as_number(br["value"])
			var res: bool = false
			match op:
				"lt": res = a < b
				"gt": res = a > b
				"eq": res = is_equal_approx(a, b)
				"le": res = a <= b
				"ge": res = a >= b
				"ne": res = not is_equal_approx(a, b)
			return _result(res, "bool")
		"timing":
			if children.is_empty():
				return _undefined()
			var inr: Dictionary = children[0].tick(vars, delta, cache)
			if inr["value"] == null or inr["type"] == "vector":
				return _undefined()
			var input: bool = _truthy(inr["value"])
			var reset: bool = false
			if children.size() > 1:
				var rr: Dictionary = children[1].tick(vars, delta, cache)
				if rr["type"] == "vector":
					return _undefined()
				reset = _truthy(rr["value"])
			return _result(_advance(input, reset, delta), "bool")
		"logic":
			if children.is_empty():
				return _undefined()
			var kid_vals: Array = []
			for c: ConditionNodeData in children:
				var r: Dictionary = c.tick(vars, delta, cache)
				if r["value"] == null or r["type"] == "vector":
					return _undefined()
				kid_vals.append(r["value"])
			var out: bool = false
			match op:
				"and":
					out = true
					for v: Variant in kid_vals:
						if not _truthy(v):
							out = false
							break
				"or":
					for v: Variant in kid_vals:
						if _truthy(v):
							out = true
							break
				"not":
					out = not _truthy(kid_vals[0])
				"xor":
					var parity: int = 0
					for v: Variant in kid_vals:
						parity ^= 1 if _truthy(v) else 0
					out = parity == 1
			return _result(out, "bool")
	return _undefined()


## Vector-kind ops. Inputs are read in wiring order and must match
## VECTOR_INPUTS exactly; anything missing or mistyped leaves the node
## undefined rather than being coerced into something plausible.
func _compute_vector(vars: Dictionary, delta: float, cache: Dictionary) -> Dictionary:
	if op == "const":
		return _result(vec, "vector")
	var wants: Array = VECTOR_INPUTS.get(op, [])
	if children.size() < wants.size():
		return _undefined()
	var vals: Array = []
	for i: int in wants.size():
		var r: Dictionary = children[i].tick(vars, delta, cache)
		if r["value"] == null or r["type"] != str(wants[i]):
			return _undefined()
		vals.append(r["value"])
	match op:
		"from_angle":
			return _result(Vector2.RIGHT.rotated(deg_to_rad(_as_number(vals[0]))),
				"vector")
		"add":
			return _result(_as_vector(vals[0]) + _as_vector(vals[1]), "vector")
		"sub":
			return _result(_as_vector(vals[0]) - _as_vector(vals[1]), "vector")
		"scale":
			return _result(_as_vector(vals[0]) * _as_number(vals[1]), "vector")
		"rotate":
			return _result(_as_vector(vals[0]).rotated(deg_to_rad(_as_number(vals[1]))),
				"vector")
		"normalize":
			var v: Vector2 = _as_vector(vals[0])
			return _result(Vector2.ZERO if v.is_zero_approx() else v.normalized(),
				"vector")
		"length":
			return _result(_as_vector(vals[0]).length(), "float")
		"angle":
			return _result(rad_to_deg(_as_vector(vals[0]).angle()), "float")
		"dot":
			return _result(_as_vector(vals[0]).dot(_as_vector(vals[1])), "float")
	return _undefined()
	
## Drive the timer. A non-positive delta is a peek: report the current output
## without consuming edges or advancing time.
func _advance(input: bool, reset: bool, delta: float) -> bool:
	if delta <= 0.0:
		return _out
	match op:
		"delay":
			if reset or not input:
				_timer = 0.0
				_out = false
			else:
				_timer += delta
				_out = _timer >= seconds
		"hold":
			if reset:
				_timer = 0.0
				_out = false
			elif input:
				_timer = seconds
				_out = true
			else:
				_timer = maxf(0.0, _timer - delta)
				_out = _timer > 0.0
		"pulse":
			if reset:
				_timer = 0.0
				_out = false
			else:
				if input and not _prev_in:
					_timer = seconds
				_timer = maxf(0.0, _timer - delta)
				_out = _timer > 0.0
		"cooldown":
			_timer = maxf(0.0, _timer - delta)
			if reset:
				_timer = 0.0
				_out = false
			elif input and _timer <= 0.0:
				_out = true
				_timer = seconds
			else:
				_out = false
		"latch":
			if reset:
				_out = false
			elif input:
				_out = true
	_prev_in = input
	return _out


## 0..1 fill for the widget's timer bar. Meaningless for latch.
func timer_progress() -> float:
	if not is_timing() or seconds <= 0.0 or op == "latch":
		return 0.0
	return clampf(_timer / seconds, 0.0, 1.0)


func timer_remaining() -> float:
	return _timer
	
static func vector_type_of(p_op: String) -> String:
	return str(VECTOR_TYPES.get(p_op, "vector"))
