class_name ConditionNodeData
extends RefCounted
## Data model for one node in a condition graph.
##
## kind: "logic" | "compare" | "property" | "literal"
## op:   logic -> and/or/not/xor ; compare -> lt/gt/eq/le/ge/ne ; else ""
## type: "bool" | "float" | "int"
## Evaluation is UI-free: pass a Dictionary of variable values to evaluate().

const LOGIC_OPS: Array[String] = ["and", "or", "not", "xor"]
const CMP_OPS: Array[String] = ["lt", "gt", "eq", "le", "ge", "ne"]

const GLYPHS := {
	"and": "\u2227", "or": "\u2228", "not": "\u00ac", "xor": "\u2295",
	"lt": "<", "gt": ">", "eq": "=", "le": "\u2264", "ge": "\u2265", "ne": "\u2260",
	"property": "\u25c6", "literal": "#",
}
## Fallback set used when the active font is missing the unicode glyphs.
const ASCII_GLYPHS := {
	"and": "&", "or": "|", "not": "!", "xor": "^",
	"lt": "<", "gt": ">", "eq": "=", "le": "<=", "ge": ">=", "ne": "!=",
	"property": "*", "literal": "#",
}
const OP_WORDS := {
	"lt": "less", "gt": "greater", "eq": "equal",
	"le": "at most", "ge": "at least", "ne": "not equal",
}
const OP_SUBS := {"and": "all true", "or": "any true", "not": "invert", "xor": "one true"}

## Set to true by the editor if the UI font lacks the unicode glyph set.
static var ascii_mode := false

static var _next_id: int = 1000

var id: String
var kind: String = "logic"
var op: String = ""
var type: String = "bool"
var label: String = ""
var children: Array[ConditionNodeData] = []
## Library-package link. Empty string = not a package instance.
var pkg_id: String = ""
var pkg_name: String = ""


static func new_id() -> String:
	_next_id += 1
	return "n%d" % _next_id


## Factory matching the mockup's makeNode().
static func create(p_kind: String, p_op: String = "") -> ConditionNodeData:
	var n := ConditionNodeData.new()
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
		"property":
			n.type = "float"
			n.label = "new_property"
		"literal":
			n.type = "float"
			n.label = "0.0"
	return n


## Convenience for building trees by hand.
static func make(p_kind: String, p_op: String, p_type: String, p_label: String,
		p_children: Array = []) -> ConditionNodeData:
	var n := ConditionNodeData.new()
	n.id = new_id()
	n.kind = p_kind
	n.op = p_op
	n.type = p_type
	n.label = p_label
	for c in p_children:
		n.children.append(c)
	return n


static func glyph_for(key: String) -> String:
	if ascii_mode:
		return ASCII_GLYPHS.get(key, "?")
	return GLYPHS.get(key, "?")


## Human-readable operator name, e.g. "AND" or "<= at most".
static func op_name(p_op: String) -> String:
	if p_op in LOGIC_OPS:
		return p_op.to_upper()
	return "%s %s" % [glyph_for(p_op), OP_WORDS.get(p_op, p_op)]


func is_gate() -> bool:
	return kind == "logic" or kind == "compare"


func glyph() -> String:
	return glyph_for(op if is_gate() else kind)


func kind_title() -> String:
	match kind:
		"logic":
			return (op if op != "" else "and").to_upper()
		"compare":
			return "Compare"
		"property":
			return "Property"
	return "Constant"


func display_label() -> String:
	if kind == "compare":
		if children.size() >= 2:
			return "%s %s %s" % [children[0].label, glyph_for(op), children[1].label]
		return "comparison (needs 2 inputs)"
	return label


## Deep clone with fresh ids (mockup cloneNew). Drops package links on the copy root.
func clone_new() -> ConditionNodeData:
	var c := clone_exact()
	c._relabel_ids()
	return c


## Deep clone preserving ids (mockup structuredClone).
func clone_exact() -> ConditionNodeData:
	var c := ConditionNodeData.new()
	c.id = id
	c.kind = kind
	c.op = op
	c.type = type
	c.label = label
	c.pkg_id = pkg_id
	c.pkg_name = pkg_name
	for child in children:
		c.children.append(child.clone_exact())
	return c


func _relabel_ids() -> void:
	id = new_id()
	for c in children:
		c._relabel_ids()


## Depth-first search; returns {"node": ..., "parent": ...} or empty Dictionary.
func find_with_parent(target_id: String, parent: ConditionNodeData = null) -> Dictionary:
	if id == target_id:
		return {"node": self, "parent": parent}
	for c in children:
		var r := c.find_with_parent(target_id, self)
		if not r.is_empty():
			return r
	return {}


func contains_id(target_id: String) -> bool:
	if id == target_id:
		return true
	for c in children:
		if c.contains_id(target_id):
			return true
	return false


## Collect all descendants (self included) whose pkg_id matches.
func collect_instances(target_pkg_id: String, out: Array) -> void:
	if pkg_id == target_pkg_id:
		out.append(self)
	for c in children:
		c.collect_instances(target_pkg_id, out)


## Ensure every property label referenced below this node exists in vars.
func seed_vars(vars: Dictionary) -> void:
	if kind == "property" and not vars.has(label):
		vars[label] = false if type == "bool" else 50.0
	for c in children:
		c.seed_vars(vars)


static func _truthy(v: Variant) -> bool:
	if v is bool:
		return v
	if v is float or v is int:
		return v != 0
	return false


## Returns {"value": Variant (null = undefined), "is_bool": bool}.
func evaluate(vars: Dictionary) -> Dictionary:
	match kind:
		"literal":
			var f := label.to_float() # 0.0 for unparseable, matching the mockup
			return {"value": f, "is_bool": false}
		"property":
			var val: Variant = vars.get(label)
			if type == "bool":
				return {"value": _truthy(val), "is_bool": true}
			var num: float = 0.0
			if val is float or val is int:
				num = float(val)
			elif val is bool:
				num = 1.0 if val else 0.0
			return {"value": num, "is_bool": false}
		"compare":
			if children.size() < 2:
				return {"value": null, "is_bool": true}
			var av: Variant = children[0].evaluate(vars)["value"]
			var bv: Variant = children[1].evaluate(vars)["value"]
			if av == null or bv == null:
				return {"value": null, "is_bool": true}
			var a := float(av) if not (av is bool) else (1.0 if av else 0.0)
			var b := float(bv) if not (bv is bool) else (1.0 if bv else 0.0)
			var res := false
			match op:
				"lt": res = a < b
				"gt": res = a > b
				"eq": res = is_equal_approx(a, b)
				"le": res = a <= b
				"ge": res = a >= b
				"ne": res = not is_equal_approx(a, b)
			return {"value": res, "is_bool": true}
		"logic":
			if children.is_empty():
				return {"value": null, "is_bool": true}
			var kid_vals: Array = []
			for c in children:
				var r := c.evaluate(vars)
				if r["value"] == null:
					return {"value": null, "is_bool": true}
				kid_vals.append(r["value"])
			var out := false
			match op:
				"and":
					out = true
					for v in kid_vals:
						if not _truthy(v):
							out = false
							break
				"or":
					for v in kid_vals:
						if _truthy(v):
							out = true
							break
				"not":
					out = not _truthy(kid_vals[0])
				"xor":
					var parity := 0
					for v in kid_vals:
						parity ^= 1 if _truthy(v) else 0
					out = parity == 1
			return {"value": out, "is_bool": true}
	return {"value": null, "is_bool": true}
