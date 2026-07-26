class_name ConditionGraphEditor
extends Control
## Runtime condition-graph editor scene.
##
## A level's wired logic is the child list of the focus gate. Nodes can also sit
## on the canvas *unwired* (see [member loose]) - dropped in from the Conditions
## library or detached - and only join the tree once the user drags a wire from
## their output port into a gate or the Output rail.

const COLORS: Dictionary = {
	"bg": Color("0a0f14"), "grid": Color(0.47, 0.65, 0.76, 0.055),
	"panel": Color("0e151d"), "surface": Color("141e28"), "surface_hi": Color("1a2632"),
	"line": Color("243444"), "text": Color("e7eef4"), "dim": Color("8ea0b0"),
	"faint": Color("566878"), "logic": Color("38d3c2"), "compare": Color("f2b45c"),
	"property": Color("78d67e"), "literal": Color("b596f2"), "focus": Color("e7eef4"),
	"sel": Color("5ab0ff"), "true": Color("4bd88a"), "false": Color("ff6274"),
	"timing": Color("ff7eb6"), "query": Color("ff8f5e"),
	"vector": Color("7fd7ff"),
}

#region constants
## Reserved key inside a layer's position map holding the output rail's spot.
const RAIL_KEY: String = "#rail"
const V_GAP: float = 24.0       # vertical gap between sibling subtrees
const GUTTER: float = 56.0      # left gutter for auto-layout
const COL_GAP: float = 70.0     # horizontal gap between a parent and its children
const RAIL_W: float = 130.0
const RAIL_H: float = 112.0
const CLICK_SLOP: float = 4.0
const SINGLE_CLICK_DELAY: float = 0.27
const MIN_ZOOM: float = 0.4
const MAX_ZOOM: float = 2.0
const MIN_UI_SCALE: float = 0.75
const MAX_UI_SCALE: float = 2.5
## Height the layout was authored against; used to derive an automatic scale.
const DESIGN_HEIGHT: float = 900.0
const EDGE_PAD: float = 24.0     # keep the layer this far off the canvas origin
const REVEAL_PAD: float = 32.0   # breathing room when scrolling something into view
## Payload tag for library -> canvas drag and drop.
const DRAG_CONDITION: String = "chem_ants/condition_group"
const UI_SCALE_STEP: float = 0.05

#endregion



enum DragMode { NONE, NODE_PENDING, NODE, MARQUEE_PENDING, MARQUEE, PAN, WIRE, PANEL }

const PANEL_EDGE: float = 8.0
var drag_panel: PanelContainer = null
var panel_grab: Vector2 = Vector2.ZERO
## instance id -> true, for panels that have been detached from their anchors.
var free_panels: Dictionary = {}
## Set by an expand/collapse so the next rebuild is allowed to push subtrees
## apart. Plain rebuilds leave hand-placed cards exactly where they are.
var _needs_room: bool = false
#region document state
var behavior_title: String = "Engage Target"
var tree_root: ConditionNodeData
var path: Array[ConditionNodeData] = []
var selection: Dictionary = {}          # id -> true
var gate_selected: bool = false
## Live expansion set for the current layer. Swapped in and out of
## [member expanded_by_layer] so entering a gate never disturbs the level you
## came from.
var expanded: Dictionary = {}           # id -> true
var expanded_by_layer: Dictionary = {}  # layer id -> {node id: true}
var prev_visible: Dictionary = {}       # id -> true
var spotlight: Variant = null           # null | Dictionary id -> true
var positions: Dictionary = {}          # layer id -> {node id: Vector2}
var loose: Dictionary = {}
var test_vars: Dictionary = {}
var clipboard: Array[ConditionNodeData] = []
var groups: Array[Dictionary] = []      # {"id", "name", "root": ConditionNodeData}
var dirty_pkg: Variant = null           # null | {"node", "group"}
var zoom: float = 1.0
var content_size: Vector2 = Vector2(100, 100)
## True while any timing node exists, which puts the editor into live ticking.
var live: bool = false
#endregion

#region render state
var widgets: Dictionary = {}            # id -> GraphNodeWidget
var node_pos: Dictionary = {}           # id -> Vector2 (layout target positions)
var visible_nodes: Array[ConditionNodeData] = []
var parent_of: Dictionary = {}          # id -> ConditionNodeData (null = unwired root)
var ui_font: Font
#endregion

#region interaction state
var drag_mode: DragMode = DragMode.NONE
var drag_widget: GraphNodeWidget = null
var drag_button: MouseButton = MOUSE_BUTTON_LEFT
var drag_start_screen: Vector2 = Vector2.ZERO
var drag_start_world: Vector2 = Vector2.ZERO
var drag_move_ids: Array[String] = []
var drag_starts: Dictionary = {}
var drag_was_double: bool = false
var drag_was_ctrl: bool = false
var pan_start_pos: Vector2 = Vector2.ZERO
var wire_node: ConditionNodeData = null
var wire_dir: String = "out"
var wire_from: Vector2 = Vector2.ZERO
var marquee_add: bool = false
var marquee_base: Dictionary = {}
var _click_token: int = 0
var _nav_tween: Tween = null
var _boot_done: bool = false
#endregion


signal _modal_done(text: String)

@onready var stage: Control = %Stage
@onready var grid_layer: Control = %GridLayer
@onready var world: Control = %World
@onready var trace_layer: TraceLayer = %TraceLayer
@onready var nodes_layer: Control = %NodesLayer
@onready var marquee: Panel = %Marquee
@onready var behavior_label: Label = %BehaviorName
@onready var crumbs_box: HBoxContainer = %Crumbs
@onready var zoom_out_btn: Button = %ZoomOut
@onready var zoom_label_btn: Button = %ZoomLabel
@onready var zoom_in_btn: Button = %ZoomIn
@onready var arrange_btn: Button = %ArrangeBtn
@onready var cond_btn: Button = %CondBtn
@onready var vars_btn: Button = %VarsBtn
@onready var back_btn: Button = %BackBtn
@onready var library_panel: PanelContainer = %LibraryPanel
@onready var lib_close: Button = %LibClose
@onready var group_list: VBoxContainer = %GroupList
@onready var legend_box: HBoxContainer = %Legend
@onready var vars_panel: PanelContainer = %VarsPanel
@onready var vars_close: Button = %VarsClose
@onready var vars_list: VBoxContainer = %VarsList
@onready var inspector_panel: PanelContainer = %InspectorPanel
@onready var insp_glyph: Label = %InspGlyph
@onready var insp_title: Label = %InspTitle
@onready var insp_empty: Label = %InspEmpty
@onready var form_box: VBoxContainer = %FormBox
@onready var single_row: HBoxContainer = %SingleRow
@onready var copy_btn: Button = %CopyBtn
@onready var delete_btn: Button = %DeleteBtn
@onready var multi_box: VBoxContainer = %MultiBox
@onready var multi_count: Label = %MultiCount
@onready var save_cond_btn: Button = %SaveCondBtn
@onready var copy_btn_m: Button = %CopyBtnM
@onready var delete_btn_m: Button = %DeleteBtnM
@onready var pkg_bar: PanelContainer = %PkgBar
@onready var pkg_label: Label = %PkgLabel
@onready var pkg_update_btn: Button = %PkgUpdate
@onready var pkg_new_btn: Button = %PkgNew
@onready var pkg_keep_btn: Button = %PkgKeep
@onready var toast_panel: PanelContainer = %Toast
@onready var toast_label: Label = %ToastLabel
@onready var modal_layer: Control = %ModalLayer
@onready var modal_scrim: ColorRect = %Scrim
@onready var modal_title: Label = %ModalTitle
@onready var modal_desc: Label = %ModalDesc
@onready var modal_input: LineEdit = %ModalInput
@onready var modal_cancel: Button = %ModalCancel
@onready var modal_save: Button = %ModalSave
@onready var ui_scale_slider: HSlider = %UiScale
@onready var ui_scale_label: Label = %UiScaleLabel

var rail: OutputRailWidget = null
var _toast_tween: Tween = null
var ui_scale: float = 1.0



# ============================================================================
# Lifecycle
# ============================================================================
func _ready() -> void:
	ui_font = get_theme_default_font()
	_check_glyph_coverage()
	ConditionLibrary.dev_reset_user_data()
	_build_sample_document()

	# Graph state first: _build_viewport() is unusable without it.
	path = [tree_root] as Array[ConditionNodeData]
	expanded = _layer_expansion(tree_root.id)

	_load_library()
	_apply_styles()
	_connect_chrome()
	rail = OutputRailWidget.new(COLORS, ui_font)
	var _rc: int = rail.rail_clicked.connect(_on_rail_clicked)
	var _rp: int = rail.rail_port_pressed.connect(_on_rail_port_pressed)
	world.add_child(rail)
	world.move_child(rail, world.get_child_count() - 1)
	behavior_label.text = behavior_title
	var _gd: int = grid_layer.draw.connect(_draw_grid)

	resized.connect(_on_editor_resized)
	_boot_done = true
	_place_back_button()
	_setup_movable_panels()
	_setup_ui_scale()
	call_deferred("_render_all")

func _on_editor_resized() -> void:
	for p: PanelContainer in [library_panel, vars_panel, inspector_panel]:
		_clamp_panel(p)
## Back reads as "up out of here", so it belongs immediately left of the trail
## it walks back along, not stranded at the far end of the toolbar.
func _place_back_button() -> void:
	var bar: HBoxContainer = back_btn.get_parent() as HBoxContainer
	if bar == null:
		return
	bar.move_child(back_btn, crumbs_box.get_index())
func _check_glyph_coverage() -> void:
	var needed: String = "\u2227\u2228\u00ac\u2295\u2264\u2265\u2260\u25c6\u25b8\u25be\u25a3\u25ce\u00d7\u2220\u2212\u21bb\u00fb\u03b8\u00b7"	
	for i: int in needed.length():
		if not ui_font.has_char(needed.unicode_at(i)):
			ConditionNodeData.ascii_mode = true
			return


func _build_sample_document() -> void:
	tree_root = ConditionNodeData.make("logic", "and", "bool", "deliver food", [
		ConditionNodeData.make("property", "", "bool", "is_carrying_food"),
		ConditionNodeData.timer("hold", 2.5, [
			ConditionNodeData.sense("exists", "food", "reach"),
		]),
		ConditionNodeData.make("compare", "lt", "bool", "", [
			ConditionNodeData.sense("distance", "colony", "smell"),
			ConditionNodeData.make("literal", "", "float", "40.0"),
		]),
		ConditionNodeData.make("logic", "not", "bool", "not resting", [
			ConditionNodeData.make("property", "", "bool", "is_resting"),
		]),
	])
	test_vars = {}
	_seed_all_vars()


## Make sure every schema variable and every variable the graph reads exists.
func _seed_all_vars() -> void:
	for v: Dictionary in AntSchema.base_variables():
		if not test_vars.has(v["name"]):
			test_vars[v["name"]] = v["default"]
	tree_root.seed_vars(test_vars)
	for n: ConditionNodeData in _all_loose_roots():
		n.seed_vars(test_vars)


## Restore the saved library, or generate the starter set and write it to user://
## so the defaults are ordinary saved conditions from then on.
func _load_library() -> void:
	groups = ConditionLibrary.load_groups()
	if not groups.is_empty():
		print_rich("[color=cyan]Condition library: loaded %d saved condition(s) from %s.[/color]"
			% [groups.size(), ConditionLibrary.SAVE_PATH])
		return
	groups = ConditionLibrary.default_groups()
	_persist_library()
	print_rich("[color=cyan]Condition library: generated %d starter condition(s) and saved them to %s.[/color]"
		% [groups.size(), ConditionLibrary.SAVE_PATH])


func _persist_library() -> void:
	var err: Error = ConditionLibrary.save_groups(groups)
	if err != OK:
		push_error("Condition library: save failed (error %d)." % err)


# ============================================================================
# Styling helpers
# ============================================================================
func _panel_style(bg: Color, border: Color, radius: int = 13, margin: int = 13) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 14
	sb.shadow_offset = Vector2(0, 8)
	return sb


