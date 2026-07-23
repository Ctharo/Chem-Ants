class_name ConditionGraphEditor
extends Control
## Runtime condition-graph editor scene (not a @tool plugin).
##
## Ported from an HTML/JS mockup. Interaction model:
##   Single click gate .... expand/collapse in place; active branch stays bright
##   Single click leaf .... select (edit in the Inspector)
##   Double click gate .... enter it (drill down); Back / Esc / breadcrumb = exit
##   Drag node ............ move (per-layer); Ctrl+click / drag-blank = select
##   Drag OUT port ........ wire downstream (into a gate, the rail, or blank = create)
##   Drag IN / rail port .. wire upstream (add / create an input)
##   Pan .................. wheel, middle-drag, or Space + drag
##   Zoom ................. Ctrl + wheel or the -/+ controls
##   Right click .......... context menu (add nodes, insert saved conditions)

const COLORS := {
	"bg": Color("0a0f14"), "grid": Color(0.47, 0.65, 0.76, 0.055),
	"panel": Color("0e151d"), "surface": Color("141e28"), "surface_hi": Color("1a2632"),
	"line": Color("243444"), "text": Color("e7eef4"), "dim": Color("8ea0b0"),
	"faint": Color("566878"), "logic": Color("38d3c2"), "compare": Color("f2b45c"),
	"property": Color("78d67e"), "literal": Color("b596f2"), "focus": Color("e7eef4"),
	"sel": Color("5ab0ff"), "true": Color("4bd88a"), "false": Color("ff6274"),
}

const V_GAP := 24.0       # vertical gap between sibling subtrees
const GUTTER := 56.0      # left gutter for auto-layout
const COL_GAP := 70.0     # horizontal gap between a parent and its children
const RAIL_W := 130.0
const RAIL_H := 112.0
const CLICK_SLOP := 4.0
const SINGLE_CLICK_DELAY := 0.27
const MIN_ZOOM := 0.4
const MAX_ZOOM := 2.0

enum DragMode { NONE, NODE_PENDING, NODE, MARQUEE_PENDING, MARQUEE, PAN, WIRE }

# --- document state ---------------------------------------------------------
var behavior_title := "Engage Target"
var tree_root: ConditionNodeData
var path: Array[ConditionNodeData] = []
var selection: Dictionary = {}          # id -> true
var gate_selected := false
var expanded: Dictionary = {}           # id -> true
var prev_visible: Dictionary = {}       # id -> true
var spotlight: Variant = null           # null | Dictionary id -> true
var positions: Dictionary = {}          # layer id -> {node id: Vector2}
var test_vars: Dictionary = {}
var clipboard: Array[ConditionNodeData] = []
var groups: Array[Dictionary] = []      # {"id", "name", "root": ConditionNodeData}
var dirty_pkg: Variant = null           # null | {"node", "group"}
var zoom := 1.0
var content_size := Vector2(100, 100)

# --- render state -----------------------------------------------------------
var widgets: Dictionary = {}            # id -> GraphNodeWidget
var node_pos: Dictionary = {}           # id -> Vector2 (layout target positions)
var visible_nodes: Array[ConditionNodeData] = []
var parent_of: Dictionary = {}          # id -> ConditionNodeData
var ui_font: Font

# --- interaction state ------------------------------------------------------
var drag_mode: DragMode = DragMode.NONE
var drag_widget: GraphNodeWidget = null
var drag_button := MOUSE_BUTTON_LEFT
var drag_start_screen := Vector2.ZERO
var drag_start_world := Vector2.ZERO
var drag_move_ids: Array[String] = []
var drag_starts: Dictionary = {}
var drag_was_double := false
var drag_was_ctrl := false
var pan_start_pos := Vector2.ZERO
var wire_node: ConditionNodeData = null
var wire_dir := "out"
var wire_from := Vector2.ZERO
var marquee_add := false
var marquee_base: Dictionary = {}
var _click_token := 0
var _nav_tween: Tween = null

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

var rail: OutputRailWidget = null
var _toast_tween: Tween = null


