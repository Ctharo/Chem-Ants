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

const CATEGORY_ACTION: String = "Action"
const CATEGORY_VITALS: String = "Vitals"
const CATEGORY_CARGO: String = "Cargo"
const CATEGORY_SENSES: String = "Senses"
const CATEGORY_CUSTOM: String = "Custom"

const CATEGORY_ORDER: Array[String] = [
	CATEGORY_ACTION, CATEGORY_VITALS, CATEGORY_CARGO, CATEGORY_SENSES, CATEGORY_CUSTOM,
]

## Rough upper bound for "how many things could I see at once", used to scale
## the test-panel sliders for count queries.
const MAX_EXPECTED_COUNT: float = 24.0


static func action_variables() -> Array[String]:
	return Ant.action_variables()


## Every variable that always exists, whether or not a node references it.
static func base_variables() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for var_name: String in Ant.action_variables():
		out.append(_flag(var_name, CATEGORY_ACTION, false))
	out.append(_number("energy", CATEGORY_VITALS, Ant.MAX_ENERGY, 0.0, Ant.MAX_ENERGY))
	out.append(_number("health", CATEGORY_VITALS, Ant.MAX_HEALTH, 0.0, Ant.MAX_HEALTH))
	out.append(_number("carry_mass", CATEGORY_CARGO, 0.0, 0.0, Ant.MAX_CARRY_MASS))
	out.append(_flag("is_carrying_food", CATEGORY_CARGO, false))
	return out


## Type, category, default and slider range for any variable name, including
## sense-query keys that were never declared up front.
static func describe(var_name: String) -> Dictionary:
	for v: Dictionary in base_variables():
		if v["name"] == var_name:
			return v
	var parts: PackedStringArray = var_name.split(".")
	if parts.size() == 3:
		return _sense(var_name, parts[1], parts[2])
	return _number(var_name, CATEGORY_CUSTOM, 0.0, 0.0, 100.0)


static func default_for(var_name: String) -> Variant:
	return describe(var_name)["default"]


static func type_of(var_name: String) -> String:
	return describe(var_name)["type"]


static func category_of(var_name: String) -> String:
	return describe(var_name)["category"]


## A sense key's shape depends on its measure. "Nothing found" for a distance is
## the edge of the sensing range, which keeps `distance < n` comparisons honest
## without needing a separate found/not-found flag.
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
	return _number(var_name, CATEGORY_SENSES, 0.0, 0.0, 100.0)


static func _number(var_name: String, category: String, value: float,
		low: float, high: float) -> Dictionary:
	return {"name": var_name, "type": "float", "category": category,
		"default": value, "min": low, "max": high}


static func _flag(var_name: String, category: String, value: bool) -> Dictionary:
	return {"name": var_name, "type": "bool", "category": category,
		"default": value, "min": 0.0, "max": 1.0}
