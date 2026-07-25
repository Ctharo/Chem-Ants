class_name ConditionLibrary
extends RefCounted
## Disk persistence for the reusable condition packages shown in the Conditions
## panel.
##
## A "group" is a Dictionary: {"id": String, "name": String,
## "root": ConditionNodeData}. Groups round-trip through JSON at [constant
## SAVE_PATH] so they survive between runs.

const SAVE_PATH: String = "user://condition_library.json"
const FORMAT_VERSION: int = 1

## DEVELOPMENT ONLY. While true, every launch wipes the saved library so we
## always boot from freshly generated defaults. Set to false to keep user data.
const DEV_CLEAR_ON_LAUNCH: bool = true


## Wipe the saved library when running in development mode. Loud on purpose:
## this must not survive into a release build.
static func dev_reset_user_data() -> void:
	if not DEV_CLEAR_ON_LAUNCH:
		return
	var existed: bool = FileAccess.file_exists(SAVE_PATH)
	if existed:
		var err: Error = DirAccess.remove_absolute(SAVE_PATH)
		if err != OK:
			push_error("ConditionLibrary: could not delete %s (error %d)." % [SAVE_PATH, err])
			existed = false
	print_rich("[color=orange][b]*** DEV MODE ***[/b] " +
		"ConditionLibrary.DEV_CLEAR_ON_LAUNCH is true - user data at %s was %s on launch. " % [
			SAVE_PATH, "DELETED" if existed else "already absent"] +
		"Flip that constant to false before shipping or players will lose their conditions." +
		"[/color]")
	push_warning("DEV MODE: condition library user data is cleared on every launch.")


static func user_path() -> String:
	return ProjectSettings.globalize_path(SAVE_PATH)


static func save_groups(groups: Array[Dictionary]) -> Error:
	var serialised: Array = []
	for g: Dictionary in groups:
		var root: ConditionNodeData = g.get("root")
		if root == null:
			continue
		serialised.append({
			"id": str(g.get("id", "")),
			"name": str(g.get("name", root.label)),
			"root": root.to_dict(),
		})
	var payload: Dictionary = {"version": FORMAT_VERSION, "groups": serialised}
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		var err: Error = FileAccess.get_open_error()
		push_error("ConditionLibrary: could not open %s for writing (error %d)." % [SAVE_PATH, err])
		return err
	var _written: bool = file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	return OK


static func load_groups() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not FileAccess.file_exists(SAVE_PATH):
		return out
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		push_error("ConditionLibrary: could not read %s (error %d)." % [
			SAVE_PATH, FileAccess.get_open_error()])
		return out
	var text: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_error("ConditionLibrary: %s is not a valid library file." % SAVE_PATH)
		return out
	var data: Dictionary = parsed
	var raw: Variant = data.get("groups", [])
	if not (raw is Array):
		return out
	for entry: Variant in (raw as Array):
		if not (entry is Dictionary):
			continue
		var d: Dictionary = entry
		var root: ConditionNodeData = ConditionNodeData.from_dict(d.get("root"))
		if root == null:
			continue
		var gid: String = str(d.get("id", ""))
		if gid == "":
			gid = ConditionNodeData.new_id()
		ConditionNodeData.bump_id_floor(gid)
		out.append({"id": gid, "name": str(d.get("name", root.label)), "root": root})
	return out


## Starter conditions generated on a fresh install. The editor writes these to
## user:// immediately so they behave exactly like anything the player saves.
static func default_groups() -> Array[Dictionary]:
	var out: Array[Dictionary] = []

	out.append(_group("target acquired", ConditionNodeData.make("logic", "or", "bool", "target acquired", [
		ConditionNodeData.make("compare", "lt", "bool", "", [
			ConditionNodeData.make("property", "", "float", "distance_to_target"),
			ConditionNodeData.make("literal", "", "float", "15.0"),
		]),
		ConditionNodeData.make("property", "", "bool", "has_line_of_sight"),
	])))

	out.append(_group("combat ready", ConditionNodeData.make("logic", "and", "bool", "combat ready", [
		ConditionNodeData.make("logic", "not", "bool", "not reloading", [
			ConditionNodeData.make("property", "", "bool", "is_reloading"),
		]),
		ConditionNodeData.make("compare", "gt", "bool", "", [
			ConditionNodeData.make("property", "", "float", "current_health"),
			ConditionNodeData.make("literal", "", "float", "25.0"),
		]),
	])))

	out.append(_group("needs food", ConditionNodeData.make("compare", "lt", "bool", "", [
		ConditionNodeData.make("property", "", "float", "energy"),
		ConditionNodeData.make("literal", "", "float", "30.0"),
	])))

	out.append(_group("near base", ConditionNodeData.make("compare", "lt", "bool", "", [
		ConditionNodeData.make("property", "", "float", "distance_to_base"),
		ConditionNodeData.make("literal", "", "float", "20.0"),
	])))

	out.append(_group("hands full", ConditionNodeData.make("property", "", "bool", "is_carrying_food")))

	return out


static func _group(p_name: String, root: ConditionNodeData) -> Dictionary:
	root.label = p_name
	root.pkg_id = ""
	root.pkg_name = ""
	return {"id": ConditionNodeData.new_id(), "name": p_name, "root": root}