func _style_button(btn: Button, kind: String = "normal") -> void:
	var normal: StyleBoxFlat = StyleBoxFlat.new()
	normal.set_corner_radius_all(8)
	normal.set_border_width_all(1)
	normal.content_margin_left = 11
	normal.content_margin_right = 11
	normal.content_margin_top = 7
	normal.content_margin_bottom = 7
	match kind:
		"primary":
			normal.bg_color = COLORS["sel"]
			normal.border_color = COLORS["sel"]
			btn.add_theme_color_override("font_color", Color("04121f"))
			btn.add_theme_color_override("font_hover_color", Color("04121f"))
			btn.add_theme_color_override("font_pressed_color", Color("04121f"))
		"danger":
			normal.bg_color = COLORS["surface"]
			normal.border_color = COLORS["line"].lerp(COLORS["false"], 0.3)
			btn.add_theme_color_override("font_color", Color("ff8a95"))
			btn.add_theme_color_override("font_hover_color", Color("ffa9b1"))
		"flat":
			normal.bg_color = Color(0, 0, 0, 0)
			normal.border_color = Color(0, 0, 0, 0)
			btn.add_theme_color_override("font_color", COLORS["faint"])
			btn.add_theme_color_override("font_hover_color", COLORS["text"])
		_:
			normal.bg_color = COLORS["surface"]
			normal.border_color = COLORS["line"]
			btn.add_theme_color_override("font_color", COLORS["text"])
			btn.add_theme_color_override("font_hover_color", COLORS["text"])
	var hover: StyleBoxFlat = normal.duplicate()
	if kind == "primary":
		hover.bg_color = Color("7cc1ff")
	elif kind == "flat":
		hover.bg_color = COLORS["surface_hi"]
	else:
		hover.bg_color = COLORS["surface_hi"]
		hover.border_color = Color("33475a")
	var pressed: StyleBoxFlat = hover.duplicate()
	pressed.bg_color = hover.bg_color.darkened(0.08)
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	var disabled: StyleBoxFlat = normal.duplicate()
	disabled.bg_color = Color(normal.bg_color, 0.35)
	btn.add_theme_stylebox_override("disabled", disabled)
	btn.add_theme_color_override("font_disabled_color", COLORS["faint"])
	btn.add_theme_font_size_override("font_size", 12)
	btn.focus_mode = Control.FOCUS_NONE


func _style_line_edit(le: LineEdit) -> void:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = COLORS["panel"]
	sb.border_color = COLORS["line"]
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(9)
	var focus: StyleBoxFlat = sb.duplicate()
	focus.border_color = COLORS["sel"]
	le.add_theme_stylebox_override("normal", sb)
	le.add_theme_stylebox_override("focus", focus)
	le.add_theme_color_override("font_color", COLORS["text"])
	le.add_theme_font_size_override("font_size", 13)


func _style_spin(spin: SpinBox) -> void:
	_style_line_edit(spin.get_line_edit())
	spin.add_theme_font_size_override("font_size", 13)


static func _trim_range(v: float) -> String:
	return "%d units" % roundi(v)


func _style_option(ob: OptionButton) -> void:
	_style_button(ob)
	ob.add_theme_font_size_override("font_size", 13)


func _tiny_label(p_text: String, p_color: Color, font_size: int = 9) -> Label:
	var l: Label = Label.new()
	l.text = p_text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", p_color)
	return l


func _apply_styles() -> void:
	var top_sb: StyleBoxFlat = StyleBoxFlat.new()
	top_sb.bg_color = COLORS["panel"]
	top_sb.border_width_bottom = 1
	top_sb.border_color = COLORS["line"]
	top_sb.content_margin_left = 16
	top_sb.content_margin_right = 16
	top_sb.content_margin_top = 8
	top_sb.content_margin_bottom = 8
	($TopBar as PanelContainer).add_theme_stylebox_override("panel", top_sb)

	for p: PanelContainer in [library_panel, vars_panel, inspector_panel]:
		p.add_theme_stylebox_override("panel",
			_panel_style(Color(COLORS["surface"], 0.94), COLORS["line"]))
	pkg_bar.add_theme_stylebox_override("panel",
		_panel_style(COLORS["surface"], COLORS["sel"], 11, 10))
	toast_panel.add_theme_stylebox_override("panel",
		_panel_style(COLORS["surface_hi"], COLORS["line"], 10, 11))
	(%ModalPanel as PanelContainer).add_theme_stylebox_override("panel",
		_panel_style(COLORS["surface"], COLORS["line"], 14, 18))

	for b: Button in [zoom_out_btn, zoom_in_btn, arrange_btn, cond_btn, vars_btn,
			back_btn, copy_btn, copy_btn_m, pkg_keep_btn, modal_cancel]:
		_style_button(b)
	for b: Button in [delete_btn, delete_btn_m]:
		_style_button(b, "danger")
	for b: Button in [save_cond_btn, pkg_update_btn, modal_save]:
		_style_button(b, "primary")
	_style_button(pkg_new_btn)
	for b: Button in [zoom_label_btn, lib_close, vars_close]:
		_style_button(b, "flat")
	_style_line_edit(modal_input)
	back_btn.text = ("\u2190 Back" if not ConditionNodeData.ascii_mode else "< Back")

	# Legend swatches.
	for entry: Array in [["logic", "logic"], ["compare", "compare"],
			["timing", "timing"], ["query", "sense"],
			["property", "prop"], ["literal", "const"]]:
		var h: HBoxContainer = HBoxContainer.new()
		h.add_theme_constant_override("separation", 5)
		var sw: ColorRect = ColorRect.new()
		sw.custom_minimum_size = Vector2(9, 9)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sw.color = COLORS[entry[0]]
		h.add_child(sw)
		h.add_child(_tiny_label(entry[1], COLORS["dim"], 10))
		legend_box.add_child(h)


func _connect_chrome() -> void:
	stage.gui_input.connect(_on_stage_gui_input)
	stage.set_drag_forwarding(
		func(_at: Vector2) -> Variant: return null,
		_stage_can_drop_data,
		_stage_drop_data)
	zoom_in_btn.pressed.connect(func() -> void: _set_zoom(zoom * 1.2))
	zoom_out_btn.pressed.connect(func() -> void: _set_zoom(zoom / 1.2))
	zoom_label_btn.pressed.connect(func() -> void: _set_zoom(1.0))
	arrange_btn.pressed.connect(_on_arrange)
	back_btn.pressed.connect(_go_back)
	cond_btn.toggled.connect(func(on: bool) -> void: library_panel.visible = on)
	vars_btn.toggled.connect(func(on: bool) -> void: vars_panel.visible = on)
	lib_close.pressed.connect(func() -> void: cond_btn.button_pressed = false)
	vars_close.pressed.connect(func() -> void: vars_btn.button_pressed = false)
	copy_btn.pressed.connect(_copy_selection)
	copy_btn_m.pressed.connect(_copy_selection)
	delete_btn.pressed.connect(_delete_selection)
	delete_btn_m.pressed.connect(_delete_selection)
	save_cond_btn.pressed.connect(_save_condition)
	pkg_update_btn.pressed.connect(_pkg_update_everywhere)
	pkg_new_btn.pressed.connect(_pkg_save_as_new)
	pkg_keep_btn.pressed.connect(_pkg_keep_here)
	modal_cancel.pressed.connect(func() -> void: _modal_done.emit(""))
	modal_save.pressed.connect(func() -> void:
		_modal_done.emit(modal_input.text.strip_edges()))
	modal_input.text_submitted.connect(func(t: String) -> void:
		_modal_done.emit(t.strip_edges()))
	modal_scrim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			_modal_done.emit(""))


func _draw_grid() -> void:
	var s: Vector2 = grid_layer.size
	var step: float = 34.0
	var x: float = 0.0
	while x < s.x:
		grid_layer.draw_line(Vector2(x, 0), Vector2(x, s.y), COLORS["grid"], 1.0)
		x += step
	var y: float = 0.0
	while y < s.y:
		grid_layer.draw_line(Vector2(0, y), Vector2(s.x, y), COLORS["grid"], 1.0)
		y += step


# ============================================================================
# Core helpers
# ============================================================================
func _focus() -> ConditionNodeData:
	assert(not path.is_empty(), "_focus(): path emptied - check _go_to()/_go_back().")
	return path[path.size() - 1]


## Depth-first lookup across the wired tree *and* every unwired root.
## Unwired roots report a null parent.
func _find(id: String) -> Dictionary:
	var r: Dictionary = tree_root.find_with_parent(id)
	if not r.is_empty():
		return r
	for key: String in loose.keys():
		var roots: Array[ConditionNodeData] = loose[key]
		for n: ConditionNodeData in roots:
			var lr: Dictionary = n.find_with_parent(id)
			if not lr.is_empty():
				return lr
	return {}


func _layer_positions() -> Dictionary:
	var key: String = _focus().id
	if not positions.has(key):
		positions[key] = {}
	return positions[key]


## Expansion set stored for a layer. `expanded` mirrors the current one.
func _layer_expansion(layer_id: String) -> Dictionary:
	if not expanded_by_layer.has(layer_id):
		expanded_by_layer[layer_id] = {}
	return expanded_by_layer[layer_id]


## Replace the current layer's expansion set, keeping the store in sync.
func _set_expansion(next: Dictionary) -> void:
	expanded = next
	expanded_by_layer[_focus().id] = next


## Remember the current layer's expansion, then adopt the new focus's.
func _switch_expansion_to(layer_id: String) -> void:
	expanded_by_layer[_focus().id] = expanded
	expanded = _layer_expansion(layer_id)


func _layer_loose() -> Array[ConditionNodeData]:
	var key: String = _focus().id
	if not loose.has(key):
		var fresh: Array[ConditionNodeData] = []
		loose[key] = fresh
	return loose[key]


func _all_loose_roots() -> Array[ConditionNodeData]:
	var out: Array[ConditionNodeData] = []
	for key: String in loose.keys():
		var roots: Array[ConditionNodeData] = loose[key]
		for n: ConditionNodeData in roots:
			out.append(n)
	return out


func _to_world(global_pos: Vector2) -> Vector2:
	return world.get_global_transform().affine_inverse() * global_pos


func _toast(msg: String) -> void:
	toast_label.text = msg
	toast_panel.visible = true
	toast_panel.modulate.a = 1.0
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_interval(1.7)
	_toast_tween.tween_property(toast_panel, "modulate:a", 0.0, 0.2)
	_toast_tween.tween_callback(func() -> void: toast_panel.visible = false)


## Modal name prompt; returns "" on cancel.
func _prompt(p_title: String, p_desc: String, p_default: String) -> String:
	modal_title.text = p_title
	modal_desc.text = p_desc
	modal_input.text = p_default
	modal_layer.visible = true
	modal_input.grab_focus()
	modal_input.select_all()
	var result: String = await _modal_done
	modal_layer.visible = false
	return result


# ============================================================================
# Rendering
# ============================================================================
func _render_all() -> void:
	_draw_crumbs()
	back_btn.disabled = path.size() <= 1
	_build_viewport(true)
	_render_library()
	_render_vars()
	_update_inspector()


func _draw_crumbs() -> void:
	for c: Node in crumbs_box.get_children():
		crumbs_box.remove_child(c)
		c.queue_free()
	var mk: Callable = func(p_text: String, index: int, current: bool) -> void:
		var b: Button = Button.new()
		b.text = p_text
		b.disabled = current
		_style_button(b, "flat" if not current else "normal")
		b.add_theme_font_size_override("font_size", 12)
		if current:
			b.add_theme_color_override("font_disabled_color", COLORS["text"])
		else:
			b.pressed.connect(func() -> void: _go_to(index))
		crumbs_box.add_child(b)
	mk.call("entry", 0, path.size() == 1)
	for i: int in range(1, path.size()):
		var sep: Label = _tiny_label(">" if ConditionNodeData.ascii_mode else "\u203a",
			COLORS["faint"], 11)
		sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		crumbs_box.add_child(sep)
		mk.call(path[i].display_label(), i, i == path.size() - 1)


func _walk_visible(n: ConditionNodeData, parent: ConditionNodeData) -> void:
	visible_nodes.append(n)
	parent_of[n.id] = parent
	if expanded.has(n.id):
		for c: ConditionNodeData in n.children:
			_walk_visible(c, n)


func _sub_height(n: ConditionNodeData) -> float:
	var h: float = widgets[n.id].size.y
	if not expanded.has(n.id) or n.children.is_empty():
		return h
	var s: float = 0.0
	for i: int in n.children.size():
		s += _sub_height(n.children[i]) + (V_GAP if i > 0 else 0.0)
	return maxf(h, s)


func _place_tree(n: ConditionNodeData, right_edge: float, top: float) -> void:
	var w: GraphNodeWidget = widgets[n.id]
	var s: float = _sub_height(n)
	var lp: Dictionary = _layer_positions()
	var pos: Vector2
	if lp.has(n.id):
		pos = lp[n.id]
	else:
		pos = Vector2(right_edge - w.size.x, top + s * 0.5 - w.size.y * 0.5)
	node_pos[n.id] = pos
	if expanded.has(n.id) and not n.children.is_empty():
		var kid_total: float = 0.0
		for i: int in n.children.size():
			kid_total += _sub_height(n.children[i]) + (V_GAP if i > 0 else 0.0)
		var cy: float = pos.y + w.size.y * 0.5 - kid_total * 0.5
		for c: ConditionNodeData in n.children:
			_place_tree(c, pos.x - COL_GAP, cy)
			cy += _sub_height(c) + V_GAP


