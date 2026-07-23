class_name GraphNodeWidget
extends Control
## One card in the condition graph. Fully custom-drawn so it can be measured
## synchronously during layout. Emits raw pointer signals; the editor owns all
## interaction logic (click vs double-click vs drag, selection, wiring).

signal pointer_pressed(widget: GraphNodeWidget, event: InputEventMouseButton)
signal context_requested(widget: GraphNodeWidget, event: InputEventMouseButton)
signal port_pressed(widget: GraphNodeWidget, dir: String, event: InputEventMouseButton)

const MIN_W := 148.0
const MAX_W := 260.0
const PAD_X := 13.0
const PAD_TOP := 10.0
const PAD_BOT := 11.0
const ROW_GAP := 5.0
const GLYPH_BOX := 22.0
const LABEL_MAX_W := MAX_W - PAD_X * 2.0

var data: ConditionNodeData
var theme_colors: Dictionary = {} # supplied by the editor

var selected := false
var dimmed := false
var expanded := false
var hovered := false
## null (no bool result), true, or false
var eval_state: Variant = null
var value_text := ""

var _font: Font
var _label_size := Vector2.ZERO
var _in_port: Control = null
var _out_port: Control = null


class Port extends Control:
	signal port_down(dir: String, event: InputEventMouseButton)
	var dir := "out"
	var color := Color.WHITE
	var hovered := false

	func _ready() -> void:
		custom_minimum_size = Vector2(16, 16)
		size = Vector2(16, 16)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_CROSS
		mouse_entered.connect(func() -> void: hovered = true; queue_redraw())
		mouse_exited.connect(func() -> void: hovered = false; queue_redraw())

	func _draw() -> void:
		var c := size * 0.5
		var r := 7.0 if hovered else 6.0
		draw_circle(c, r + 3.0, Color(color, 0.14))
		draw_circle(c, r, color)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT \
				and event.pressed:
			accept_event()
			port_down.emit(dir, event)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_DRAG


func _ready() -> void:
	mouse_entered.connect(func() -> void: hovered = true; queue_redraw())
	mouse_exited.connect(func() -> void: hovered = false; queue_redraw())


func setup(p_data: ConditionNodeData, p_colors: Dictionary, p_font: Font) -> void:
	data = p_data
	theme_colors = p_colors
	_font = p_font
	if data.is_gate():
		_in_port = _make_port("in", theme_colors["focus"])
	_out_port = _make_port("out", accent_color())
	refresh()


func _make_port(dir: String, col: Color) -> Control:
	var p := Port.new()
	p.dir = dir
	p.color = col
	p.port_down.connect(func(d: String, ev: InputEventMouseButton) -> void:
		port_pressed.emit(self, d, ev))
	add_child(p)
	return p


func accent_color() -> Color:
	return theme_colors.get(data.kind, Color.WHITE)


