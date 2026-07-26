class_name GraphInspector
extends RefCounted
## Builds the single-node edit form for the condition-graph inspector panel.
##
## Extracted from ConditionGraphEditor: the editor keeps selection routing
## (_update_inspector) and reacts to this class through signals, so the form
## code never reaches back into editor internals directly. Async or lookup
## dependencies that live on the editor come in as typed Callables via setup().

const COLORS: Dictionary = GraphTheme.COLORS

## A structural edit was made. The editor's handler is its old _commit_edit():
## mark the package dirty, rebuild the viewport, refresh the inspector.
signal committed
## A cosmetic change (label text while typing): repaint traces only.
signal soft_changed
## The set of variables the graph reads may have changed: re-render the panel.
signal vars_changed
## Rebuild the inspector without a document change (e.g. a cancelled prompt).
signal refresh_requested

var skin: GraphTheme = null
var form_box: VBoxContainer = null
var insp_title: Label = null
## The editor's own id -> GraphNodeWidget map, shared by reference. The editor
## clears it in place on rebuild but never reassigns it, so this stays current.
var widgets: Dictionary = {}

## Async name prompt: func(title: String, desc: String, default: String) -> String.
## Returns "" on cancel. Wired to ConditionGraphEditor._prompt.
var prompt: Callable = Callable()
## func() -> Dictionary: category name -> Array[String] of variable names.
var variables_by_category: Callable = Callable()
## func(var_name: String) -> String: display type for a variable.
var var_type: Callable = Callable()
## func(value: float) -> String: short number formatting for sense ranges.
var trim_range: Callable = Callable()


func setup(p_skin: GraphTheme, p_form_box: VBoxContainer, p_insp_title: Label,
		p_widgets: Dictionary) -> void:
	skin = p_skin
	form_box = p_form_box
	insp_title = p_insp_title
	widgets = p_widgets


## Rebuild the form for one node. `test_vars` is the editor's live dictionary;
## the "+ new variable..." flow writes straight into it.
func build_form(node: ConditionNodeData, test_vars: Dictionary) -> void:
	for c: Node in form_box.get_children():
		form_box.remove_child(c)
		c.queue_free()
	match node.kind:
		"literal":
			_literal_form(node)
		"property":
			_property_form(node, test_vars)
		"compare":
			_compare_form(node)
		"logic":
			_logic_form(node)
		"timing":
			_timing_form(node)
		"query":
			_query_form(node)
		"vector":
			_vector_form(node)


# ============================================================================
# Per-kind forms
# ============================================================================
func _literal_form(node: ConditionNodeData) -> void:
	form_box.add_child(_form_label("Value"))
	form_box.add_child(_label_line_edit(node))
	form_box.add_child(_form_label("Type"))
	var ob: OptionButton = OptionButton.new()
	ob.add_item("float")
	ob.add_item("int")
	ob.selected = 1 if node.type == "int" else 0
	skin.style_option(ob)
	var _is: int = ob.item_selected.connect(func(i: int) -> void:
		node.type = "int" if i == 1 else "float"
		committed.emit())
	form_box.add_child(ob)


func _property_form(node: ConditionNodeData, test_vars: Dictionary) -> void:
	form_box.add_child(_form_label("Tracks variable"))
	var ob: OptionButton = OptionButton.new()
	skin.style_option(ob)
	var by_id: Dictionary = {}
	var next_id: int = 0
	var grouped: Dictionary = variables_by_category.call()
	for cat: String in grouped.keys():
		ob.add_separator(cat)
		for vn: String in grouped[cat]:
			ob.add_item("%s - %s" % [vn, str(var_type.call(vn))], next_id)
			by_id[next_id] = vn
			if vn == node.label:
				ob.selected = ob.item_count - 1
			next_id += 1
	ob.add_separator("")
	ob.add_item("+ new variable...", -1)
	var _is: int = ob.item_selected.connect(func(i: int) -> void:
		var picked: int = ob.get_item_id(i)
		if picked < 0:
			var nm: String = await prompt.call("New variable",
				"Add a test variable to track.", "my_variable")
			if nm == "":
				refresh_requested.emit()
				return
			if not test_vars.has(nm):
				test_vars[nm] = AntSchema.default_for(nm)
			node.label = nm
			node.type = AntSchema.type_of(nm)
			vars_changed.emit()
			committed.emit()
			return
		var chosen: String = by_id[picked]
		node.label = chosen
		node.type = AntSchema.type_of(chosen)
		committed.emit())
	form_box.add_child(ob)