func _build_viewport(skip_anim: bool = false) -> void:
	if not _boot_done or path.is_empty() or stage.size.x < 2:
		return
	var old_pos: Dictionary = node_pos.duplicate()
	for c: Node in nodes_layer.get_children():
		nodes_layer.remove_child(c)
		c.queue_free()
	widgets.clear()
	node_pos.clear()
	visible_nodes.clear()
	parent_of.clear()
	var f: ConditionNodeData = _focus()
	for c: ConditionNodeData in f.children:
		_walk_visible(c, f)
	var tree_count: int = visible_nodes.size()
	var loose_roots: Array[ConditionNodeData] = _layer_loose()
	for n: ConditionNodeData in loose_roots:
		_walk_visible(n, null)

	var appear_ids: Array[String] = []
	for n: ConditionNodeData in visible_nodes:
		var w: GraphNodeWidget = GraphNodeWidget.new()
		w.unconnected = parent_of[n.id] == null
		w.setup(n, COLORS, ui_font)
		w.pointer_pressed.connect(_on_widget_pressed)
		w.context_requested.connect(_on_widget_context)
		w.port_pressed.connect(_on_port_pressed)
		nodes_layer.add_child(w)
		widgets[n.id] = w
		if not skip_anim and not prev_visible.has(n.id):
			appear_ids.append(n.id)

	# Layout. Top-level cards (the focus gate's children plus any unwired roots)
	# own a remembered position, so a rebuild never shuffles them. Only a brand
	# new layer, a newly added card, or the Arrange button computes positions.
	var stage_size: Vector2 = stage.size
	_ensure_top_positions(f, loose_roots, stage_size)
	for c: ConditionNodeData in f.children:
		_place_tree(c, 0.0, 0.0)
	for n: ConditionNodeData in loose_roots:
		_place_tree(n, 0.0, 0.0)
	for n: ConditionNodeData in loose_roots:
		_place_tree(n, 0.0, 0.0)
	_make_room(f, loose_roots)
	# Extents. The rail follows the wired tree only, so dropping a card off to
	# the right doesn't drag the output with it.
	var lp: Dictionary = _layer_positions()
	var tree_r: float = GUTTER
	var max_r: float = GUTTER
	var max_b: float = 44.0
	for i: int in visible_nodes.size():
		var n: ConditionNodeData = visible_nodes[i]
		var right: float = node_pos[n.id].x + widgets[n.id].size.x
		var bottom: float = node_pos[n.id].y + widgets[n.id].size.y
		max_r = maxf(max_r, right)
		max_b = maxf(max_b, bottom)
		if i < tree_count:
			tree_r = maxf(tree_r, right)

	var rail_pos: Vector2 = lp.get(RAIL_KEY, Vector2(
		stage_size.x - 150.0, stage_size.y * 0.5 - RAIL_H * 0.5))
	rail_pos.x = maxf(rail_pos.x, tree_r + 90.0)
	lp[RAIL_KEY] = rail_pos
	rail.position = rail_pos
	content_size = Vector2(
		maxf(stage_size.x, maxf(rail_pos.x + RAIL_W + 40.0, max_r + 60.0)),
		maxf(stage_size.y, maxf(max_b + 60.0, rail_pos.y + RAIL_H + 40.0)))
	world.size = content_size
	trace_layer.position = Vector2.ZERO
	trace_layer.size = content_size
	grid_layer.queue_redraw()
	_apply_zoom()
	_update_live_state()

	# Commit widget positions (animate movers / newcomers unless told to skip).
	for n: ConditionNodeData in visible_nodes:
		var w: GraphNodeWidget = widgets[n.id]
		w.expanded = expanded.has(n.id)
		var target: Vector2 = node_pos[n.id]
		if skip_anim:
			w.position = target
		elif old_pos.has(n.id):
			w.position = old_pos[n.id]
			if w.position.distance_to(target) > 0.5:
				var tw: Tween = create_tween()
				tw.tween_property(w, "position", target, 0.32) \
					.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			else:
				w.position = target
		else:
			w.position = target + Vector2(42, 0)
			w.modulate.a = 0.0
			var delay: float = appear_ids.find(n.id) * 0.028
			var tw: Tween = create_tween().set_parallel(true)
			tw.tween_property(w, "position", target, 0.3).set_delay(delay) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tw.tween_property(w, "modulate:a", 1.0, 0.28).set_delay(delay)
	prev_visible.clear()
	for n: ConditionNodeData in visible_nodes:
		prev_visible[n.id] = true
	_repaint()

## Keep an expansion legible: push overlapping subtrees apart, then shove the
## whole layer back inside the canvas if it grew off the left or top edge.
## Results are written to the layer store, so the shuffle is permanent.
func _make_room(f: ConditionNodeData, loose_roots: Array[ConditionNodeData]) -> void:
	var tops: Array[ConditionNodeData] = []
	for c: ConditionNodeData in f.children:
		tops.append(c)
	for n: ConditionNodeData in loose_roots:
		tops.append(n)
	if tops.is_empty():
		return
	if _needs_room:
		_needs_room = false
		_separate_subtrees(tops)
	_shift_into_canvas()


## Bounding box of everything currently drawn for this root.
func _subtree_rect(n: ConditionNodeData) -> Rect2:
	var out: Rect2 = Rect2()
	var started: bool = false
	for sid: String in _visible_subtree_ids(n.id):
		if not node_pos.has(sid) or not widgets.has(sid):
			continue
		var box: Rect2 = Rect2(node_pos[sid], (widgets[sid] as GraphNodeWidget).size)
		if started:
			out = out.merge(box)
		else:
			out = box
			started = true
	return out


func _shift_subtree(n: ConditionNodeData, delta: Vector2) -> void:
	if delta.is_zero_approx():
		return
	var lp: Dictionary = _layer_positions()
	for sid: String in _visible_subtree_ids(n.id):
		if node_pos.has(sid):
			node_pos[sid] = (node_pos[sid] as Vector2) + delta
		if lp.has(sid):
			lp[sid] = (lp[sid] as Vector2) + delta


## Top-down sweep: each subtree drops below anything it collides with.
func _separate_subtrees(tops: Array[ConditionNodeData]) -> void:
	var order: Array[ConditionNodeData] = tops.duplicate()
	order.sort_custom(func(a: ConditionNodeData, b: ConditionNodeData) -> bool:
		return _subtree_rect(a).position.y < _subtree_rect(b).position.y)
	var taken: Array[Rect2] = []
	for n: ConditionNodeData in order:
		var box: Rect2 = _subtree_rect(n)
		if box.size.y <= 0.0:
			continue
		var start_y: float = box.position.y
		var moved: bool = true
		var guard: int = 0
		while moved and guard < 8:
			moved = false
			guard += 1
			for other: Rect2 in taken:
				if box.intersects(other):
					box.position.y = other.end.y + V_GAP
					moved = true
		_shift_subtree(n, Vector2(0.0, box.position.y - start_y))
		taken.append(box)


## The canvas can grow right and down on its own, but nothing left of x = 0 is
## reachable, so the layer moves instead.
func _shift_into_canvas() -> void:
	var min_l: float = INF
	var min_t: float = INF
	for n: ConditionNodeData in visible_nodes:
		if not node_pos.has(n.id):
			continue
		var p: Vector2 = node_pos[n.id]
		min_l = minf(min_l, p.x)
		min_t = minf(min_t, p.y)
	if min_l == INF:
		return
	var delta: Vector2 = Vector2(maxf(0.0, EDGE_PAD - min_l), maxf(0.0, EDGE_PAD - min_t))
	if delta.is_zero_approx():
		return
	var lp: Dictionary = _layer_positions()
	for key: String in lp.keys():
		lp[key] = (lp[key] as Vector2) + delta
	for nid: String in node_pos.keys():
		node_pos[nid] = (node_pos[nid] as Vector2) + delta


## Pan the stage until `area` (world space) is on screen.
func _reveal_rect(area: Rect2) -> void:
	if area.size.x <= 0.0 or area.size.y <= 0.0:
		return
	var view_pos: Vector2 = -world.position / zoom
	var view_size: Vector2 = stage.size / zoom
	var target: Vector2 = world.position
	if area.position.x - REVEAL_PAD < view_pos.x:
		target.x += (view_pos.x - area.position.x + REVEAL_PAD) * zoom
	elif area.end.x + REVEAL_PAD > view_pos.x + view_size.x:
		target.x -= (area.end.x + REVEAL_PAD - view_pos.x - view_size.x) * zoom
	if area.position.y - REVEAL_PAD < view_pos.y:
		target.y += (view_pos.y - area.position.y + REVEAL_PAD) * zoom
	elif area.end.y + REVEAL_PAD > view_pos.y + view_size.y:
		target.y -= (area.end.y + REVEAL_PAD - view_pos.y - view_size.y) * zoom
	var lim: Vector2 = stage.size - content_size * zoom
	target.x = clampf(target.x, minf(0.0, lim.x), 0.0)
	target.y = clampf(target.y, minf(0.0, lim.y), 0.0)
	if target.is_equal_approx(world.position):
		return
	var tw: Tween = create_tween()
	tw.tween_property(world, "position", target, 0.28) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## Give every top-level card a stored position. An empty layer gets the full
## tidy tree layout; a layer that already has positions only places newcomers,
## which is what keeps existing cards still.
func _ensure_top_positions(f: ConditionNodeData, loose_roots: Array[ConditionNodeData],
		stage_size: Vector2) -> void:
	var tops: Array[ConditionNodeData] = []
	for c: ConditionNodeData in f.children:
		tops.append(c)
	for n: ConditionNodeData in loose_roots:
		tops.append(n)
	if tops.is_empty():
		return
	var lp: Dictionary = _layer_positions()
	var known: int = 0
	for t: ConditionNodeData in tops:
		if lp.has(t.id):
			known += 1
	if known == 0:
		_auto_layout_layer(f, loose_roots, stage_size)
		return
	if known == tops.size():
		return
	var bottom: float = 44.0
	for t: ConditionNodeData in tops:
		if lp.has(t.id):
			bottom = maxf(bottom, (lp[t.id] as Vector2).y + widgets[t.id].size.y)
	var y: float = bottom + V_GAP
	for t: ConditionNodeData in tops:
		if lp.has(t.id):
			continue
		lp[t.id] = Vector2(GUTTER, y)
		y += widgets[t.id].size.y + V_GAP


## Full tidy pass for one layer: the wired tree fans right-to-left and is
## centred, unwired roots stack underneath. Results are stored, so this is the
## only thing that ever moves an existing card.
func _auto_layout_layer(f: ConditionNodeData, loose_roots: Array[ConditionNodeData],
		stage_size: Vector2) -> void:
	var lp: Dictionary = _layer_positions()
	lp.clear()
	node_pos.clear()
	var total: float = 0.0
	for i: int in f.children.size():
		total += _sub_height(f.children[i]) + (V_GAP if i > 0 else 0.0)
	var tree_h: float = maxf(stage_size.y, total + 130.0)
	var col0: float = stage_size.x - 250.0
	var y: float = maxf(44.0, tree_h * 0.5 - total * 0.5)
	for r: ConditionNodeData in f.children:
		_place_tree(r, col0, y)
		y += _sub_height(r) + V_GAP

	var min_l: float = INF
	for n: ConditionNodeData in visible_nodes:
		if node_pos.has(n.id):
			min_l = minf(min_l, node_pos[n.id].x)
	if min_l != INF and absf(GUTTER - min_l) > 0.5:
		var shift: float = GUTTER - min_l
		for n: ConditionNodeData in visible_nodes:
			if node_pos.has(n.id):
				node_pos[n.id].x += shift

	var bottom: float = 44.0
	for n: ConditionNodeData in visible_nodes:
		if node_pos.has(n.id):
			bottom = maxf(bottom, node_pos[n.id].y + widgets[n.id].size.y)
	var ly: float = bottom + 40.0
	for n: ConditionNodeData in loose_roots:
		_place_tree(n, GUTTER + widgets[n.id].size.x, ly)
		_nudge_subtree_into_view(n)
		ly += _sub_height(n) + V_GAP

	for c: ConditionNodeData in f.children:
		lp[c.id] = node_pos[c.id]
	for n: ConditionNodeData in loose_roots:
		lp[n.id] = node_pos[n.id]
	var tree_r: float = GUTTER
	for c: ConditionNodeData in f.children:
		tree_r = maxf(tree_r, node_pos[c.id].x + widgets[c.id].size.x)
	lp[RAIL_KEY] = Vector2(maxf(stage_size.x - 150.0, tree_r + 90.0),
		tree_h * 0.5 - RAIL_H * 0.5)


## Shove an auto-placed subtree right if its expanded children ran off the left.
func _nudge_subtree_into_view(root_node: ConditionNodeData) -> void:
	var ids: Array[String] = _visible_subtree_ids(root_node.id)
	var lmin: float = INF
	for sid: String in ids:
		if node_pos.has(sid):
			lmin = minf(lmin, node_pos[sid].x)
	if lmin == INF or lmin >= 20.0:
		return
	var d: float = 20.0 - lmin
	for sid: String in ids:
		if node_pos.has(sid):
			node_pos[sid].x += d


func _apply_zoom() -> void:
	world.scale = Vector2(zoom, zoom)
	_clamp_pan()
	zoom_label_btn.text = "%d%%" % roundi(zoom * 100.0)


func _clamp_pan() -> void:
	var lim: Vector2 = stage.size - content_size * zoom
	world.position.x = clampf(world.position.x, minf(0.0, lim.x), 0.0)
	world.position.y = clampf(world.position.y, minf(0.0, lim.y), 0.0)


