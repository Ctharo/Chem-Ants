class_name AntSchema
extends RefCounted
## The catalogue of variables a behaviour condition graph can read.
##
## One-way dependency: this reads [Ant], and both [ConditionNodeData] and the
## graph editor read this. Nothing here reads the editor back.
##
## Sense queries use a three-part key: "<subject>.<scope>.<measure>", e.g.
## "food.visible.distance" or "enemy.smell.count". [ConditionNodeData] builds
## those keys; a senses provider fills them in on the runtime side.
##
## Three value types exist: "bool", "float" and "vector". Vector senses are
## always ant-relative - "direction" is a unit vector pointing at the subject,
## "offset" is the full vector to it - so a behaviour that works on one map
## still means the same thing on another. [constant Vector2.ZERO] is the
## canonical "nothing found", which keeps `length(direction) > 0` honest the
## same way an at-the-limit distance does.

const CATEGORY_ACTION: String = "Action"
const CATEGORY_VITALS: String = "Vitals"
const CATEGORY_CARGO: String = "Cargo"
const CATEGORY_SENSES: String = "Senses"
const CATEGORY_CUSTOM: String = "Custom"

const CATEGORY_ORDER: Array[String] = [
	CATEGORY_ACTION, CATEGORY_VITALS, CATEGORY_CARGO, CATEGORY_SENSES, CATEGORY_CUSTOM,
]

const TYPE_BOOL: String = "bool"
const TYPE_FLOAT: String = "float"
const TYPE_VECTOR: String = "vector"

## Rough upper bound for "how many things could I see at once", used to scale
## the test-panel sliders for count queries.
const MAX_EXPECTED_COUNT: float = 24.0

## Specs are pure functions of [Ant]'s constants, so they are built once and
## reused. Callers must treat the returned Dictionaries as read-only.
static var _base_cache: Array[Dictionary] = []
static var _describe_cache: Dictionary = {}


static func action_variables() -> Array[String]:
	return Ant.action_variables()


## Every variable that always exists, whether or not a node references it.
## Read-only: the caller shares one cached copy with everyone else.
static func base_variables() -> Array[Dictionary]:
	if not _base_cache.is_empty():
		return _base_cache
	var out: Array[Dictionary] = []
	for var_name: String in Ant.action_variables():
		out.append(_flag(var_name, CATEGORY_ACTION, false))
	out.append(_number("energy", CATEGORY_VITALS, Ant.MAX_ENERGY, 0.0, Ant.MAX_ENERGY))
	out.append(_number("health", CATEGORY_VITALS, Ant.MAX_HEALTH, 0.0, Ant.MAX_HEALTH))
	out.append(_number("carry_mass", CATEGORY_CARGO, 0.0, 0.0, Ant.MAX_CARRY_MASS))
	out.append(_flag("is_carrying_food", CATEGORY_CARGO, false))
	_base_cache = out
	return _base_cache


## Type, category, default and slider range for any variable name, including
## sense-query keys that were never declared up front.
static func describe(var_name: String) -> Dictionary:
	if _describe_cache.has(var_name):
		return _describe_cache[var_name]
	var spec: Dictionary = _build_spec(var_name)
	_describe_cache[var_name] = spec
	return spec


static func default_for(var_name: String) -> Variant:
	return describe(var_name)["default"]


static func type_of(var_name: String) -> String:
	return describe(var_name)["type"]


static func category_of(var_name: String) -> String:
	return describe(var_name)["category"]


## Magnitude ceiling for a variable. For vectors this is the longest the value
## can legitimately get, which the test panel uses as its length slider range.
static func max_of(var_name: String) -> float:
	return float(describe(var_name)["max"])


static func is_vector(var_name: String) -> bool:
	return type_of(var_name) == TYPE_VECTOR


## Drop every cached spec. Only needed if [Ant]'s constants become runtime
## tunables; harmless to call otherwise.
static func invalidate_cache() -> void:
	_base_cache = []
	_describe_cache = {}


static func _build_spec(var_name: String) -> Dictionary:
	for v: Dictionary in base_variables():
		if v["name"] == var_name:
			return v
	var parts: PackedStringArray = var_name.split(".")
	if parts.size() == 3:
		return _sense(var_name, parts[1], parts[2])
	return _number(var_name, CATEGORY_CUSTOM, 0.0, 0.0, 100.0)


## A sense key's shape depends on its measure. "Nothing found" for a distance is
## the edge of the sensing range, which keeps `distance < n` comparisons honest
## without needing a separate found/not-found flag. The vector measures use
## Vector2.ZERO for the same job.
static func _sense(var_name: String, scope: String, measure: String) -> Dictionary:
	match measure:
		"distance":
			var limit: float = Ant.scope_range(scope)
			return _number(var_name, CATEGORY_SENSES, limit, 0.0, limit)
		"count":
			return _number(var_name, CATEGORY_SENSES, 0.0, 0.0, MAX_EXPECTED_COUNT)
		"mass":
			return _number(var_name, CATEGORY_SENSES, 0.0, 0.0, Ant.MAX_CARRY_MASS * 5.0)
		"exists":
			return _flag(var_name, CATEGORY_SENSES, false)
		"direction":
			return _vector(var_name, CATEGORY_SENSES, Vector2.ZERO, 1.0)
		"offset":
			return _vector(var_name, CATEGORY_SENSES, Vector2.ZERO,
				Ant.scope_range(scope))
	return _number(var_name, CATEGORY_SENSES, 0.0, 0.0, 100.0)


static func _number(var_name: String, category: String, value: float,
		low: float, high: float) -> Dictionary:
	return {"name": var_name, "type": TYPE_FLOAT, "category": category,
		"default": value, "min": low, "max": high}


static func _flag(var_name: String, category: String, value: bool) -> Dictionary:
	return {"name": var_name, "type": TYPE_BOOL, "category": category,
		"default": value, "min": 0.0, "max": 1.0}


## "min"/"max" on a vector describe its magnitude, not its components: the test
## panel edits vectors as angle plus length, and length 0 means "nothing there".
static func _vector(var_name: String, category: String, value: Vector2,
		radius: float) -> Dictionary:
	return {"name": var_name, "type": TYPE_VECTOR, "category": category,
		"default": value, "min": 0.0, "max": radius}