# ============================================================================
# Output rail (custom-drawn, built in code)
# ============================================================================
class OutputRailWidget extends Control:
	signal rail_clicked
	signal rail_port_pressed(event: InputEventMouseButton)

	var colors: Dictionary
	var font: Font
	var glyph_text := ""
	var glyph_color := Color.WHITE
	var gate_name := ""
	var out_state: Variant = null   # null / true / false
	var selected := false
	var _port: GraphNodeWidget.Port

	func _init(p_colors: Dictionary, p_font: Font) -> void:
		colors = p_colors
		font = p_font
		size = Vector2(130, 112)
		mouse_filter = Control.MOUSE_FILTER_STOP
		_port = GraphNodeWidget.Port.new()
		_port.dir = "in"
		_port.color = colors["focus"]
		_port.position = Vector2(-8, size.y * 0.5 - 8)
		_port.port_down.connect(func(_d: String, ev: InputEventMouseButton) -> void:
			rail_port_pressed.emit(ev))
		add_child(_port)

	func port_point() -> Vector2:
		return position + Vector2(-6.0, size.y * 0.5)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			rail_clicked.emit()

	func _draw() -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("121c26")
		sb.set_corner_radius_all(14)
		sb.set_border_width_all(1)
		sb.border_color = Color("33475a")
		sb.shadow_color = Color(0, 0, 0, 0.5)
		sb.shadow_size = 14
		sb.shadow_offset = Vector2(0, 8)
		if selected:
			sb.border_color = colors["sel"]
			sb.set_border_width_all(2)
		elif out_state is bool:
			var ec: Color = colors["true"] if out_state else colors["false"]
			sb.border_color = Color(ec, 0.7)
			sb.shadow_color = Color(ec, 0.25)
		draw_style_box(sb, Rect2(Vector2.ZERO, size))
		var cx := size.x * 0.5
		var t := "OUTPUT"
		var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
		draw_string(font, Vector2(cx - w * 0.5, 24), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
			colors["faint"])
		var gtxt := glyph_text + "  " + gate_name
		w = font.get_string_size(gtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		w = minf(w, size.x - 16)
		draw_string(font, Vector2(cx - w * 0.5, 52), gtxt, HORIZONTAL_ALIGNMENT_LEFT,
			int(size.x - 16), 13, glyph_color)
		var vtxt := "?"
		var vcol: Color = colors["dim"]
		if out_state is bool:
			vtxt = "TRUE" if out_state else "FALSE"
			vcol = colors["true"] if out_state else colors["false"]
		w = font.get_string_size(vtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var chip := Rect2(cx - w * 0.5 - 10, 68, w + 20, 26)
		var csb := StyleBoxFlat.new()
		csb.bg_color = colors["panel"]
		csb.set_corner_radius_all(7)
		draw_style_box(csb, chip)
		draw_string(font, Vector2(cx - w * 0.5, 86), vtxt, HORIZONTAL_ALIGNMENT_LEFT, -1,
			13, vcol)


# ============================================================================
# Lifecycle
# ============================================================================
func _ready() -> void:
	ui_font = get_theme_default_font()
	_check_glyph_coverage()
	_build_sample_document()
	_apply_styles()
	_connect_chrome()
	rail = OutputRailWidget.new(COLORS, ui_font)
	rail.rail_clicked.connect(_on_rail_clicked)
	rail.rail_port_pressed.connect(_on_rail_port_pressed)
	world.add_child(rail)
	world.move_child(rail, world.get_child_count() - 1)
	behavior_label.text = behavior_title
	stage.resized.connect(func() -> void: _build_viewport(true))
	grid_layer.draw.connect(_draw_grid)
	path = [tree_root]
	call_deferred("_render_all")


func _check_glyph_coverage() -> void:
	var needed := "\u2227\u2228\u00ac\u2295\u2264\u2265\u2260\u25c6\u25b8\u25be\u25a3"
	for i in needed.length():
		if not ui_font.has_char(needed.unicode_at(i)):
			ConditionNodeData.ascii_mode = true
			return


func _build_sample_document() -> void:
	var D := ConditionNodeData
	tree_root = D.make("logic", "and", "bool", "AND", [
		D.make("logic", "or", "bool", "target acquired", [
			D.make("compare", "lt", "bool", "", [
				D.make("property", "", "float", "distance_to_target"),
				D.make("literal", "", "float", "15.0"),
			]),
			D.make("property", "", "bool", "has_line_of_sight"),
		]),
		D.make("logic", "not", "bool", "not reloading", [
			D.make("property", "", "bool", "is_reloading"),
		]),
		D.make("compare", "gt", "bool", "", [
			D.make("property", "", "float", "current_health"),
			D.make("literal", "", "float", "25.0"),
		]),
	])
	test_vars = {
		"distance_to_target": 10.0, "has_line_of_sight": true,
		"is_reloading": false, "current_health": 50.0, "energy": 80.0,
		"distance_to_base": 60.0, "distance_to_food": 40.0, "is_carrying_food": false,
	}


# ============================================================================
# Styling helpers
# ============================================================================
func _panel_style(bg: Color, border: Color, radius := 13, margin := 13) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 14
	sb.shadow_offset = Vector2(0, 8)
	return sb


func _style_button(btn: Button, kind := "normal") -> void:
	var normal := StyleBoxFlat.new()
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
	var sb := StyleBoxFlat.new()
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


func _style_option(ob: OptionButton) -> void:
	_style_button(ob)
	ob.add_theme_font_size_override("font_size", 13)


func _tiny_label(text: String, color: Color, font_size := 9) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


func _apply_styles() -> void:
	var top_sb := StyleBoxFlat.new()
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
	for entry in [["logic", "logic"], ["compare", "compare"], ["property", "prop"],
			["literal", "const"]]:
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 5)
		var sw := ColorRect.new()
		sw.custom_minimum_size = Vector2(9, 9)
		sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sw.color = COLORS[entry[0]]
		h.add_child(sw)
		h.add_child(_tiny_label(entry[1], COLORS["dim"], 10))
		legend_box.add_child(h)


func _connect_chrome() -> void:
	stage.gui_input.connect(_on_stage_gui_input)
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
	var s := grid_layer.size
	var step := 34.0
	var x := 0.0
	while x < s.x:
		grid_layer.draw_line(Vector2(x, 0), Vector2(x, s.y), COLORS["grid"], 1.0)
		x += step
	var y := 0.0
	while y < s.y:
		grid_layer.draw_line(Vector2(0, y), Vector2(s.x, y), COLORS["grid"], 1.0)
		y += step


# ============================================================================
# Core helpers
# ============================================================================
func _focus() -> ConditionNodeData:
	return path[path.size() - 1]


func _find(id: String) -> Dictionary:
	return tree_root.find_with_parent(id)


func _layer_positions() -> Dictionary:
	var key := _focus().id
	if not positions.has(key):
		positions[key] = {}
	return positions[key]


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
	for c in crumbs_box.get_children():
		crumbs_box.remove_child(c)
		c.queue_free()
	var mk := func(text: String, index: int, current: bool) -> void:
		var b := Button.new()
		b.text = text
		b.disabled = current
		_style_button(b, "flat" if not current else "normal")
		b.add_theme_font_size_override("font_size", 12)
		if current:
			b.add_theme_color_override("font_disabled_color", COLORS["text"])
		else:
			b.pressed.connect(func() -> void: _go_to(index))
		crumbs_box.add_child(b)
	mk.call("entry", 0, path.size() == 1)
	for i in range(1, path.size()):
		var sep := _tiny_label(">" if ConditionNodeData.ascii_mode else "\u203a",
			COLORS["faint"], 11)
		sep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		crumbs_box.add_child(sep)
		mk.call(path[i].display_label(), i, i == path.size() - 1)


func _walk_visible(n: ConditionNodeData, parent: ConditionNodeData) -> void:
	visible_nodes.append(n)
	parent_of[n.id] = parent
	if expanded.has(n.id):
		for c in n.children:
			_walk_visible(c, n)


func _sub_height(n: ConditionNodeData) -> float:
	var h: float = widgets[n.id].size.y
	if not expanded.has(n.id) or n.children.is_empty():
		return h
	var s := 0.0
	for i in n.children.size():
		s += _sub_height(n.children[i]) + (V_GAP if i > 0 else 0.0)
	return maxf(h, s)


func _place_tree(n: ConditionNodeData, right_edge: float, top: float) -> void:
	var w: GraphNodeWidget = widgets[n.id]
	var s := _sub_height(n)
	var lp := _layer_positions()
	var pos: Vector2
	if lp.has(n.id):
		pos = lp[n.id]
	else:
		pos = Vector2(right_edge - w.size.x, top + s * 0.5 - w.size.y * 0.5)
	node_pos[n.id] = pos
	if expanded.has(n.id) and not n.children.is_empty():
		var kid_total := 0.0
		for i in n.children.size():
			kid_total += _sub_height(n.children[i]) + (V_GAP if i > 0 else 0.0)
		var cy := pos.y + w.size.y * 0.5 - kid_total * 0.5
		for c in n.children:
			_place_tree(c, pos.x - COL_GAP, cy)
			cy += _sub_height(c) + V_GAP


func _build_viewport(skip_anim := false) -> void:
	if not is_node_ready() or stage.size.x < 2:
		return
	var old_pos := node_pos.duplicate()
	for c in nodes_layer.get_children():
		nodes_layer.remove_child(c)
		c.queue_free()
	widgets.clear()
	node_pos.clear()
	visible_nodes.clear()
	parent_of.clear()
	var f := _focus()
	for c in f.children:
		_walk_visible(c, f)

	var appear_ids: Array[String] = []
	for n in visible_nodes:
		var w := GraphNodeWidget.new()
		w.setup(n, COLORS, ui_font)
		w.pointer_pressed.connect(_on_widget_pressed)
		w.context_requested.connect(_on_widget_context)
		w.port_pressed.connect(_on_port_pressed)
		nodes_layer.add_child(w)
		widgets[n.id] = w
		if not skip_anim and not prev_visible.has(n.id):
			appear_ids.append(n.id)

	# Layout (right-to-left tree; children sit left of their parent).
	var stage_size := stage.size
	var total := 0.0
	for i in f.children.size():
		total += _sub_height(f.children[i]) + (V_GAP if i > 0 else 0.0)
	var content_h := maxf(stage_size.y, total + 130.0)
	var col0 := stage_size.x - 250.0
	var y := maxf(44.0, content_h * 0.5 - total * 0.5)
	for r in f.children:
		_place_tree(r, col0, y)
		y += _sub_height(r) + V_GAP

	# Normalise: auto-layout hugs the gutter; hand-placed layers only get clamped.
	var min_l := INF
	var max_r := 0.0
	for n in visible_nodes:
		min_l = minf(min_l, node_pos[n.id].x)
		max_r = maxf(max_r, node_pos[n.id].x + widgets[n.id].size.x)
	if visible_nodes.is_empty():
		min_l = GUTTER
		max_r = GUTTER
	var manual := not _layer_positions().is_empty()
	var target_l := maxf(min_l, 20.0) if manual else GUTTER
	var shift := target_l - min_l
	if absf(shift) > 0.5:
		for n in visible_nodes:
			node_pos[n.id].x += shift
		max_r += shift

	var rail_x := maxf(stage_size.x - 150.0, max_r + 90.0)
	rail.position = Vector2(rail_x, content_h * 0.5 - RAIL_H * 0.5)
	content_size = Vector2(maxf(stage_size.x, rail_x + 150.0), content_h)
	world.size = content_size
	trace_layer.position = Vector2.ZERO
	trace_layer.size = content_size
	grid_layer.queue_redraw()
	_apply_zoom()

	# Commit widget positions (animate movers / newcomers unless told to skip).
	for n in visible_nodes:
		var w: GraphNodeWidget = widgets[n.id]
		w.expanded = expanded.has(n.id)
		var target: Vector2 = node_pos[n.id]
		if skip_anim:
			w.position = target
		elif old_pos.has(n.id):
			w.position = old_pos[n.id]
			if w.position.distance_to(target) > 0.5:
				var tw := create_tween()
				tw.tween_property(w, "position", target, 0.32) \
					.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			else:
				w.position = target
		else:
			w.position = target + Vector2(42, 0)
			w.modulate.a = 0.0
			var delay := appear_ids.find(n.id) * 0.028
			var tw := create_tween().set_parallel(true)
			tw.tween_property(w, "position", target, 0.3).set_delay(delay) \
				.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
			tw.tween_property(w, "modulate:a", 1.0, 0.28).set_delay(delay)
	prev_visible.clear()
	for n in visible_nodes:
		prev_visible[n.id] = true
	_repaint()


func _apply_zoom() -> void:
	world.scale = Vector2(zoom, zoom)
	_clamp_pan()
	zoom_label_btn.text = "%d%%" % roundi(zoom * 100.0)


func _clamp_pan() -> void:
	var lim := stage.size - content_size * zoom
	world.position.x = clampf(world.position.x, minf(0.0, lim.x), 0.0)
	world.position.y = clampf(world.position.y, minf(0.0, lim.y), 0.0)


func _set_zoom(nz: float, stage_point: Variant = null) -> void:
	var sp: Vector2 = stage_point if stage_point != null else stage.size * 0.5
	var wp := (sp - world.position) / zoom
	zoom = clampf(nz, MIN_ZOOM, MAX_ZOOM)
	world.position = sp - wp * zoom
	_apply_zoom()


func _out_point(n: ConditionNodeData) -> Vector2:
	var w: GraphNodeWidget = widgets[n.id]
	return node_pos[n.id] + Vector2(w.size.x + 6.0, w.size.y * 0.5)


func _in_point(n: ConditionNodeData) -> Vector2:
	var w: GraphNodeWidget = widgets[n.id]
	return node_pos[n.id] + Vector2(-6.0, w.size.y * 0.5)


## Recompute evaluation, selection, spotlight and traces in one pass.
func _repaint() -> void:
	var eval_cache := {}
	for n in visible_nodes:
		eval_cache[n.id] = n.evaluate(test_vars)

	for n in visible_nodes:
		var w: GraphNodeWidget = widgets[n.id]
		var r: Dictionary = eval_cache[n.id]
		w.selected = selection.has(n.id)
		w.dimmed = spotlight != null and not (spotlight as Dictionary).has(n.id)
		w.expanded = expanded.has(n.id)
		if r["is_bool"]:
			w.eval_state = r["value"]
			w.value_text = "?" if r["value"] == null else ("true" if r["value"] else "false")
		else:
			w.eval_state = null
			var v: float = r["value"]
			w.value_text = str(roundi(v)) if n.type == "int" else str(v)
		w.refresh()
		w.position = w.position  # keep any running tween target; refresh may resize

	var traces: Array[Dictionary] = []
	var rail_point := Vector2(rail.position.x - 6.0, rail.position.y + RAIL_H * 0.5)
	for n in visible_nodes:
		var p: ConditionNodeData = parent_of[n.id]
		var a := _out_point(n)
		var b := rail_point if p == _focus() else _in_point(p)
		var r: Dictionary = eval_cache[n.id]
		var col: Color = COLORS[n.kind]
		var alpha := 0.82
		var width := 2.0
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

	var g := _focus()
	var gr := g.evaluate(test_vars)
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
	var set := {id: true}
	for n in visible_nodes:
		var p: ConditionNodeData = parent_of.get(n.id)
		while p != null:
			if p.id == id:
				set[n.id] = true
				break
			p = parent_of.get(p.id)
	return set


func _collapse_from(id: String) -> void:
	var keep := {}
	for eid: String in expanded.keys():
		if eid == id:
			continue
		var p: ConditionNodeData = parent_of.get(eid)
		var desc := false
		while p != null:
			if p.id == id:
				desc = true
				break
			p = parent_of.get(p.id)
		if not desc:
			keep[eid] = true
	expanded = keep


func _visible_subtree_ids(id: String) -> Array[String]:
	var out: Array[String] = [id]
	var r := _find(id)
	if r.is_empty():
		return out
	var rec := func(n: ConditionNodeData, again: Callable) -> void:
		if expanded.has(n.id):
			for c in n.children:
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
	var s := selection.duplicate()
	if s.has(id):
		s.erase(id)
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
	var id := w.data.id
	drag_move_ids.clear()
	if selection.has(id):
		for sid: String in selection.keys():
			drag_move_ids.append(sid)
	else:
		drag_move_ids = _visible_subtree_ids(id)
	drag_starts.clear()
	for mid in drag_move_ids:
		if node_pos.has(mid):
			drag_starts[mid] = node_pos[mid]


func _single_click(node: ConditionNodeData) -> void:
	if node.is_gate() and not node.children.is_empty():
		if expanded.has(node.id):
			_collapse_from(node.id)
			spotlight = null
		else:
			var nxt := {node.id: true}
			for aid in _ancestors_of(node.id):
				nxt[aid] = true
			expanded = nxt
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
			var tw := create_tween()
			tw.tween_property(w, "position:x", w.position.x - 4, 0.07)
			tw.tween_property(w, "position:x", w.position.x + 4, 0.14)
			tw.tween_property(w, "position:x", w.position.x, 0.07)
		_toast("Leaf value - nothing inside.")


func _finish_node_click() -> void:
	var node := drag_widget.data
	if drag_was_ctrl:
		_toggle_select(node.id)
		return
	if drag_was_double:
		_double_click(node)
		return
	_click_token += 1
	var token := _click_token
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
	var w := _to_world(get_global_mouse_position())
	var tl := Vector2(minf(drag_start_world.x, w.x), minf(drag_start_world.y, w.y))
	var br := Vector2(maxf(drag_start_world.x, w.x), maxf(drag_start_world.y, w.y))
	marquee.position = tl
	marquee.size = br - tl
	var sel := marquee_base.duplicate()
	for n in visible_nodes:
		var r := Rect2(node_pos[n.id], widgets[n.id].size)
		if r.intersects(Rect2(tl, br - tl)):
			sel[n.id] = true
	_set_selection(sel)


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
	var gp := get_global_mouse_position()
	match drag_mode:
		DragMode.NODE_PENDING:
			if gp.distance_to(drag_start_screen) > CLICK_SLOP:
				drag_mode = DragMode.NODE
				_drag_motion()
		DragMode.NODE:
			var delta := _to_world(gp) - drag_start_world
			var lp := _layer_positions()
			for mid in drag_move_ids:
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


func _drag_release() -> void:
	var mode := drag_mode
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


func _widget_at(world_point: Vector2, exclude_id := "") -> GraphNodeWidget:
	var kids := nodes_layer.get_children()
	for i in range(kids.size() - 1, -1, -1):
		var w := kids[i] as GraphNodeWidget
		if w == null or w.data.id == exclude_id:
			continue
		if Rect2(w.position, w.size).has_point(world_point):
			return w
	return null


func _rail_at(world_point: Vector2) -> bool:
	return Rect2(rail.position, rail.size).has_point(world_point)


func _finish_wire() -> void:
	var wp := _to_world(get_global_mouse_position())
	var target := _widget_at(wp, wire_node.id)
	var on_rail := _rail_at(wp)
	if wire_dir == "out":
		if target:
			var t := target.data
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
			var s := target.data
			if not s.contains_id(wire_node.id):
				_reparent(s, wire_node)
				_toast("%s feeds %s." % [s.label, wire_node.label])
			else:
				_toast("Can't create a loop.")
		elif on_rail:
			_toast("The rail is the output, not an input.")
		else:
			var upstream := wire_node
			_open_create_menu(wp, func(kind: String, op: String) -> void:
				var n := ConditionNodeData.create(kind, op)
				upstream.children.append(n)
				if upstream != _focus():
					expanded[upstream.id] = true
				_layer_positions()[n.id] = wp
				_mark_pkg_dirty()
				_build_viewport(true)
				_set_selection({n.id: true}, false)
				_toast("Input node created."))


func _insert_in_wire(kind: String, op: String, wp: Vector2) -> void:
	var n := ConditionNodeData.create(kind, op)
	var found := _find(wire_node.id)
	var par: ConditionNodeData = found.get("parent") if not found.is_empty() else null
	if par == null:
		par = _focus()
	var idx := par.children.find(wire_node)
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


func _reparent(child: ConditionNodeData, new_parent: ConditionNodeData) -> void:
	var found := _find(child.id)
	var old_parent: ConditionNodeData = found.get("parent") if not found.is_empty() else null
	if old_parent == null or old_parent == new_parent:
		return
	old_parent.children.erase(child)
	new_parent.children.append(child)
	if new_parent != _focus():
		expanded[new_parent.id] = true
	_mark_pkg_dirty()
	_build_viewport(true)


# ============================================================================
# Navigation
# ============================================================================
func _reset_view_state() -> void:
	selection.clear()
	gate_selected = false
	expanded.clear()
	spotlight = null


func _enter(node: ConditionNodeData, origin: Variant) -> void:
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
	var start := zoom * (0.5 if entering else 1.32)
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
	var ids := selection.keys()
	if ids.is_empty():
		return
	for id: String in ids:
		var r := _find(id)
		if not r.is_empty() and r["parent"] != null:
			(r["parent"] as ConditionNodeData).children.erase(r["node"])
		_layer_positions().erase(id)
	selection.clear()
	spotlight = null
	_mark_pkg_dirty()
	_build_viewport(true)
	_update_inspector()
	_toast("%d deleted." % ids.size() if ids.size() > 1 else "Deleted.")


func _copy_selection() -> void:
	var ids := selection.keys()
	if ids.is_empty():
		return
	clipboard.clear()
	for id: String in ids:
		var r := _find(id)
		if not r.is_empty():
			clipboard.append((r["node"] as ConditionNodeData).clone_new())
	_toast("%d copied." % ids.size() if ids.size() > 1 else "Copied.")


func _paste_clipboard(pos: Variant) -> void:
	if clipboard.is_empty():
		return
	var f := _focus()
	var added := {}
	var base: Vector2 = pos if pos != null else Vector2(80, 80)
	for i in clipboard.size():
		var c := clipboard[i].clone_new()
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
		var r := _find(id)
		if r.is_empty():
			continue
		var covered := false
		var p: ConditionNodeData = r["parent"]
		while p != null:
			if selection.has(p.id):
				covered = true
				break
			var pr := _find(p.id)
			p = pr.get("parent") if not pr.is_empty() else null
		if not covered:
			out.append(r["node"])
	return out


func _save_condition() -> void:
	var f := _focus()
	var tops := _selected_top_nodes()
	var root: ConditionNodeData = null
	if gate_selected:
		var sel_kids: Array[ConditionNodeData] = []
		for c in f.children:
			if selection.has(c.id):
				sel_kids.append(c)
		var source := sel_kids if not sel_kids.is_empty() else f.children
		root = f.clone_exact()
		root.id = ConditionNodeData.new_id()
		root.pkg_id = ""
		root.pkg_name = ""
		root.children.clear()
		for c in source:
			root.children.append(c.clone_new())
	elif tops.size() == 1:
		root = tops[0].clone_new()
	elif tops.size() > 1:
		root = ConditionNodeData.create("logic", "and")
		root.label = "combined"
		root.children.clear()
		for t in tops:
			root.children.append(t.clone_new())
	else:
		_toast("Select some nodes (or the Output rail) first.")
		return
	var name := await _prompt("Save as condition",
		"Reuse it later. It drops in as one collapsed package node.",
		root.display_label() if root.display_label() != "" else "condition")
	if name == "":
		return
	root.pkg_id = ""
	root.pkg_name = ""
	root.label = name
	groups.append({"id": ConditionNodeData.new_id(), "name": name,
		"root": root.clone_exact()})
	_render_library()
	cond_btn.button_pressed = true
	_toast("Saved \"%s\"." % name)


func _insert_condition(g: Dictionary, pos: Variant) -> void:
	var c: ConditionNodeData = (g["root"] as ConditionNodeData).clone_new()
	c.pkg_id = g["id"]
	c.pkg_name = g["name"]
	c.label = g["name"]
	_focus().children.append(c)
	_layer_positions()[c.id] = pos if pos != null else Vector2(90, 90)
	_mark_pkg_dirty()
	_build_viewport(true)
	_set_selection({c.id: true}, false)
	_toast("Inserted \"%s\"." % g["name"])


func _render_library() -> void:
	cond_btn.text = "Conditions \u00b7 %d" % groups.size()
	for c in group_list.get_children():
		group_list.remove_child(c)
		c.queue_free()
	if groups.is_empty():
		var l := Label.new()
		l.text = "Select nodes (add the Output rail for the gate), then \"Save as condition\". Reuses as one package."
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_font_size_override("font_size", 11)
		l.add_theme_color_override("font_color", COLORS["faint"])
		group_list.add_child(l)
		return
	for g in groups:
		var b := Button.new()
		b.text = "%s  %s" % [(g["root"] as ConditionNodeData).glyph(), g["name"]]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.tooltip_text = "Insert into the current level"
		_style_button(b)
		var gg := g
		b.pressed.connect(func() -> void: _insert_condition(gg, null))
		group_list.add_child(b)


# ---- linked-instance edit prompt ----
func _nearest_pkg_in_path() -> ConditionNodeData:
	for i in range(path.size() - 1, 0, -1):
		if path[i].pkg_id != "":
			return path[i]
	return null


func _mark_pkg_dirty() -> void:
	var p := _nearest_pkg_in_path()
	if p == null:
		return
	for g in groups:
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
	var tmpl := node.clone_exact()
	tmpl.pkg_id = ""
	tmpl.pkg_name = ""
	tmpl.label = group["name"]
	group["root"] = tmpl
	var instances: Array = []
	tree_root.collect_instances(group["id"], instances)
	for inst: ConditionNodeData in instances:
		if inst == node:
			continue
		var fresh := (group["root"] as ConditionNodeData).clone_new()
		inst.children = fresh.children
		inst.label = group["name"]
	_hide_pkg_bar()
	_render_library()
	_build_viewport(true)
	_toast("Updated \"%s\" everywhere." % group["name"])


func _pkg_save_as_new() -> void:
	if dirty_pkg == null:
		return
	var node: ConditionNodeData = dirty_pkg["node"]
	var name := await _prompt("Save as new condition",
		"Detaches this instance; other uses stay unchanged.", node.pkg_name + " v2")
	if name == "":
		return
	var root := node.clone_exact()
	root.pkg_id = ""
	root.pkg_name = ""
	root.label = name
	var g := {"id": ConditionNodeData.new_id(), "name": name, "root": root}
	groups.append(g)
	node.pkg_id = g["id"]
	node.pkg_name = name
	node.label = name
	_hide_pkg_bar()
	_render_library()
	_build_viewport(true)
	_toast("Saved as \"%s\"." % name)


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
func _swatch_icon(color: Color) -> ImageTexture:
	var img := Image.create(9, 9, false, Image.FORMAT_RGBA8)
	img.fill(color)
	return ImageTexture.create_from_image(img)


## items: Array of Dictionaries:
##   {"label": String, "action": Callable} plus optional
##   "disabled": bool, "icon": Texture2D, "sep": bool, "title": String
func _show_menu(items: Array) -> void:
	var pm := PopupMenu.new()
	pm.add_theme_font_size_override("font_size", 12)
	var actions: Array[Callable] = []
	for it: Dictionary in items:
		if it.get("sep", false):
			pm.add_separator()
			continue
		if it.has("title"):
			pm.add_separator(it["title"])
			continue
		var idx := pm.item_count
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
	var node := w.data
	if not selection.has(node.id):
		_set_selection({node.id: true}, false)
	var count := selection.size()
	var items: Array = []
	if node.is_gate():
		items.append({"label": "Enter", "action": func() -> void:
			_double_click(node)})
		if not node.children.is_empty():
			items.append({"label": "Collapse" if expanded.has(node.id) else "Expand",
				"action": func() -> void: _single_click(node)})
	items.append({"label": "Copy (%d)" % count if count > 1 else "Copy",
		"action": _copy_selection})
	items.append({"label": "Save as condition...", "action": _save_condition})
	items.append({"sep": true})
	items.append({"label": "Delete (%d)" % count if count > 1 else "Delete",
		"action": _delete_selection})
	_show_menu(items)


func _open_blank_menu(wp: Vector2) -> void:
	var items: Array = [{"title": "Add node"}]
	var defs := [
		["logic", "and", "Logic - AND"], ["logic", "or", "Logic - OR"],
		["logic", "not", "Logic - NOT"], ["compare", "lt", "Comparison"],
		["property", "", "Property"], ["literal", "", "Constant"],
	]
	for d in defs:
		var kind: String = d[0]
		var op: String = d[1]
		items.append({"label": d[2], "icon": _swatch_icon(COLORS[kind]),
			"action": func() -> void: _add_node(ConditionNodeData.create(kind, op), wp)})
	if not groups.is_empty():
		items.append({"sep": true})
		for g in groups:
			var gg: Dictionary = g
			items.append({"label": "[%s]" % gg["name"],
				"action": func() -> void: _insert_condition(gg, wp)})
	items.append({"sep": true})
	items.append({"label": "Paste", "disabled": clipboard.is_empty(),
		"action": func() -> void: _paste_clipboard(wp)})
	_show_menu(items)


func _open_create_menu(_wp: Vector2, cb: Callable) -> void:
	var items: Array = [{"title": "Wire into new node"}]
	var defs := [
		["logic", "and", "Logic - AND"], ["logic", "or", "Logic - OR"],
		["compare", "lt", "Comparison"], ["property", "", "Property"],
		["literal", "", "Constant"],
	]
	for d in defs:
		var kind: String = d[0]
		var op: String = d[1]
		items.append({"label": d[2], "icon": _swatch_icon(COLORS[kind]),
			"action": func() -> void: cb.call(kind, op)})
	_show_menu(items)


# ============================================================================
# Variables panel
# ============================================================================
func _var_type(name: String) -> String:
	return "bool" if test_vars.get(name) is bool else "float"


func _render_vars() -> void:
	tree_root.seed_vars(test_vars)
	for c in vars_list.get_children():
		vars_list.remove_child(c)
		c.queue_free()
	for name: String in test_vars.keys():
		var wrap := VBoxContainer.new()
		wrap.add_theme_constant_override("separation", 4)
		var head := HBoxContainer.new()
		var nl := _tiny_label(name, COLORS["text"], 12)
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(nl)
		wrap.add_child(head)
		if test_vars[name] is bool:
			var cb := CheckButton.new()
			cb.button_pressed = test_vars[name]
			cb.text = "true" if test_vars[name] else "false"
			cb.add_theme_font_size_override("font_size", 11)
			cb.add_theme_color_override("font_color", COLORS["dim"])
			cb.focus_mode = Control.FOCUS_NONE
			var vn := name
			cb.toggled.connect(func(on: bool) -> void:
				test_vars[vn] = on
				cb.text = "true" if on else "false"
				_repaint())
			wrap.add_child(cb)
		else:
			var vl := _tiny_label(str(test_vars[name]), COLORS["property"], 12)
			head.add_child(vl)
			var slider := HSlider.new()
			slider.min_value = 0
			slider.max_value = 100
			slider.step = 0.5
			slider.value = float(test_vars[name])
			slider.focus_mode = Control.FOCUS_NONE
			var vn := name
			slider.value_changed.connect(func(v: float) -> void:
				test_vars[vn] = v
				vl.text = str(v)
				_repaint())
			wrap.add_child(slider)
		vars_list.add_child(wrap)


# ============================================================================
# Inspector
# ============================================================================
func _form_label(text: String) -> Label:
	return _tiny_label(text.to_upper(), COLORS["faint"], 9)


func _commit_edit() -> void:
	_mark_pkg_dirty()
	_build_viewport(true)
	_update_inspector()


func _build_inspector_form(node: ConditionNodeData) -> void:
	for c in form_box.get_children():
		form_box.remove_child(c)
		c.queue_free()
	match node.kind:
		"literal":
			form_box.add_child(_form_label("Value"))
			var le := LineEdit.new()
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
			var ob := OptionButton.new()
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
			var ob := OptionButton.new()
			_style_option(ob)
			var names: Array = test_vars.keys()
			for i in names.size():
				ob.add_item("%s \u00b7 %s" % [names[i], _var_type(names[i])], i)
				if names[i] == node.label:
					ob.selected = i
			ob.add_item("+ new variable...", names.size())
			ob.item_selected.connect(func(i: int) -> void:
				if i >= names.size():
					var nm := await _prompt("New variable",
						"Add a test variable to track.", "new_var")
					if nm == "":
						_update_inspector()
						return
					if not test_vars.has(nm):
						test_vars[nm] = 0.0
					node.label = nm
				else:
					node.label = names[i]
				node.type = _var_type(node.label)
				_commit_edit()
				_render_vars())
			form_box.add_child(ob)
			form_box.add_child(_form_label("Value type"))
			var tle := LineEdit.new()
			tle.text = node.type
			tle.editable = false
			_style_line_edit(tle)
			tle.add_theme_color_override("font_uneditable_color", COLORS["faint"])
			form_box.add_child(tle)
		"compare":
			form_box.add_child(_form_label("Comparison"))
			var ob := OptionButton.new()
			_style_option(ob)
			for i in ConditionNodeData.CMP_OPS.size():
				var op: String = ConditionNodeData.CMP_OPS[i]
				ob.add_item(ConditionNodeData.op_name(op), i)
				if op == node.op:
					ob.selected = i
			ob.item_selected.connect(func(i: int) -> void:
				node.op = ConditionNodeData.CMP_OPS[i]
				_commit_edit())
			form_box.add_child(ob)
			form_box.add_child(_form_label("Operands"))
			var hint := Label.new()
			hint.text = "Double-click the node to enter and edit its two values."
			hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			hint.add_theme_font_size_override("font_size", 11)
			hint.add_theme_color_override("font_color", COLORS["faint"])
			form_box.add_child(hint)
		"logic":
			form_box.add_child(_form_label("Name"))
			var le := LineEdit.new()
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
			var ob := OptionButton.new()
			_style_option(ob)
			for i in ConditionNodeData.LOGIC_OPS.size():
				var op: String = ConditionNodeData.LOGIC_OPS[i]
				ob.add_item(ConditionNodeData.op_name(op), i)
				if op == node.op:
					ob.selected = i
			ob.item_selected.connect(func(i: int) -> void:
				node.op = ConditionNodeData.LOGIC_OPS[i]
				node.label = node.op.to_upper()
				_commit_edit())
			form_box.add_child(ob)


func _update_inspector() -> void:
	var ids := selection.keys()
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
		var r := _find(ids[0])
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
	var k := event as InputEventKey
	if k == null or not k.pressed:
		return
	var meta := k.ctrl_pressed or k.meta_pressed
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