func _set_zoom(nz: float, stage_point: Variant = null) -> void:
	var sp: Vector2 = stage_point if stage_point != null else stage.size * 0.5
	var wp: Vector2 = (sp - world.position) / zoom
	zoom = clampf(nz, MIN_ZOOM, MAX_ZOOM)
	world.position = sp - wp * zoom
	_apply_zoom()


func _out_point(n: ConditionNodeData) -> Vector2:
	var w: GraphNodeWidget = widgets[n.id]
	return node_pos[n.id] + Vector2(w.size.x + 6.0, w.size.y * 0.5)


func _in_point(n: ConditionNodeData) -> Vector2:
	var w: GraphNodeWidget = widgets[n.id]
	return node_pos[n.id] + Vector2(-6.0, w.size.y * 0.5)


## Turn per-frame ticking on only while the document actually holds a timer.
func _update_live_state() -> void:
	var next: bool = tree_root.has_timing()
	if not next:
		for n: ConditionNodeData in _all_loose_roots():
			if n.has_timing():
				next = true
				break
	live = next
	set_process(live)


func _process(delta: float) -> void:
	if rail == null or visible_nodes.is_empty():
		return
	_repaint(delta)


func reset_timers() -> void:
	tree_root.reset_runtime()
	for n: ConditionNodeData in _all_loose_roots():
		n.reset_runtime()
	_repaint()


## Recompute evaluation, selection, spotlight and traces in one pass.
##
## Everything is ticked from the document roots through a single shared cache:
## a node is reachable via several ancestors, and a timer must only advance once
## per frame.
func _repaint(delta: float = 0.0) -> void:
	var eval_cache: Dictionary = {}
	var _root_value: Dictionary = tree_root.tick(test_vars, delta, eval_cache)
	for n: ConditionNodeData in _all_loose_roots():
		var _loose_value: Dictionary = n.tick(test_vars, delta, eval_cache)
	for n: ConditionNodeData in visible_nodes:
		if not eval_cache.has(n.id):
			var _orphan_value: Dictionary = n.tick(test_vars, delta, eval_cache)

	for n: ConditionNodeData in visible_nodes:
		var w: GraphNodeWidget = widgets[n.id]
		var r: Dictionary = eval_cache[n.id]
		w.selected = selection.has(n.id)
		w.dimmed = spotlight != null and not (spotlight as Dictionary).has(n.id)
		w.expanded = expanded.has(n.id)
		w.unconnected = parent_of[n.id] == null
		if r["is_bool"]:
			w.eval_state = r["value"]
			w.value_text = "?" if r["value"] == null else ("true" if r["value"] else "false")
		else:
			w.eval_state = null
			var v: float = r["value"]
			w.value_text = str(roundi(v)) if n.type == "int" else str(v)
		w.refresh()
		if n.is_timing():
			w.queue_redraw()
		w.position = w.position  # keep any running tween target; refresh may resize

	var traces: Array[Dictionary] = []
	var rail_point: Vector2 = Vector2(rail.position.x - 6.0, rail.position.y + RAIL_H * 0.5)
	for n: ConditionNodeData in visible_nodes:
		var p: ConditionNodeData = parent_of[n.id]
		if p == null:
			continue  # unwired root: nothing consumes it yet
		var a: Vector2 = _out_point(n)
		var b: Vector2 = rail_point if p == _focus() else _in_point(p)
		var r: Dictionary = eval_cache[n.id]
		var col: Color = COLORS[n.kind]
		var alpha: float = 0.82
		var width: float = 2.0
		if r["is_bool"] and r["value"] == true:
			col = COLORS["true"]
			alpha = 0.95
		elif spotlight != null and not (spotlight as Dictionary).has(n.id):
			alpha = 0.16
		elif r["is_bool"] and r["value"] == false:
			col = COLORS["false"]
			alpha = 0.5
		if selection.has(n.id):
			width = 3.0
			alpha = maxf(alpha, 1.0)
		traces.append({"a": a, "b": b, "color": Color(col, alpha), "width": width})
	trace_layer.set_traces(traces)

	var g: ConditionNodeData = _focus()
	var gr: Dictionary = eval_cache.get(g.id, {"value": null, "is_bool": true})
	rail.glyph_text = g.glyph()
	rail.glyph_color = COLORS[g.kind]
	rail.gate_name = g.op.to_upper() if g.kind == "logic" else g.display_label()
	rail.out_state = gr["value"] if gr["is_bool"] else null
	rail.selected = gate_selected
	rail.queue_redraw()

# ============================================================================
# Spotlight / expansion helpers
# ============================================================================
func _ancestors_of(id: String) -> Array[String]:
	var out: Array[String] = []
	var p: ConditionNodeData = parent_of.get(id)
	while p != null and p != _focus():
		out.append(p.id)
		p = parent_of.get(p.id)
	return out


func _compute_spotlight(id: String) -> Dictionary:
	var marked: Dictionary = {id: true}
	for n: ConditionNodeData in visible_nodes:
		var p: ConditionNodeData = parent_of.get(n.id)
		while p != null:
			if p.id == id:
				marked[n.id] = true
				break
			p = parent_of.get(p.id)
	return marked


func _collapse_from(id: String) -> void:
	var keep: Dictionary = {}
	for eid: String in expanded.keys():
		if eid == id:
			continue
		var p: ConditionNodeData = parent_of.get(eid)
		var desc: bool = false
		while p != null:
			if p.id == id:
				desc = true
				break
			p = parent_of.get(p.id)
		if not desc:
			keep[eid] = true
	_set_expansion(keep)


func _visible_subtree_ids(id: String) -> Array[String]:
	var out: Array[String] = [id]
	var r: Dictionary = _find(id)
	if r.is_empty():
		return out
	var rec: Callable = func(n: ConditionNodeData, again: Callable) -> void:
		if expanded.has(n.id):
			for c: ConditionNodeData in n.children:
				if widgets.has(c.id):
					out.append(c.id)
					again.call(c, again)
	rec.call(r["node"], rec)
	return out


# ============================================================================
# Selection
# ============================================================================
func _set_selection(ids: Dictionary, gate: Variant = null) -> void:
	selection = ids
	if gate != null:
		gate_selected = gate
	_repaint()
	_update_inspector()


func _toggle_select(id: String) -> void:
	var s: Dictionary = selection.duplicate()
	if s.has(id):
		var _erased: bool = s.erase(id)
	else:
		s[id] = true
	_set_selection(s)


func _clear_selection() -> void:
	if not selection.is_empty() or gate_selected:
		_set_selection({}, false)


# ============================================================================
# Click / double-click / drag on nodes
# ============================================================================
func _on_widget_pressed(w: GraphNodeWidget, ev: InputEventMouseButton) -> void:
	if drag_mode != DragMode.NONE:
		return
	if Input.is_key_pressed(KEY_SPACE):
		_begin_pan(MOUSE_BUTTON_LEFT)
		return
	if ev.double_click:
		_click_token += 1  # cancel any pending single-click
	drag_was_double = ev.double_click
	drag_was_ctrl = ev.ctrl_pressed or ev.meta_pressed
	drag_widget = w
	drag_mode = DragMode.NODE_PENDING
	drag_button = MOUSE_BUTTON_LEFT
	drag_start_screen = get_global_mouse_position()
	drag_start_world = _to_world(drag_start_screen)
	var id: String = w.data.id
	drag_move_ids.clear()
	if selection.has(id):
		for sid: String in selection.keys():
			drag_move_ids.append(sid)
	else:
		drag_move_ids = _visible_subtree_ids(id)
	drag_starts.clear()
	for mid: String in drag_move_ids:
		if node_pos.has(mid):
			drag_starts[mid] = node_pos[mid]


func _single_click(node: ConditionNodeData) -> void:
	if node.is_gate() and not node.children.is_empty():
		if expanded.has(node.id):
			_collapse_from(node.id)
			spotlight = null
		else:
			var nxt: Dictionary = {node.id: true}
			for aid: String in _ancestors_of(node.id):
				nxt[aid] = true
			_set_expansion(nxt)
		selection = {node.id: true}
		gate_selected = false
		_build_viewport(false)
		spotlight = _compute_spotlight(node.id) if expanded.has(node.id) else null
		_repaint()
		_update_inspector()
	else:
		selection = {node.id: true}
		gate_selected = false
		spotlight = _compute_spotlight(node.id)
		_repaint()
		_update_inspector()


func _double_click(node: ConditionNodeData) -> void:
	if node.is_gate():
		var origin: Variant = null
		if node_pos.has(node.id):
			origin = node_pos[node.id] + widgets[node.id].size * 0.5
		_enter(node, origin)
	else:
		var w: GraphNodeWidget = widgets.get(node.id)
		if w:
			var tw: Tween = create_tween()
			tw.tween_property(w, "position:x", w.position.x - 4, 0.07)
			tw.tween_property(w, "position:x", w.position.x + 4, 0.14)
			tw.tween_property(w, "position:x", w.position.x, 0.07)
		_toast("Leaf value - nothing inside.")


func _finish_node_click() -> void:
	var node: ConditionNodeData = drag_widget.data
	if drag_was_ctrl:
		_toggle_select(node.id)
		return
	if drag_was_double:
		_double_click(node)
		return
	_click_token += 1
	var token: int = _click_token
	get_tree().create_timer(SINGLE_CLICK_DELAY).timeout.connect(func() -> void:
		if token == _click_token and is_instance_valid(self):
			_single_click(node))


# ============================================================================
# Stage input: pan / zoom / marquee / context menu
# ============================================================================
func _on_stage_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_MIDDLE:
				_begin_pan(MOUSE_BUTTON_MIDDLE)
				stage.accept_event()
			MOUSE_BUTTON_LEFT:
				if Input.is_key_pressed(KEY_SPACE):
					_begin_pan(MOUSE_BUTTON_LEFT)
				else:
					_begin_marquee(event)
				stage.accept_event()
			MOUSE_BUTTON_RIGHT:
				_open_blank_menu(_to_world(get_global_mouse_position()))
				stage.accept_event()
			MOUSE_BUTTON_WHEEL_UP:
				if event.ctrl_pressed or event.meta_pressed:
					_set_zoom(zoom * 1.1, event.position)
				else:
					world.position.y += 60
					_clamp_pan()
				stage.accept_event()
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.ctrl_pressed or event.meta_pressed:
					_set_zoom(zoom / 1.1, event.position)
				else:
					world.position.y -= 60
					_clamp_pan()
				stage.accept_event()
			MOUSE_BUTTON_WHEEL_LEFT:
				world.position.x += 60
				_clamp_pan()
				stage.accept_event()
			MOUSE_BUTTON_WHEEL_RIGHT:
				world.position.x -= 60
				_clamp_pan()
				stage.accept_event()


func _begin_pan(button: MouseButton) -> void:
	drag_mode = DragMode.PAN
	drag_button = button
	drag_start_screen = get_global_mouse_position()
	pan_start_pos = world.position
	stage.mouse_default_cursor_shape = Control.CURSOR_DRAG


func _begin_marquee(event: InputEventMouseButton) -> void:
	drag_mode = DragMode.MARQUEE_PENDING
	drag_button = MOUSE_BUTTON_LEFT
	drag_start_screen = get_global_mouse_position()
	drag_start_world = _to_world(drag_start_screen)
	marquee_add = event.shift_pressed or event.ctrl_pressed or event.meta_pressed
	marquee_base = selection.duplicate() if marquee_add else {}


func _update_marquee() -> void:
	var w: Vector2 = _to_world(get_global_mouse_position())
	var tl: Vector2 = Vector2(minf(drag_start_world.x, w.x), minf(drag_start_world.y, w.y))
	var br: Vector2 = Vector2(maxf(drag_start_world.x, w.x), maxf(drag_start_world.y, w.y))
	marquee.position = tl
	marquee.size = br - tl
	var sel: Dictionary = marquee_base.duplicate()
	for n: ConditionNodeData in visible_nodes:
		var r: Rect2 = Rect2(node_pos[n.id], widgets[n.id].size)
		if r.intersects(Rect2(tl, br - tl)):
			sel[n.id] = true
	_set_selection(sel)


# ============================================================================
# Library drag and drop (Conditions panel -> canvas)
# ============================================================================
func _stage_can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if not (data is Dictionary):
		return false
	return (data as Dictionary).get("type", "") == DRAG_CONDITION


func _stage_drop_data(at_position: Vector2, data: Variant) -> void:
	if not _stage_can_drop_data(at_position, data):
		return
	var gid: String = str((data as Dictionary).get("group_id", ""))
	var g: Dictionary = _group_by_id(gid)
	if g.is_empty():
		_toast("That condition is no longer in the library.")
		return
	# Drop under the cursor rather than with the cursor on the card's corner.
	var wp: Vector2 = _to_world(stage.get_global_transform() * at_position)
	_insert_condition(g, wp - Vector2(70.0, 30.0))


func _group_by_id(gid: String) -> Dictionary:
	for g: Dictionary in groups:
		if str(g.get("id", "")) == gid:
			return g
	return {}