## Recompute display strings, size, and port placement. Call after data changes.
func refresh() -> void:
	var kind_w := _font.get_string_size(data.kind_title(), HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	var head_w := GLYPH_BOX + 8.0 + kind_w + 12.0 + 9.0
	_label_size = _font.get_multiline_string_size(
		data.display_label(), HORIZONTAL_ALIGNMENT_LEFT, LABEL_MAX_W, 13)
	var type_w := _font.get_string_size(data.type, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 14.0
	var val_w := _font.get_string_size(value_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	var foot_w := type_w + 8.0 + val_w
	var inner := clampf(max(head_w, max(_label_size.x, foot_w)),
		MIN_W - PAD_X * 2.0, MAX_W - PAD_X * 2.0)
	var w := inner + PAD_X * 2.0
	var foot_h := 19.0
	var h := PAD_TOP + GLYPH_BOX + ROW_GAP + _label_size.y + ROW_GAP + foot_h + PAD_BOT
	size = Vector2(w, h)
	custom_minimum_size = size
	if _in_port:
		_in_port.position = Vector2(-8.0, h * 0.5 - 8.0)
	if _out_port:
		_out_port.position = Vector2(w - 8.0, h * 0.5 - 8.0)
		_out_port.color = accent_color()
	queue_redraw()


func in_port_point() -> Vector2:
	return position + Vector2(-6.0, size.y * 0.5)


func out_port_point() -> Vector2:
	return position + Vector2(size.x + 6.0, size.y * 0.5)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			accept_event()
			pointer_pressed.emit(self, event)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			accept_event()
			context_requested.emit(self, event)


func _draw() -> void:
	var accent := accent_color()
	var line: Color = theme_colors["line"]
	var rect := Rect2(Vector2.ZERO, size)

	# Card background.
	var sb := StyleBoxFlat.new()
	sb.bg_color = theme_colors["surface"]
	sb.set_corner_radius_all(12)
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_color = line
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 10
	sb.shadow_offset = Vector2(0, 5)
	if selected:
		sb.border_color = theme_colors["sel"]
		sb.set_border_width_all(2)
	elif eval_state is bool:
		var ec: Color = theme_colors["true"] if eval_state else theme_colors["false"]
		sb.border_color = Color(ec, 0.75 if eval_state else 0.6)
		sb.shadow_color = Color(ec, 0.28)
	elif hovered:
		sb.border_color = line.lerp(accent, 0.55)
	draw_style_box(sb, rect)

	# Accent bar.
	draw_rect(Rect2(0, 10, 3, size.y - 20), accent)

	var text_col: Color = theme_colors["text"]
	var dim_col: Color = theme_colors["dim"]
	var faint_col: Color = theme_colors["faint"]

	# Head row: glyph box, kind, status dot.
	var gy := PAD_TOP
	var gbox := Rect2(PAD_X, gy, GLYPH_BOX, GLYPH_BOX)
	draw_rect(gbox, Color(accent, 0.12))
	draw_rect(gbox, Color(accent, 0.4), false, 1.0)
	var gw := _font.get_string_size(data.glyph(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	draw_string(_font, Vector2(PAD_X + (GLYPH_BOX - gw) * 0.5, gy + 16.0),
		data.glyph(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, accent)
	draw_string(_font, Vector2(PAD_X + GLYPH_BOX + 8.0, gy + 15.0),
		data.kind_title(), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, accent)
	var dot_col := faint_col
	if eval_state is bool:
		dot_col = theme_colors["true"] if eval_state else theme_colors["false"]
	draw_circle(Vector2(size.x - PAD_X - 4.5, gy + GLYPH_BOX * 0.5), 4.5, dot_col)

	# Label (wrapped).
	var ly := gy + GLYPH_BOX + ROW_GAP
	draw_multiline_string(_font, Vector2(PAD_X, ly + 12.0), data.display_label(),
		HORIZONTAL_ALIGNMENT_LEFT, size.x - PAD_X * 2.0, 13, -1, text_col)

	# Foot row: type chip, value.
	var fy := ly + _label_size.y + ROW_GAP
	var type_w := _font.get_string_size(data.type, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	var chip := Rect2(PAD_X, fy, type_w + 12.0, 17.0)
	draw_rect(chip, theme_colors["panel"])
	draw_rect(chip, line, false, 1.0)
	draw_string(_font, Vector2(PAD_X + 6.0, fy + 12.5), data.type,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, dim_col)
	if value_text != "":
		var vcol := dim_col
		if eval_state is bool:
			vcol = theme_colors["true"] if eval_state else theme_colors["false"]
		var vw := _font.get_string_size(value_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(_font, Vector2(size.x - PAD_X - vw, fy + 12.5), value_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, vcol)

	# Caret for gates with children.
	if data.is_gate() and not data.children.is_empty():
		var caret: String
		if ConditionNodeData.ascii_mode:
			caret = "v" if expanded else ">"
		else:
			caret = "\u25be" if expanded else "\u25b8"
		var ccol := accent if expanded else faint_col
		draw_string(_font, Vector2(size.x - 15.0, size.y - 7.0), caret,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, ccol)

	# Package badge.
	if data.pkg_name != "":
		var mark := "#" if ConditionNodeData.ascii_mode else "\u25a3"
		var btxt := mark + " " + data.pkg_name.to_upper()
		var bw := _font.get_string_size(btxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
		var brect := Rect2(12, -9, bw + 12.0, 15.0)
		var bsb := StyleBoxFlat.new()
		bsb.bg_color = theme_colors["sel"]
		bsb.set_corner_radius_all(4)
		draw_style_box(bsb, brect)
		draw_string(_font, Vector2(18, 2.5), btxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
			Color("04121f"))

	if dimmed:
		modulate = Color(1, 1, 1, 0.34)
	else:
		modulate.a = 1.0
