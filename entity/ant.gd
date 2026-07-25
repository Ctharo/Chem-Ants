class_name Ant
extends Node
## A single ant. Owns the state a behaviour condition graph reads.
##
## [method write_state] is the bridge to the graph editor: it fills a plain
## Dictionary keyed exactly like [AntSchema], so the same values drive both the
## live simulation and the editor's test panel.

## What the ant is doing right now. Exactly one is true at a time; the graph
## sees them as the booleans is_idle, is_walking, is_picking_up_food, ...
enum Action {
	IDLE,
	WALKING,
	RESTING,
	EATING,
	PICKING_UP_FOOD,
	DROPPING_FOOD,
	FOLLOWING_TRAIL,
	FIGHTING,
}

#region Stats
const MAX_ENERGY: float = 100.0
const MAX_HEALTH: float = 100.0
const MAX_CARRY_MASS: float = 10.0
#endregion

#region Senses
const REACH_RANGE: float = 10.0
const VISION_RANGE: float = 60.0
const OLFACTORY_RANGE: float = 200.0
#endregion

signal action_changed(previous: Action, current: Action)

#region Status
var action: Action = Action.IDLE
var energy: float = MAX_ENERGY
var health: float = MAX_HEALTH
var carry_mass: float = 0.0
#endregion

## Optional helper that answers spatial queries (nearest visible food, ant
## counts, ...). Anything with a `write_state(out: Dictionary) -> void` method
## works; see AntSchema for the key format it must fill.
var senses: Node = null


## Canonical variable name for an action, e.g. PICKING_UP_FOOD -> is_picking_up_food.
static func action_var(action_key: String) -> String:
	return "is_" + action_key.to_lower()


static func action_key_of(p_action: Action) -> String:
	return Action.keys()[int(p_action)]


static func action_variables() -> Array[String]:
	var out: Array[String] = []
	for key: String in Action.keys():
		out.append(action_var(key))
	return out


func set_action(next: Action) -> void:
	if next == action:
		return
	var previous: Action = action
	action = next
	action_changed.emit(previous, action)


func is_doing(p_action: Action) -> bool:
	return action == p_action


func is_carrying_food() -> bool:
	return carry_mass > 0.0


func carry_fraction() -> float:
	return carry_mass / MAX_CARRY_MASS


## Range in world units for a sensing scope, matching AntSchema's scope names.
static func scope_range(scope: String) -> float:
	match scope:
		"reach":
			return REACH_RANGE
		"visible":
			return VISION_RANGE
		"smell":
			return OLFACTORY_RANGE
	return OLFACTORY_RANGE


## Fill `out` with everything a condition graph can read about this ant.
func write_state(out: Dictionary) -> void:
	for key: String in Action.keys():
		out[action_var(key)] = false
	out[action_var(action_key_of(action))] = true
	out["energy"] = energy
	out["health"] = health
	out["carry_mass"] = carry_mass
	out["is_carrying_food"] = is_carrying_food()
	if senses != null and senses.has_method("write_state"):
		senses.call("write_state", out)