## Drag source callback for a library row. Returns the payload the canvas reads.
func _begin_group_drag(row: Button, g: Dictionary) -> Variant:
	var root: ConditionNodeData = g["root"]
	var chip: Label = _tiny_label("%s  %s" % [root.glyph(), g["name"]], COLORS["text"], 12)
	var wrap: PanelContainer = PanelContainer.new()
	wrap.add_theme_stylebox_override("panel",
		_panel_style(COLORS["surface_hi"], COLORS["sel"], 10, 9))
	wrap.modulate = Color(1, 1, 1, 0.92)
	wrap.add_child(chip)
	row.set_drag_preview(wrap)
	return {"type": DRAG_CONDITION, "group_id": str(g.get("id", ""))}


# ============================================================================
# Global motion / release handling for active drags
# ============================================================================
func _input(event: InputEvent) -> void:
	if drag_mode == DragMode.NONE:
		return
	if event is InputEventMouseMotion:
		_drag_motion()
	elif event is InputEventMouseButton and not event.pressed \
			and event.button_index == drag_button:
		_drag_release()
		get_viewport().set_input_as_handled()


func _drag_motion() -> void:
	var gp: Vector2 = get_global_mouse_position()
	match drag_mode:
		DragMode.NODE_PENDING:
			if gp.distance_to(drag_start_screen) > CLICK_SLOP:
				drag_mode = DragMode.NODE
				_drag_motion()
		DragMode.NODE:
			var delta: Vector2 = _to_world(gp) - drag_start_world
			var lp: Dictionary = _layer_positions()
			for mid: String in drag_move_ids:
				if not drag_starts.has(mid):
					continue
				var np: Vector2 = drag_starts[mid] + delta
				node_pos[mid] = np
				lp[mid] = np
				var wdg: GraphNodeWidget = widgets.get(mid)
				if wdg:
					wdg.position = np
			_repaint()
		DragMode.MARQUEE_PENDING:
			if gp.distance_to(drag_start_screen) > CLICK_SLOP:
				drag_mode = DragMode.MARQUEE
				marquee.visible = true
				_update_marquee()
		DragMode.MARQUEE:
			_update_marquee()
		DragMode.PAN:
			world.position = pan_start_pos + (gp - drag_start_screen)
			_clamp_pan()
		DragMode.WIRE:
			trace_layer.set_preview(true, wire_from, _to_world(gp),
				1.0 if wire_dir == "out" else -1.0)
		DragMode.PANEL:
			if drag_panel != null:
				drag_panel.global_position = gp + panel_grab
				_clamp_panel(drag_panel)

func _drag_release() -> void:
	var mode: DragMode = drag_mode
	drag_mode = DragMode.NONE
	stage.mouse_default_cursor_shape = Control.CURSOR_ARROW
	match mode:
		DragMode.NODE_PENDING:
			_finish_node_click()
		DragMode.NODE:
			pass
		DragMode.MARQUEE_PENDING:
			# Blank click: collapse everything and clear selection (mockup behaviour).
			expanded.clear()
			selection.clear()
			gate_selected = false
			spotlight = null
			_build_viewport(true)
			_update_inspector()
		DragMode.MARQUEE:
			marquee.visible = false
		DragMode.WIRE:
			trace_layer.set_preview(false)
			_finish_wire()
		DragMode.PANEL:
			drag_panel = null
# ============================================================================
# Wiring
# ============================================================================
func _on_port_pressed(w: GraphNodeWidget, dir: String, _ev: InputEventMouseButton) -> void:
	if drag_mode != DragMode.NONE:
		return
	drag_mode = DragMode.WIRE
	drag_button = MOUSE_BUTTON_LEFT
	wire_node = w.data
	wire_dir = dir
	wire_from = _out_point(wire_node) if dir == "out" else _in_point(wire_node)
	trace_layer.preview_color = COLORS["sel"]


func _on_rail_port_pressed(_ev: InputEventMouseButton) -> void:
	if drag_mode != DragMode.NONE:
		return
	drag_mode = DragMode.WIRE
	drag_button = MOUSE_BUTTON_LEFT
	wire_node = _focus()
	wire_dir = "in"
	wire_from = rail.port_point()
	trace_layer.preview_color = COLORS["sel"]


func _widget_at(world_point: Vector2, exclude_id: String = "") -> GraphNodeWidget:
	var kids: Array[Node] = nodes_layer.get_children()
	for i: int in range(kids.size() - 1, -1, -1):
		var w: GraphNodeWidget = kids[i] as GraphNodeWidget
		if w == null or w.data.id == exclude_id:
			continue
		if Rect2(w.position, w.size).has_point(world_point):
			return w
	return null


func _rail_at(world_point: Vector2) -> bool:
	return Rect2(rail.position, rail.size).has_point(world_point)


func _finish_wire() -> void:
	var wp: Vector2 = _to_world(get_global_mouse_position())
	var target: GraphNodeWidget = _widget_at(wp, wire_node.id)
	var on_rail: bool = _rail_at(wp)
	if wire_dir == "out":
		if target:
			var t: ConditionNodeData = target.data
			if t.is_gate() and not wire_node.contains_id(t.id):
				_reparent(wire_node, t)
				_toast("Wired into %s." % t.label)
			else:
				_toast("Can't wire into its own branch." if t.is_gate()
					else "Target must be a gate.")
		elif on_rail:
			_reparent(wire_node, _focus())
			_toast("Wired to output gate.")
		else:
			_open_create_menu(wp, func(kind: String, op: String) -> void:
				_insert_in_wire(kind, op, wp))
	else:
		if target:
			var s: ConditionNodeData = target.data
			if not s.contains_id(wire_node.id):
				_reparent(s, wire_node)
				_toast("%s feeds %s." % [s.label, wire_node.label])
			else:
				_toast("Can't create a loop.")
		elif on_rail:
			_toast("The rail is the output, not an input.")
		else:
			var upstream: ConditionNodeData = wire_node
			_open_create_menu(wp, func(kind: String, op: String) -> void:
				var n: ConditionNodeData = ConditionNodeData.create(kind, op)
				upstream.children.append(n)
				if upstream != _focus():
					expanded[upstream.id] = true
				_layer_positions()[n.id] = wp
				_mark_pkg_dirty()
				_build_viewport(true)
				_set_selection({n.id: true}, false)
				_toast("Input node created."))


func _insert_in_wire(kind: String, op: String, wp: Vector2) -> void:
	var n: ConditionNodeData = ConditionNodeData.create(kind, op)
	var found: Dictionary = _find(wire_node.id)
	var par: ConditionNodeData = found.get("parent") if not found.is_empty() else null
	var was_loose: bool = par == null
	if was_loose:
		# The wire started from an unwired root: the new node takes its place on
		# the canvas and keeps the whole thing unwired.
		var _detached: bool = _detach(wire_node)
		_layer_loose().append(n)
	else:
		var idx: int = par.children.find(wire_node)
		if idx >= 0:
			par.children[idx] = n
		else:
			par.children.append(n)
		if par != _focus():
			expanded[par.id] = true
	if n.kind == "compare":
		n.children[0] = wire_node
	else:
		n.children.append(wire_node)
	_layer_positions()[n.id] = wp
	expanded[n.id] = true
	_mark_pkg_dirty()
	_build_viewport(true)
	_set_selection({n.id: true}, false)
	_toast("Inserted a node in the wire.")


## Remove a node from wherever it lives (a parent's child list, or the unwired
## pool). Returns true when it was found and removed.
func _detach(node: ConditionNodeData) -> bool:
	var found: Dictionary = _find(node.id)
	if found.is_empty():
		return false
	var par: ConditionNodeData = found["parent"]
	if par != null:
		par.children.erase(node)
		return true
	for key: String in loose.keys():
		var roots: Array[ConditionNodeData] = loose[key]
		if roots.has(node):
			roots.erase(node)
			return true
	return false


func _reparent(child: ConditionNodeData, new_parent: ConditionNodeData) -> void:
	if child == new_parent or child.contains_id(new_parent.id):
		return
	var found: Dictionary = _find(child.id)
	if found.is_empty():
		return
	var old_parent: ConditionNodeData = found["parent"]
	if old_parent == new_parent:
		return
	if not _detach(child):
		return
	new_parent.children.append(child)
	if new_parent != _focus():
		expanded[new_parent.id] = true
	_mark_pkg_dirty()
	_build_viewport(true)


# ============================================================================
# Navigation
# ============================================================================
## Clears the transient bits only. Expansion and positions are per layer, so
## they survive a round trip in and out of a gate.
func _reset_view_state() -> void:
	selection.clear()
	gate_selected = false
	spotlight = null


func _enter(node: ConditionNodeData, origin: Variant) -> void:
	_switch_expansion_to(node.id)
	path.append(node)
	_reset_view_state()
	_draw_crumbs()
	back_btn.disabled = false
	_build_viewport(true)
	_update_inspector()
	_run_nav_anim(true, origin)


func _go_back() -> void:
	if path.size() <= 1:
		return
	_switch_expansion_to(path[path.size() - 2].id)
	path.pop_back()
	_reset_view_state()
	_draw_crumbs()
	back_btn.disabled = path.size() <= 1
	_build_viewport(true)
	_render_vars()
	_update_inspector()
	_run_nav_anim(false, null)


func _go_to(i: int) -> void:
	if i >= path.size() - 1:
		return
	_switch_expansion_to(path[i].id)
	path.resize(i + 1)
	_reset_view_state()
	_draw_crumbs()
	back_btn.disabled = path.size() <= 1
	_build_viewport(true)
	_render_vars()
	_update_inspector()
	_run_nav_anim(false, null)


func _run_nav_anim(entering: bool, origin: Variant) -> void:
	if _nav_tween:
		_nav_tween.kill()
	world.pivot_offset = origin if origin != null else content_size * 0.5
	var start: float = zoom * (0.5 if entering else 1.32)
	world.scale = Vector2(start, start)
	world.modulate.a = 0.15
	_nav_tween = create_tween().set_parallel(true)
	_nav_tween.tween_property(world, "scale", Vector2(zoom, zoom), 0.34) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_nav_tween.tween_property(world, "modulate:a", 1.0, 0.34)
	_nav_tween.chain().tween_callback(func() -> void:
		world.pivot_offset = Vector2.ZERO
		world.scale = Vector2(zoom, zoom)
		_clamp_pan())


# ============================================================================
# Rail interaction
# ============================================================================
func _on_rail_clicked() -> void:
	_set_selection(selection, not gate_selected)


# ============================================================================
# Structural edits
# ============================================================================
func _add_node(node: ConditionNodeData, pos: Variant) -> void:
	_focus().children.append(node)
	if pos != null:
		_layer_positions()[node.id] = pos
	_mark_pkg_dirty()
	_build_viewport(true)
	_set_selection({node.id: true}, false)


func _delete_selection() -> void:
	var ids: Array = selection.keys()
	if ids.is_empty():
		return
	for id: String in ids:
		var r: Dictionary = _find(id)
		if r.is_empty():
			continue
		var _removed: bool = _detach(r["node"])
		var _erased: bool = _layer_positions().erase(id)
	selection.clear()
	spotlight = null
	_mark_pkg_dirty()
	_build_viewport(true)
	_update_inspector()
	_toast("%d deleted." % ids.size() if ids.size() > 1 else "Deleted.")


func _copy_selection() -> void:
	var ids: Array = selection.keys()
	if ids.is_empty():
		return
	clipboard.clear()
	for id: String in ids:
		var r: Dictionary = _find(id)
		if not r.is_empty():
			clipboard.append((r["node"] as ConditionNodeData).clone_new())
	_toast("%d copied." % ids.size() if ids.size() > 1 else "Copied.")


func _paste_clipboard(pos: Variant) -> void:
	if clipboard.is_empty():
		return
	var f: ConditionNodeData = _focus()
	var added: Dictionary = {}
	var base: Vector2 = pos if pos != null else Vector2(80, 80)
	for i: int in clipboard.size():
		var c: ConditionNodeData = clipboard[i].clone_new()
		f.children.append(c)
		_layer_positions()[c.id] = base + Vector2(22, 22) * i
		added[c.id] = true
	_mark_pkg_dirty()
	_build_viewport(true)
	_set_selection(added, false)
	_toast("Pasted.")


# ============================================================================
# Condition library (reusable "packages")
# ============================================================================
func _selected_top_nodes() -> Array[ConditionNodeData]:
	var out: Array[ConditionNodeData] = []
	for id: String in selection.keys():
		var r: Dictionary = _find(id)
		if r.is_empty():
			continue
		var covered: bool = false
		var p: ConditionNodeData = r["parent"]
		while p != null:
			if selection.has(p.id):
				covered = true
				break
			var pr: Dictionary = _find(p.id)
			p = pr.get("parent") if not pr.is_empty() else null
		if not covered:
			out.append(r["node"])
	return out