func _compare_form(node: ConditionNodeData) -> void:
	form_box.add_child(_form_label("Comparison"))
	var ob: OptionButton = OptionButton.new()
	skin.style_option(ob)
	for i: int in ConditionNodeData.CMP_OPS.size():
		var op: String = ConditionNodeData.CMP_OPS[i]
		ob.add_item(ConditionNodeData.op_name(op), i)
		if op == node.op:
			ob.selected = i
	var _is: int = ob.item_selected.connect(func(i: int) -> void:
		node.op = ConditionNodeData.CMP_OPS[i]
		committed.emit())
	form_box.add_child(ob)
	form_box.add_child(_form_label("Operands"))
	form_box.add_child(
		_form_help("Double-click the node to enter and edit its two values."))


func _logic_form(node: ConditionNodeData) -> void:
	form_box.add_child(_form_label("Name"))
	form_box.add_child(_label_line_edit(node))
	form_box.add_child(_form_label("Gate"))
	var ob: OptionButton = OptionButton.new()
	skin.style_option(ob)
	for i: int in ConditionNodeData.LOGIC_OPS.size():
		var op: String = ConditionNodeData.LOGIC_OPS[i]
		ob.add_item(ConditionNodeData.op_name(op), i)
		if op == node.op:
			ob.selected = i
	var _is: int = ob.item_selected.connect(func(i: int) -> void:
		node.op = ConditionNodeData.LOGIC_OPS[i]
		node.label = node.op.to_upper()
		committed.emit())
	form_box.add_child(ob)


func _timing_form(node: ConditionNodeData) -> void:
	form_box.add_child(_form_label("Behaviour"))
	var ob: OptionButton = OptionButton.new()
	skin.style_option(ob)
	for i: int in ConditionNodeData.TIMING_OPS.size():
		var op: String = ConditionNodeData.TIMING_OPS[i]
		ob.add_item(ConditionNodeData.op_name(op), i)
		if op == node.op:
			ob.selected = i
	var _is: int = ob.item_selected.connect(func(i: int) -> void:
		node.op = ConditionNodeData.TIMING_OPS[i]
		committed.emit())
	form_box.add_child(ob)
	form_box.add_child(_form_label("Seconds"))
	var spin: SpinBox = SpinBox.new()
	spin.min_value = 0.0
	spin.max_value = 600.0
	spin.step = 0.1
	spin.value = node.seconds
	spin.editable = node.op != "latch"
	skin.style_spin(spin)
	var _vc: int = spin.value_changed.connect(func(v: float) -> void:
		node.seconds = maxf(0.0, v)
		committed.emit())
	form_box.add_child(spin)
	form_box.add_child(
		_form_help(str(ConditionNodeData.TIMING_HELP.get(node.op, ""))))