func _save_condition() -> void:
	var f: ConditionNodeData = _focus()
	var tops: Array[ConditionNodeData] = _selected_top_nodes()
	var root: ConditionNodeData = null
	var sources: Array[ConditionNodeData] = []
	var wraps_gate: bool = false
	if gate_selected:
		var sel_kids: Array[ConditionNodeData] = []
		for c: ConditionNodeData in f.children:
			if selection.has(c.id):
				sel_kids.append(c)
		var source: Array[ConditionNodeData] = sel_kids if not sel_kids.is_empty() else f.children
		root = f.clone_exact()
		root.id = ConditionNodeData.new_id()
		root.pkg_id = ""
		root.pkg_name = ""
		root.children.clear()
		for c: ConditionNodeData in source:
			root.children.append(c.clone_new())
		wraps_gate = true
	elif tops.size() == 1:
		root = tops[0].clone_new()
		sources.append(tops[0])
	elif tops.size() > 1:
		root = ConditionNodeData.create("logic", "and")
		root.label = "combined"
		root.children.clear()
		for t: ConditionNodeData in tops:
			root.children.append(t.clone_new())
			sources.append(t)
	else:
		_toast("Select some nodes (or the Output rail) first.")
		return

	var suggested: String = root.display_label()
	if suggested == "":
		suggested = "condition"
	var cond_name: String = await _prompt("Save as condition",
		"Saved to disk. Drag it from the Conditions panel to reuse it.", suggested)
	if cond_name == "":
		return
	root.pkg_id = ""
	root.pkg_name = ""
	root.label = cond_name
	var g: Dictionary = {"id": ConditionNodeData.new_id(), "name": cond_name,
		"root": root.clone_exact()}
	groups.append(g)
	_persist_library()
	_render_library()
	cond_btn.button_pressed = true

	if wraps_gate:
		# The package contains this level's own gate. Dropping an instance back in
		# here would nest the gate inside itself (and flip NOT / XOR results), so
		# the source nodes are left exactly as they are.
		_toast("Saved \"%s\" (gate packages aren't swapped in place)." % cond_name)
		return
	_replace_with_instance(sources, g)
	_toast("Saved \"%s\" and swapped it in." % cond_name)


## Swap the packaged nodes for a single linked instance, keeping the first
## source node's parent slot and canvas position.
func _replace_with_instance(sources: Array[ConditionNodeData], g: Dictionary) -> void:
	if sources.is_empty():
		return
	var lp: Dictionary = _layer_positions()
	var anchor_pos: Vector2 = Vector2.ZERO
	var has_pos: bool = false
	var anchor_parent: ConditionNodeData = null
	var anchor_index: int = -1
	for s: ConditionNodeData in sources:
		if not has_pos and node_pos.has(s.id):
			anchor_pos = node_pos[s.id]
			has_pos = true
		if anchor_parent != null:
			continue
		var found: Dictionary = _find(s.id)
		if found.is_empty():
			continue
		var par: ConditionNodeData = found["parent"]
		if par != null:
			anchor_parent = par
			anchor_index = par.children.find(s)

	for s: ConditionNodeData in sources:
		var _removed: bool = _detach(s)
		var _erased: bool = lp.erase(s.id)

	var inst: ConditionNodeData = (g["root"] as ConditionNodeData).clone_new()
	inst.pkg_id = g["id"]
	inst.pkg_name = g["name"]
	inst.label = g["name"]
	if anchor_parent != null:
		anchor_index = clampi(anchor_index, 0, anchor_parent.children.size())
		var _inserted: int = anchor_parent.children.insert(anchor_index, inst)
		if anchor_parent != _focus():
			expanded[anchor_parent.id] = true
	else:
		# Every source was unwired, so the replacement stays unwired too.
		_layer_loose().append(inst)
	if has_pos:
		lp[inst.id] = anchor_pos
	selection.clear()
	spotlight = null
	_mark_pkg_dirty()
	_build_viewport(true)
	_set_selection({inst.id: true}, false)


## Drop a library condition onto the canvas as an unwired root. It deliberately
## does not attach to the output gate - the user wires it up when ready.
func _insert_condition(g: Dictionary, pos: Variant) -> void:
	var inst: ConditionNodeData = (g["root"] as ConditionNodeData).clone_new()
	inst.pkg_id = g["id"]
	inst.pkg_name = g["name"]
	inst.label = g["name"]
	_layer_loose().append(inst)
	_layer_positions()[inst.id] = pos if pos != null else Vector2(GUTTER, 60.0)
	_build_viewport(true)
	_set_selection({inst.id: true}, false)
	_render_vars()
	_toast("Placed \"%s\" - drag its output port into a gate to wire it up." % g["name"])


func _render_library() -> void:
	cond_btn.text = "Conditions \u00b7 %d" % groups.size()
	for c: Node in group_list.get_children():
		group_list.remove_child(c)
		c.queue_free()
	if groups.is_empty():
		var l: Label = Label.new()
		l.text = "Select nodes (add the Output rail for the gate), then \"Save as condition\". Saved conditions are dragged onto the canvas to reuse."
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_font_size_override("font_size", 11)
		l.add_theme_color_override("font_color", COLORS["faint"])
		group_list.add_child(l)
		return
	for g: Dictionary in groups:
		var gg: Dictionary = g
		var root: ConditionNodeData = gg["root"]
		var b: Button = Button.new()
		b.text = "%s  %s" % [root.glyph(), gg["name"]]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.tooltip_text = "Drag onto the canvas to place it"
		b.mouse_default_cursor_shape = Control.CURSOR_DRAG
		_style_button(b)
		b.set_drag_forwarding(
			func(_at: Vector2) -> Variant: return _begin_group_drag(b, gg),
			func(_at: Vector2, _data: Variant) -> bool: return false,
			func(_at: Vector2, _data: Variant) -> void: pass)
		b.pressed.connect(func() -> void:
			_toast("Drag \"%s\" onto the canvas to place it." % gg["name"]))
		group_list.add_child(b)


# ---- linked-instance edit prompt ----
func _nearest_pkg_in_path() -> ConditionNodeData:
	for i: int in range(path.size() - 1, 0, -1):
		if path[i].pkg_id != "":
			return path[i]
	return null


func _mark_pkg_dirty() -> void:
	var p: ConditionNodeData = _nearest_pkg_in_path()
	if p == null:
		return
	for g: Dictionary in groups:
		if g["id"] == p.pkg_id:
			dirty_pkg = {"node": p, "group": g}
			pkg_label.text = "You edited an instance of \"%s\"." % g["name"]
			pkg_bar.visible = true
			return


func _hide_pkg_bar() -> void:
	dirty_pkg = null
	pkg_bar.visible = false


func _pkg_update_everywhere() -> void:
	if dirty_pkg == null:
		return
	var node: ConditionNodeData = dirty_pkg["node"]
	var group: Dictionary = dirty_pkg["group"]
	var tmpl: ConditionNodeData = node.clone_exact()
	tmpl.pkg_id = ""
	tmpl.pkg_name = ""
	tmpl.label = group["name"]
	group["root"] = tmpl
	var instances: Array = []
	tree_root.collect_instances(group["id"], instances)
	for r: ConditionNodeData in _all_loose_roots():
		r.collect_instances(group["id"], instances)
	for inst: ConditionNodeData in instances:
		if inst == node:
			continue
		var fresh: ConditionNodeData = (group["root"] as ConditionNodeData).clone_new()
		inst.children = fresh.children
		inst.label = group["name"]
	_hide_pkg_bar()
	_persist_library()
	_render_library()
	_build_viewport(true)
	_toast("Updated \"%s\" everywhere." % group["name"])


func _pkg_save_as_new() -> void:
	if dirty_pkg == null:
		return
	var node: ConditionNodeData = dirty_pkg["node"]
	var cond_name: String = await _prompt("Save as new condition",
		"Detaches this instance; other uses stay unchanged.", node.pkg_name + " v2")
	if cond_name == "":
		return
	var root: ConditionNodeData = node.clone_exact()
	root.pkg_id = ""
	root.pkg_name = ""
	root.label = cond_name
	var g: Dictionary = {"id": ConditionNodeData.new_id(), "name": cond_name, "root": root}
	groups.append(g)
	node.pkg_id = g["id"]
	node.pkg_name = cond_name
	node.label = cond_name
	_hide_pkg_bar()
	_persist_library()
	_render_library()
	_build_viewport(true)
	_toast("Saved as \"%s\"." % cond_name)


func _pkg_keep_here() -> void:
	if dirty_pkg == null:
		return
	var node: ConditionNodeData = dirty_pkg["node"]
	node.pkg_id = ""
	node.pkg_name = ""
	_hide_pkg_bar()
	_build_viewport(true)
	_toast("Kept as a one-off (unlinked).")


# ============================================================================
# Context menus
# ============================================================================
func _swatch_icon(p_color: Color) -> ImageTexture:
	var img: Image = Image.create(9, 9, false, Image.FORMAT_RGBA8)
	img.fill(p_color)
	return ImageTexture.create_from_image(img)


## items: Array of Dictionaries:
##   {"label": String, "action": Callable} plus optional
##   "disabled": bool, "icon": Texture2D, "sep": bool, "title": String
func _show_menu(items: Array) -> void:
	var pm: PopupMenu = PopupMenu.new()
	pm.add_theme_font_size_override("font_size", 12)
	var actions: Array[Callable] = []
	for it: Dictionary in items:
		if it.get("sep", false):
			pm.add_separator()
			continue
		if it.has("title"):
			pm.add_separator(it["title"])
			continue
		var idx: int = pm.item_count
		if it.has("icon"):
			pm.add_icon_item(it["icon"], it["label"], actions.size())
		else:
			pm.add_item(it["label"], actions.size())
		pm.set_item_disabled(idx, it.get("disabled", false))
		actions.append(it.get("action", Callable()))
	pm.id_pressed.connect(func(id: int) -> void:
		if id >= 0 and id < actions.size() and actions[id].is_valid():
			actions[id].call())
	pm.popup_hide.connect(pm.queue_free)
	add_child(pm)
	pm.popup(Rect2i(Vector2i(get_global_mouse_position()), Vector2i.ZERO))


func _on_widget_context(w: GraphNodeWidget, _ev: InputEventMouseButton) -> void:
	var node: ConditionNodeData = w.data
	if not selection.has(node.id):
		_set_selection({node.id: true}, false)
	var count: int = selection.size()
	var items: Array = []
	if node.is_gate():
		items.append({"label": "Enter", "action": func() -> void:
			_double_click(node)})
		if not node.children.is_empty():
			items.append({"label": "Collapse" if expanded.has(node.id) else "Expand",
				"action": func() -> void: _single_click(node)})
	if parent_of.get(node.id) != null:
		items.append({"label": "Unwire", "action": func() -> void: _unwire(node)})
	items.append({"label": "Copy (%d)" % count if count > 1 else "Copy",
		"action": _copy_selection})
	items.append({"label": "Save as condition...", "action": _save_condition})
	items.append({"sep": true})
	items.append({"label": "Delete (%d)" % count if count > 1 else "Delete",
		"action": _delete_selection})
	_show_menu(items)


## Pull a node out of the tree and leave it parked on the canvas.
func _unwire(node: ConditionNodeData) -> void:
	var here: Vector2 = node_pos.get(node.id, Vector2(GUTTER, 60.0))
	if not _detach(node):
		return
	_layer_loose().append(node)
	_layer_positions()[node.id] = here
	_mark_pkg_dirty()
	_build_viewport(true)
	_set_selection({node.id: true}, false)
	_toast("Unwired \"%s\"." % node.display_label())


func _open_blank_menu(wp: Vector2) -> void:
	var items: Array = [{"title": "Add node"}]
	var defs: Array = [
		["logic", "and", "Logic - AND"], ["logic", "or", "Logic - OR"],
		["logic", "not", "Logic - NOT"], ["compare", "lt", "Comparison"],
		["timing", "hold", "Timing - stay true for"],
		["timing", "delay", "Timing - true after"],
		["timing", "latch", "Timing - latch until reset"],
		["query", "distance", "Sense - distance to nearest"],
		["query", "exists", "Sense - anything nearby"],
		["query", "count", "Sense - how many"],
		["query", "direction", "Sense - direction to nearest"],
		["query", "offset", "Sense - offset to nearest"],
		["vector", "const", "Vector - fixed value"],
		["vector", "from_angle", "Vector - from angle"],
		["vector", "scale", "Vector - scale"],
		["vector", "add", "Vector - add"],
		["vector", "length", "Vector - length"],
		["vector", "angle", "Vector - angle"],
		["property", "", "Property"], ["literal", "", "Constant"],
	]
	for d: Array in defs:
		var kind: String = d[0]
		var op: String = d[1]
		items.append({"label": d[2], "icon": _swatch_icon(COLORS[kind]),
			"action": func() -> void: _add_node(ConditionNodeData.create(kind, op), wp)})
	if not groups.is_empty():
		items.append({"title": "Place condition (unwired)"})
		for g: Dictionary in groups:
			var gg: Dictionary = g
			items.append({"label": "[%s]" % gg["name"],
				"action": func() -> void: _insert_condition(gg, wp)})
	items.append({"sep": true})
	items.append({"label": "Paste", "disabled": clipboard.is_empty(),
		"action": func() -> void: _paste_clipboard(wp)})
	items.append({"label": "Reset timers", "disabled": not live,
		"action": reset_timers})
	_show_menu(items)


func _open_create_menu(_wp: Vector2, cb: Callable) -> void:
	var items: Array = [{"title": "Wire into new node"}]
	var defs: Array = [
		["logic", "and", "Logic - AND"], ["logic", "or", "Logic - OR"],
		["timing", "hold", "Timing - stay true for"],
		["timing", "delay", "Timing - true after"],
		["compare", "lt", "Comparison"], ["query", "distance", "Sense query"],
		["property", "", "Property"], ["literal", "", "Constant"],
		["query", "direction", "Sense - direction"],
		["vector", "length", "Vector - length"],
		["vector", "scale", "Vector - scale"],
	]
	for d: Array in defs:
		var kind: String = d[0]
		var op: String = d[1]
		items.append({"label": d[2], "icon": _swatch_icon(COLORS[kind]),
			"action": func() -> void: cb.call(kind, op)})
	_show_menu(items)


# ============================================================================
# Variables panel
# ============================================================================
func _var_type(p_name: String) -> String:
	var v: Variant = test_vars.get(p_name)
	if v is bool:
		return "bool"
	if v is Vector2:
		return "vector"
	return "float"

## Variable names grouped by schema category, in a stable display order.
func _variables_by_category() -> Dictionary:
	var by_cat: Dictionary = {}
	for var_name: String in test_vars.keys():
		var cat: String = AntSchema.category_of(var_name)
		if not by_cat.has(cat):
			var fresh: Array[String] = []
			by_cat[cat] = fresh
		(by_cat[cat] as Array[String]).append(var_name)
	var ordered: Dictionary = {}
	for cat: String in AntSchema.CATEGORY_ORDER:
		if by_cat.has(cat):
			ordered[cat] = by_cat[cat]
	for cat: String in by_cat.keys():
		if not ordered.has(cat):
			ordered[cat] = by_cat[cat]
	return ordered


## The action variable currently set true, or "" if none is.
func _current_action_var() -> String:
	for var_name: String in AntSchema.action_variables():
		if test_vars.get(var_name) == true:
			return var_name
	return ""


## Actions are mutually exclusive, so setting one clears the rest.
func _set_action_var(var_name: String) -> void:
	for other: String in AntSchema.action_variables():
		test_vars[other] = other == var_name
	_repaint()


func _render_vars() -> void:
	_seed_all_vars()
	for c: Node in vars_list.get_children():
		vars_list.remove_child(c)
		c.queue_free()
	var by_cat: Dictionary = _variables_by_category()
	for cat: String in by_cat.keys():
		var header: Label = _tiny_label(cat.to_upper(), COLORS["faint"], 9)
		vars_list.add_child(header)
		if cat == AntSchema.CATEGORY_ACTION:
			vars_list.add_child(_build_action_picker())
			continue
		for var_name: String in by_cat[cat]:
			vars_list.add_child(_build_var_row(var_name))


## One dropdown for the whole Action category - the ant is only ever doing one.
func _build_action_picker() -> Control:
	var ob: OptionButton = OptionButton.new()
	_style_option(ob)
	var names: Array[String] = AntSchema.action_variables()
	for i: int in names.size():
		ob.add_item(names[i].trim_prefix("is_").replace("_", " "), i)
		if names[i] == _current_action_var():
			ob.selected = i
	ob.item_selected.connect(func(i: int) -> void: _set_action_var(names[i]))
	return ob


func _build_var_row(var_name: String) -> Control:
	var wrap: VBoxContainer = VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 4)
	var head: HBoxContainer = HBoxContainer.new()
	var name_label: Label = _tiny_label(var_name, COLORS["text"], 12)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.tooltip_text = var_name
	head.add_child(name_label)
	wrap.add_child(head)
	if test_vars[var_name] is bool:
		var cb: CheckButton = CheckButton.new()
		cb.button_pressed = test_vars[var_name]
		cb.text = "true" if test_vars[var_name] else "false"
		cb.add_theme_font_size_override("font_size", 11)
		cb.add_theme_color_override("font_color", COLORS["dim"])
		cb.focus_mode = Control.FOCUS_NONE
		cb.toggled.connect(func(on: bool) -> void:
			test_vars[var_name] = on
			cb.text = "true" if on else "false"
			_repaint())
		wrap.add_child(cb)
		return wrap
	if test_vars[var_name] is Vector2:
		wrap.add_child(_build_vector_editor(var_name, head))
		return wrap
	var spec: Dictionary = AntSchema.describe(var_name)
	var low: float = spec["min"]
	var high: float = spec["max"]
	var value_label: Label = _tiny_label(
		str(test_vars[var_name]), COLORS["property"], 12)
	head.add_child(value_label)
	var slider: HSlider = HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = maxf(0.01, snappedf((high - low) / 200.0, 0.01))
	slider.value = clampf(float(test_vars[var_name]), low, high)
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(func(v: float) -> void:
		test_vars[var_name] = v
		value_label.text = str(v)
		_repaint())
	wrap.add_child(slider)
	return wrap


## Vectors are edited as angle plus length. That is how a player reasons about
## "direction to the nearest food", and it makes length 0 - the canonical
## "nothing sensed" - a single obvious slider position.
func _build_vector_editor(var_name: String, head: HBoxContainer) -> Control:
	var top: float = maxf(0.001, AntSchema.max_of(var_name))
	var current: Vector2 = test_vars[var_name]
	var value_label: Label = _tiny_label(_vec_text(current), COLORS["vector"], 12)
	head.add_child(value_label)

	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var angle_slider: HSlider = HSlider.new()
	angle_slider.min_value = -180.0
	angle_slider.max_value = 180.0
	angle_slider.step = 1.0
	angle_slider.value = 0.0 if current.is_zero_approx() else rad_to_deg(current.angle())
	angle_slider.focus_mode = Control.FOCUS_NONE
	var length_slider: HSlider = HSlider.new()
	length_slider.min_value = 0.0
	length_slider.max_value = top
	length_slider.step = maxf(0.01, snappedf(top / 200.0, 0.01))
	length_slider.value = clampf(current.length(), 0.0, top)
	length_slider.focus_mode = Control.FOCUS_NONE

	var apply: Callable = func() -> void:
		var v: Vector2 = Vector2.RIGHT.rotated(
			deg_to_rad(angle_slider.value)) * length_slider.value
		test_vars[var_name] = v
		value_label.text = _vec_text(v)
		_repaint()
	angle_slider.value_changed.connect(func(_v: float) -> void: apply.call())
	length_slider.value_changed.connect(func(_v: float) -> void: apply.call())

	box.add_child(_tiny_label("angle", COLORS["faint"], 9))
	box.add_child(angle_slider)
	box.add_child(_tiny_label("length", COLORS["faint"], 9))
	box.add_child(length_slider)
	return box


func _vec_text(v: Vector2) -> String:
	if v.is_zero_approx():
		return "none"
	return "(%.1f, %.1f)" % [v.x, v.y]

# ============================================================================
# Inspector
# ============================================================================
func _form_label(p_text: String) -> Label:
	return _tiny_label(p_text.to_upper(), COLORS["faint"], 9)


func _commit_edit() -> void:
	_mark_pkg_dirty()
	_build_viewport(true)
	_update_inspector()