func _query_form(node: ConditionNodeData) -> void:
	form_box.add_child(_form_label("Measure"))
	var measure_ob: OptionButton = OptionButton.new()
	skin.style_option(measure_ob)
	for i: int in ConditionNodeData.QUERY_MEASURES.size():
		var m: String = ConditionNodeData.QUERY_MEASURES[i]
		measure_ob.add_item(str(ConditionNodeData.MEASURE_WORDS.get(m, m)), i)
		if m == node.op:
			measure_ob.selected = i
	var _mc: int = measure_ob.item_selected.connect(func(i: int) -> void:
		node.op = ConditionNodeData.QUERY_MEASURES[i]
		node.type = node.measure_type()
		committed.emit()
		vars_changed.emit())
	form_box.add_child(measure_ob)
	form_box.add_child(_form_label("Subject"))
	var subject_ob: OptionButton = OptionButton.new()
	skin.style_option(subject_ob)
	var subjects: Array = ConditionNodeData.SUBJECT_WORDS.keys()
	for i: int in subjects.size():
		var s: String = subjects[i]
		subject_ob.add_item(str(ConditionNodeData.SUBJECT_WORDS[s]), i)
		if s == node.subject:
			subject_ob.selected = i
	var _sc: int = subject_ob.item_selected.connect(func(i: int) -> void:
		node.subject = subjects[i]
		committed.emit()
		vars_changed.emit())
	form_box.add_child(subject_ob)
	form_box.add_child(_form_label("Scope"))
	var scope_ob: OptionButton = OptionButton.new()
	skin.style_option(scope_ob)
	for i: int in ConditionNodeData.QUERY_SCOPES.size():
		var sc: String = ConditionNodeData.QUERY_SCOPES[i]
		scope_ob.add_item("%s (%s)" % [
			str(ConditionNodeData.SCOPE_WORDS.get(sc, sc)),
			str(trim_range.call(Ant.scope_range(sc)))], i)
		if sc == node.scope:
			scope_ob.selected = i
	var _oc: int = scope_ob.item_selected.connect(func(i: int) -> void:
		node.scope = ConditionNodeData.QUERY_SCOPES[i]
		committed.emit()
		vars_changed.emit())
	form_box.add_child(scope_ob)
	form_box.add_child(_form_label("Reads variable"))
	var key_le: LineEdit = LineEdit.new()
	key_le.text = node.var_key()
	key_le.editable = false
	skin.style_line_edit(key_le)
	key_le.add_theme_color_override("font_uneditable_color", COLORS["faint"])
	form_box.add_child(key_le)


func _vector_form(node: ConditionNodeData) -> void:
	form_box.add_child(_form_label("Operation"))
	var ob: OptionButton = OptionButton.new()
	skin.style_option(ob)
	for i: int in ConditionNodeData.VECTOR_OPS.size():
		var vop: String = ConditionNodeData.VECTOR_OPS[i]
		ob.add_item(str(ConditionNodeData.VECTOR_NAMES.get(vop, vop)), i)
		if vop == node.op:
			ob.selected = i
	var _is: int = ob.item_selected.connect(func(i: int) -> void:
		node.op = ConditionNodeData.VECTOR_OPS[i]
		node.type = ConditionNodeData.vector_type_of(node.op)
		committed.emit())
	form_box.add_child(ob)
	if node.op == "const":
		form_box.add_child(_form_label("Value"))
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(_vec_spin(node.vec.x, func(v: float) -> void:
			node.vec.x = v
			committed.emit()))
		row.add_child(_vec_spin(node.vec.y, func(v: float) -> void:
			node.vec.y = v
			committed.emit()))
		form_box.add_child(row)
	form_box.add_child(
		_form_help(str(ConditionNodeData.VECTOR_HELP.get(node.op, ""))))


# ============================================================================
# Shared bits
# ============================================================================
## Free-text label editor used by literal and logic nodes: soft repaint while
## typing, full commit on submit or focus loss.
func _label_line_edit(node: ConditionNodeData) -> LineEdit:
	var le: LineEdit = LineEdit.new()
	le.text = node.label
	skin.style_line_edit(le)
	var _tc: int = le.text_changed.connect(func(t: String) -> void:
		node.label = t
		insp_title.text = node.display_label()
		var w: GraphNodeWidget = widgets.get(node.id)
		if w:
			w.refresh()
		soft_changed.emit())
	var _ts: int = le.text_submitted.connect(func(_t: String) -> void:
		committed.emit())
	var _fe: int = le.focus_exited.connect(func() -> void:
		committed.emit())
	return le


func _vec_spin(value: float, on_change: Callable) -> SpinBox:
	var spin: SpinBox = SpinBox.new()
	spin.min_value = -9999.0
	spin.max_value = 9999.0
	spin.step = 0.1
	spin.value = value
	skin.style_spin(spin)
	var _vc: int = spin.value_changed.connect(on_change)
	return spin


func _form_label(p_text: String) -> Label:
	return skin.tiny_label(p_text.to_upper(), COLORS["faint"], 9)


func _form_help(p_text: String) -> Label:
	var help: Label = Label.new()
	help.text = p_text
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_font_size_override("font_size", skin.fs(11))
	help.add_theme_color_override("font_color", COLORS["faint"])
	return help