func _build_inspector_form(node: ConditionNodeData) -> void:
	for c: Node in form_box.get_children():
		form_box.remove_child(c)
		c.queue_free()
	match node.kind:
		"literal":
			form_box.add_child(_form_label("Value"))
			var le: LineEdit = LineEdit.new()
			le.text = node.label
			_style_line_edit(le)
			le.text_changed.connect(func(t: String) -> void:
				node.label = t
				insp_title.text = node.display_label()
				var w: GraphNodeWidget = widgets.get(node.id)
				if w:
					w.refresh()
				_repaint())
			le.text_submitted.connect(func(_t: String) -> void: _commit_edit())
			le.focus_exited.connect(_commit_edit)
			form_box.add_child(le)
			form_box.add_child(_form_label("Type"))
			var ob: OptionButton = OptionButton.new()
			ob.add_item("float")
			ob.add_item("int")
			ob.selected = 1 if node.type == "int" else 0
			_style_option(ob)
			ob.item_selected.connect(func(i: int) -> void:
				node.type = "int" if i == 1 else "float"
				_commit_edit())
			form_box.add_child(ob)
		"property":
			form_box.add_child(_form_label("Tracks variable"))
			var ob: OptionButton = OptionButton.new()
			_style_option(ob)
			var by_id: Dictionary = {}
			var next_id: int = 0
			var grouped: Dictionary = _variables_by_category()
			for cat: String in grouped.keys():
				ob.add_separator(cat)
				for vn: String in grouped[cat]:
					ob.add_item("%s - %s" % [vn, _var_type(vn)], next_id)
					by_id[next_id] = vn
					if vn == node.label:
						ob.selected = ob.item_count - 1
					next_id += 1
			ob.add_separator("")
			ob.add_item("+ new variable...", -1)
			ob.item_selected.connect(func(i: int) -> void:
				var picked: int = ob.get_item_id(i)
				if picked < 0:
					var nm: String = await _prompt("New variable",
						"Add a test variable to track.", "new_var")
					if nm == "":
						_update_inspector()
						return
					if not test_vars.has(nm):
						test_vars[nm] = AntSchema.default_for(nm)
					node.label = nm
				else:
					node.label = by_id[picked]
				node.type = _var_type(node.label)
				_commit_edit()
				_render_vars())
			form_box.add_child(ob)
			form_box.add_child(_form_label("Value type"))
			var tle: LineEdit = LineEdit.new()
			tle.text = node.type
			tle.editable = false
			_style_line_edit(tle)
			tle.add_theme_color_override("font_uneditable_color", COLORS["faint"])
			form_box.add_child(tle)
		"timing":
			form_box.add_child(_form_label("Name (optional)"))
			var le: LineEdit = LineEdit.new()
			le.text = node.label
			le.placeholder_text = node.display_label()
			_style_line_edit(le)
			le.text_changed.connect(func(t: String) -> void:
				node.label = t
				insp_title.text = node.display_label()
				var w: GraphNodeWidget = widgets.get(node.id)
				if w:
					w.refresh()
				_repaint())
			le.text_submitted.connect(func(_t: String) -> void: _commit_edit())
			le.focus_exited.connect(_commit_edit)
			form_box.add_child(le)
			form_box.add_child(_form_label("Behaviour"))
			var ob: OptionButton = OptionButton.new()
			_style_option(ob)
			for i: int in ConditionNodeData.TIMING_OPS.size():
				var top: String = ConditionNodeData.TIMING_OPS[i]
				ob.add_item(ConditionNodeData.TIMING_NAMES.get(top, top), i)
				if top == node.op:
					ob.selected = i
			ob.item_selected.connect(func(i: int) -> void:
				node.op = ConditionNodeData.TIMING_OPS[i]
				node.reset_runtime()
				_commit_edit())
			form_box.add_child(ob)
			form_box.add_child(_form_label("Seconds"))
			var spin: SpinBox = SpinBox.new()
			spin.min_value = 0.0
			spin.max_value = 600.0
			spin.step = 0.1
			spin.value = node.seconds
			spin.editable = node.op != "latch"
			_style_spin(spin)
			spin.value_changed.connect(func(v: float) -> void:
				node.seconds = maxf(0.0, v)
				node.reset_runtime()
				var w: GraphNodeWidget = widgets.get(node.id)
				if w:
					w.refresh()
				insp_title.text = node.display_label()
				_repaint())
			form_box.add_child(spin)
			form_box.add_child(_form_label("How it behaves"))
			var help: Label = Label.new()
			help.text = ConditionNodeData.TIMING_HELP.get(node.op, "")
			help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			help.add_theme_font_size_override("font_size", 11)
			help.add_theme_color_override("font_color", COLORS["faint"])
			form_box.add_child(help)
			var wiring: Label = Label.new()
			wiring.text = "First input drives it. Wire a second input to use as the reset / trigger."
			wiring.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			wiring.add_theme_font_size_override("font_size", 11)
			wiring.add_theme_color_override("font_color", COLORS["dim"])
			form_box.add_child(wiring)
			var reset_btn: Button = Button.new()
			reset_btn.text = "Reset this timer"
			_style_button(reset_btn)
			reset_btn.pressed.connect(func() -> void:
				node.reset_runtime()
				_repaint())
			form_box.add_child(reset_btn)
		"query":
			form_box.add_child(_form_label("Measure"))
			var measure_ob: OptionButton = OptionButton.new()
			_style_option(measure_ob)
			for i: int in ConditionNodeData.QUERY_MEASURES.size():
				var m: String = ConditionNodeData.QUERY_MEASURES[i]
				measure_ob.add_item(ConditionNodeData.MEASURE_WORDS.get(m, m), i)
				if m == node.op:
					measure_ob.selected = i
			measure_ob.item_selected.connect(func(i: int) -> void:
				node.op = ConditionNodeData.QUERY_MEASURES[i]
				node.type = node.measure_type()
				_commit_edit()
				_render_vars())
			form_box.add_child(measure_ob)
			form_box.add_child(_form_label("Subject"))
			var subject_ob: OptionButton = OptionButton.new()
			_style_option(subject_ob)
			for i: int in ConditionNodeData.QUERY_SUBJECTS.size():
				var sub: String = ConditionNodeData.QUERY_SUBJECTS[i]
				subject_ob.add_item(ConditionNodeData.subject_name(sub), i)
				if sub == node.subject:
					subject_ob.selected = i
			subject_ob.item_selected.connect(func(i: int) -> void:
				node.subject = ConditionNodeData.QUERY_SUBJECTS[i]
				_commit_edit()
				_render_vars())
			form_box.add_child(subject_ob)
			form_box.add_child(_form_label("Within"))
			var scope_ob: OptionButton = OptionButton.new()
			_style_option(scope_ob)
			for i: int in ConditionNodeData.QUERY_SCOPES.size():
				var sc: String = ConditionNodeData.QUERY_SCOPES[i]
				scope_ob.add_item("%s (%s)" % [ConditionNodeData.scope_name(sc),
					_trim_range(Ant.scope_range(sc))], i)
				if sc == node.scope:
					scope_ob.selected = i
			scope_ob.item_selected.connect(func(i: int) -> void:
				node.scope = ConditionNodeData.QUERY_SCOPES[i]
				_commit_edit()
				_render_vars())
			form_box.add_child(scope_ob)
			form_box.add_child(_form_label("Reads variable"))
			var key_le: LineEdit = LineEdit.new()
			key_le.text = node.var_key()
			key_le.editable = false
			_style_line_edit(key_le)
			key_le.add_theme_color_override("font_uneditable_color", COLORS["faint"])
			form_box.add_child(key_le)
		"compare":
			form_box.add_child(_form_label("Comparison"))
			var ob: OptionButton = OptionButton.new()
			_style_option(ob)
			for i: int in ConditionNodeData.CMP_OPS.size():
				var op: String = ConditionNodeData.CMP_OPS[i]
				ob.add_item(ConditionNodeData.op_name(op), i)
				if op == node.op:
					ob.selected = i
			ob.item_selected.connect(func(i: int) -> void:
				node.op = ConditionNodeData.CMP_OPS[i]
				_commit_edit())
			form_box.add_child(ob)
			form_box.add_child(_form_label("Operands"))
			var hint: Label = Label.new()
			hint.text = "Double-click the node to enter and edit its two values."
			hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			hint.add_theme_font_size_override("font_size", 11)
			hint.add_theme_color_override("font_color", COLORS["faint"])
			form_box.add_child(hint)
		"logic":
			form_box.add_child(_form_label("Name"))
			var le: LineEdit = LineEdit.new()
			le.text = node.label
			_style_line_edit(le)
			le.text_changed.connect(func(t: String) -> void:
				node.label = t
				insp_title.text = node.display_label()
				var w: GraphNodeWidget = widgets.get(node.id)
				if w:
					w.refresh()
				_repaint())
			le.text_submitted.connect(func(_t: String) -> void: _commit_edit())
			le.focus_exited.connect(_commit_edit)
			form_box.add_child(le)
			form_box.add_child(_form_label("Gate"))
			var ob: OptionButton = OptionButton.new()
			_style_option(ob)
			for i: int in ConditionNodeData.LOGIC_OPS.size():
				var op: String = ConditionNodeData.LOGIC_OPS[i]
				ob.add_item(ConditionNodeData.op_name(op), i)
				if op == node.op:
					ob.selected = i
			ob.item_selected.connect(func(i: int) -> void:
				node.op = ConditionNodeData.LOGIC_OPS[i]
				node.label = node.op.to_upper()
				_commit_edit())
			form_box.add_child(ob)
		"vector":
			form_box.add_child(_form_label("Operation"))
			var ob: OptionButton = OptionButton.new()
			_style_option(ob)
			for i: int in ConditionNodeData.VECTOR_OPS.size():
				var vop: String = ConditionNodeData.VECTOR_OPS[i]
				ob.add_item(ConditionNodeData.VECTOR_NAMES.get(vop, vop), i)
				if vop == node.op:
					ob.selected = i
			ob.item_selected.connect(func(i: int) -> void:
				node.op = ConditionNodeData.VECTOR_OPS[i]
				node.type = ConditionNodeData.vector_type_of(node.op)
				_commit_edit())
			form_box.add_child(ob)
			if node.op == "const":
				form_box.add_child(_form_label("Value"))
				var xy: HBoxContainer = HBoxContainer.new()
				xy.add_theme_constant_override("separation", 6)
				var sx: SpinBox = SpinBox.new()
				sx.min_value = -9999.0
				sx.max_value = 9999.0
				sx.step = 0.1
				sx.value = node.vec.x
				_style_spin(sx)
				var sy: SpinBox = SpinBox.new()
				sy.min_value = -9999.0
				sy.max_value = 9999.0
				sy.step = 0.1
				sy.value = node.vec.y
				_style_spin(sy)
				sx.value_changed.connect(func(v: float) -> void:
					node.vec.x = v
					insp_title.text = node.display_label()
					var w: GraphNodeWidget = widgets.get(node.id)
					if w:
						w.refresh()
					_repaint())
				sy.value_changed.connect(func(v: float) -> void:
					node.vec.y = v
					insp_title.text = node.display_label()
					var w: GraphNodeWidget = widgets.get(node.id)
					if w:
						w.refresh()
					_repaint())
				xy.add_child(sx)
				xy.add_child(sy)
				form_box.add_child(xy)
			form_box.add_child(_form_label("Inputs"))
			var wants: Array = ConditionNodeData.VECTOR_INPUTS.get(node.op, [])
			var wiring: Label = Label.new()
			wiring.text = "none" if wants.is_empty() else "in order: %s" % ", ".join(
				PackedStringArray(wants))
			wiring.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			wiring.add_theme_font_size_override("font_size", 11)
			wiring.add_theme_color_override("font_color", COLORS["dim"])
			form_box.add_child(wiring)
			form_box.add_child(_form_label("What it does"))
			var help: Label = Label.new()
			help.text = ConditionNodeData.VECTOR_HELP.get(node.op, "")
			help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			help.add_theme_font_size_override("font_size", 11)
			help.add_theme_color_override("font_color", COLORS["faint"])
			form_box.add_child(help)

func _update_inspector() -> void:
	var ids: Array = selection.keys()
	if ids.is_empty() and not gate_selected:
		insp_empty.visible = true
		form_box.visible = false
		single_row.visible = false
		multi_box.visible = false
		insp_glyph.text = "\u00b7"
		insp_glyph.add_theme_color_override("font_color", COLORS["faint"])
		insp_title.text = "Inspector"
		return
	if ids.size() == 1 and not gate_selected:
		var r: Dictionary = _find(ids[0])
		if r.is_empty():
			return
		var node: ConditionNodeData = r["node"]
		insp_empty.visible = false
		form_box.visible = true
		single_row.visible = true
		multi_box.visible = false
		insp_glyph.text = node.glyph()
		insp_glyph.add_theme_color_override("font_color", COLORS[node.kind])
		insp_title.text = node.display_label()
		_build_inspector_form(node)
	else:
		insp_empty.visible = false
		form_box.visible = false
		single_row.visible = false
		multi_box.visible = true
		insp_glyph.text = "\u25a3" if not ConditionNodeData.ascii_mode else "#"
		insp_glyph.add_theme_color_override("font_color", COLORS["sel"])
		insp_title.text = "Selection"
		var parts: Array[String] = []
		if not ids.is_empty():
			parts.append("%d node%s" % [ids.size(), "s" if ids.size() > 1 else ""])
		if gate_selected:
			parts.append("gate")
		multi_count.text = " + ".join(parts) + " selected"


# ============================================================================
# Toolbar actions & shortcuts
# ============================================================================
func _on_arrange() -> void:
	positions[_focus().id] = {}
	_build_viewport(true)
	_toast("Arranged.")


func _unhandled_key_input(event: InputEvent) -> void:
	var k: InputEventKey = event as InputEventKey
	if k == null or not k.pressed:
		return
	var meta: bool = k.ctrl_pressed or k.meta_pressed
	if meta and k.keycode == KEY_C:
		if not selection.is_empty():
			_copy_selection()
			get_viewport().set_input_as_handled()
	elif meta and k.keycode == KEY_V:
		if not clipboard.is_empty():
			_paste_clipboard(null)
			get_viewport().set_input_as_handled()
	elif meta and (k.keycode == KEY_EQUAL or k.keycode == KEY_PLUS):
		_set_zoom(zoom * 1.2)
		get_viewport().set_input_as_handled()
	elif meta and k.keycode == KEY_MINUS:
		_set_zoom(zoom / 1.2)
		get_viewport().set_input_as_handled()
	elif k.keycode == KEY_DELETE:
		if not selection.is_empty():
			_delete_selection()
			get_viewport().set_input_as_handled()
	elif k.keycode == KEY_BACKSPACE:
		if not selection.is_empty():
			_delete_selection()
		else:
			_go_back()
		get_viewport().set_input_as_handled()
	elif k.keycode == KEY_ESCAPE:
		if not selection.is_empty() or gate_selected:
			spotlight = null
			_clear_selection()
		elif not expanded.is_empty():
			expanded.clear()
			spotlight = null
			_build_viewport(true)
		else:
			_go_back()
		get_viewport().set_input_as_handled()

func _setup_movable_panels() -> void:
	var pairs: Array = [
		[library_panel, library_panel.get_node("VBox/Head")],
		[vars_panel, vars_panel.get_node("VBox/Head")],
		[inspector_panel, inspector_panel.get_node("VBox/Head")],
	]
	for pair: Array in pairs:
		var panel: PanelContainer = pair[0]
		var handle: HBoxContainer = pair[1]
		handle.mouse_filter = Control.MOUSE_FILTER_STOP
		handle.mouse_default_cursor_shape = Control.CURSOR_MOVE
		handle.tooltip_text = "Drag to move"
		for child: Node in handle.get_children():
			var lab: Label = child as Label
			if lab != null:
				lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		handle.gui_input.connect(_on_panel_handle_input.bind(panel))


func _on_panel_handle_input(event: InputEvent, panel: PanelContainer) -> void:
	var mb: InputEventMouseButton = event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if drag_mode != DragMode.NONE:
		return
	_float_panel(panel)
	panel.move_to_front()
	drag_mode = DragMode.PANEL
	drag_button = MOUSE_BUTTON_LEFT
	drag_panel = panel
	panel_grab = panel.global_position - get_global_mouse_position()
	get_viewport().set_input_as_handled()


## Detach a panel from its scene anchors the first time it is dragged, keeping
## exactly the rect it already occupied.
func _float_panel(panel: PanelContainer) -> void:
	var key: int = panel.get_instance_id()
	if free_panels.has(key):
		return
	var here: Vector2 = panel.position
	var box: Vector2 = panel.size
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT, false)
	panel.position = here
	panel.size = box
	free_panels[key] = true


func _clamp_panel(panel: PanelContainer) -> void:
	if not free_panels.has(panel.get_instance_id()):
		return
	var lim: Vector2 = size - panel.size
	panel.position = Vector2(
		clampf(panel.position.x, PANEL_EDGE, maxf(PANEL_EDGE, lim.x - PANEL_EDGE)),
		clampf(panel.position.y, PANEL_EDGE, maxf(PANEL_EDGE, lim.y - PANEL_EDGE)))

func _setup_ui_scale() -> void:
	ui_scale_slider.min_value = MIN_UI_SCALE
	ui_scale_slider.max_value = MAX_UI_SCALE
	ui_scale_slider.step = UI_SCALE_STEP
	ui_scale_slider.focus_mode = Control.FOCUS_NONE
	ui_scale_slider.tooltip_text = "Interface size"
	ui_scale_slider.value_changed.connect(_on_ui_scale_changed)
	_set_ui_scale(_auto_ui_scale())


## Starting point for a fresh install: match the layout's authored height.
func _auto_ui_scale() -> float:
	return clampf(float(get_window().size.y) / DESIGN_HEIGHT, MIN_UI_SCALE, MAX_UI_SCALE)


func _on_ui_scale_changed(value: float) -> void:
	_set_ui_scale(value)


func _set_ui_scale(value: float) -> void:
	ui_scale = clampf(snappedf(value, UI_SCALE_STEP), MIN_UI_SCALE, MAX_UI_SCALE)
	get_window().content_scale_factor = ui_scale
	ui_scale_slider.set_value_no_signal(ui_scale)
	ui_scale_label.text = "%d%%" % roundi(ui_scale * 100.0)
	# Stage size is reported in the new logical units only after this frame.
	call_deferred("_after_ui_scale")


func _after_ui_scale() -> void:
	for p: PanelContainer in [library_panel, vars_panel, inspector_panel]:
		_clamp_panel(p)
	_build_viewport(true)
