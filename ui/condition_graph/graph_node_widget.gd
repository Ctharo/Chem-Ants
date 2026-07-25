class_name GraphNodeWidget
extends Control
## One card in the condition graph. Fully custom-drawn so it can be measured
## synchronously during layout. Emits raw pointer signals; the editor owns all
## interaction logic (click vs double-click vs drag, selection, wiring).

signal pointer_pressed(widget: GraphNodeWidget, event: InputEventMouseButton)
signal context_requested(widget: GraphNodeWidget, event: InputEventMouseButton)
signal port_pressed(widget: GraphNodeWidget, dir: String, event: InputEventMouseButton)

const MIN_W: float = 148.0
const MAX_W: float = 260.0
const PAD_X: float = 13.0
const PAD_TOP: float = 10.0
const PAD_BOT: float = 11.0
const ROW_GAP: float = 5.0
const GLYPH_BOX: float = 22.0
const LABEL_MAX_W: float = MAX_W - PAD_X * 2.0
const UNWIRED_TEXT: String = "unwired"
const TIMER_BAR_H: float = 6.0

var data: ConditionNodeData
var theme_colors: Dictionary = {} # supplied by the editor

var selected: bool = false
var dimmed: bool = false
var expanded: bool = false
var hovered: bool = false
## True when this card is a loose root: it lives on the canvas but nothing
## consumes its output yet.
var unconnected: bool = false
## null (no bool result), true, or false
var eval_state: Variant = null
var value_text: String = ""

var _font: Font
var _label_size: Vector2 = Vector2.ZERO
var _in_port: Control = null
var _out_port: Control = null


class Port extends Control:
	signal port_down(dir: String, event: InputEventMouseButton)
	var dir: String = "out"
	var color: Color = Color.WHITE
	var hovered: bool = false

	func _ready() -> void:
		custom_minimum_size = Vector2(16, 16)
		size = Vector2(16, 16)
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_CROSS
		mouse_entered.connect(func() -> void: hovered = true; queue_redraw())
		mouse_exited.connect(func() -> void: hovered = false; queue_redraw())

	func _draw() -> void:
		var c: Vector2 = size * 0.5
		var r: float = 7.0 if hovered else 6.0
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
	var p: Port = Port.new()
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
	var kind_w: float = _font.get_string_size(
		data.kind_title(), HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	var head_w: float = GLYPH_BOX + 8.0 + kind_w + 12.0 + 9.0
	if unconnected:
		head_w += _font.get_string_size(
			" " + UNWIRED_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	_label_size = _font.get_multiline_string_size(
		data.display_label(), HORIZONTAL_ALIGNMENT_LEFT, LABEL_MAX_W, 13)
	var type_w: float = _font.get_string_size(
		data.type, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x + 14.0
	var val_w: float = _font.get_string_size(
		value_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	var foot_w: float = type_w + 8.0 + val_w
	var inner: float = clampf(maxf(head_w, maxf(_label_size.x, foot_w)),
		MIN_W - PAD_X * 2.0, MAX_W - PAD_X * 2.0)
	var w: float = inner + PAD_X * 2.0
	var foot_h: float = 19.0
	var h: float = PAD_TOP + GLYPH_BOX + ROW_GAP + _label_size.y + ROW_GAP + foot_h + PAD_BOT
	if data.is_timing():
		h += TIMER_BAR_H + ROW_GAP
	size = Vector2(w, h)
	custom_minimum_size = size
	if _in_port:
		_in_port.position = Vector2(-8.0, h * 0.5 - 8.0)
	if _out_port:
		_out_port.position = Vector2(w - 8.0, h * 0.5 - 8.0)
		(_out_port as Port).color = accent_color()
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
	var accent: Color = accent_color()
	var line: Color = theme_colors["line"]
	var rect: Rect2 = Rect2(Vector2.ZERO, size)

	# Card background.
	var sb: StyleBoxFlat = StyleBoxFlat.new()
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

	# Accent bar. Broken into segments while the card feeds nothing.
	if unconnected:
		var seg: float = (size.y - 20.0) / 5.0
		draw_rect(Rect2(0, 10, 3, seg), Color(accent, 0.8))
		draw_rect(Rect2(0, 10 + seg * 2.0, 3, seg), Color(accent, 0.8))
		draw_rect(Rect2(0, 10 + seg * 4.0, 3, seg), Color(accent, 0.8))
	else:
		draw_rect(Rect2(0, 10, 3, size.y - 20), accent)

	var text_col: Color = theme_colors["text"]
	var dim_col: Color = theme_colors["dim"]
	var faint_col: Color = theme_colors["faint"]

	# Head row: glyph box, kind, status dot.
	var gy: float = PAD_TOP
	var gbox: Rect2 = Rect2(PAD_X, gy, GLYPH_BOX, GLYPH_BOX)
	draw_rect(gbox, Color(accent, 0.12))
	draw_rect(gbox, Color(accent, 0.4), false, 1.0)
	var gw: float = _font.get_string_size(data.glyph(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	draw_string(_font, Vector2(PAD_X + (GLYPH_BOX - gw) * 0.5, gy + 16.0),
		data.glyph(), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, accent)
	var kind_x: float = PAD_X + GLYPH_BOX + 8.0
	draw_string(_font, Vector2(kind_x, gy + 15.0),
		data.kind_title(), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, accent)
	if unconnected:
		var kw: float = _font.get_string_size(
			data.kind_title(), HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		draw_string(_font, Vector2(kind_x + kw + 6.0, gy + 15.0), UNWIRED_TEXT,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, faint_col)
	var dot_col: Color = faint_col
	if eval_state is bool:
		dot_col = theme_colors["true"] if eval_state else theme_colors["false"]
	draw_circle(Vector2(size.x - PAD_X - 4.5, gy + GLYPH_BOX * 0.5), 4.5, dot_col)

	# Label (wrapped).
	var ly: float = gy + GLYPH_BOX + ROW_GAP
	draw_multiline_string(_font, Vector2(PAD_X, ly + 12.0), data.display_label(),
		HORIZONTAL_ALIGNMENT_LEFT, size.x - PAD_X * 2.0, 13, -1, text_col)

	# Foot row: type chip, value.
	var fy: float = ly + _label_size.y + ROW_GAP
	var type_w: float = _font.get_string_size(data.type, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	var chip: Rect2 = Rect2(PAD_X, fy, type_w + 12.0, 17.0)
	draw_rect(chip, theme_colors["panel"])
	draw_rect(chip, line, false, 1.0)
	draw_string(_font, Vector2(PAD_X + 6.0, fy + 12.5), data.type,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, dim_col)
	if value_text != "":
		var vcol: Color = dim_col
		if eval_state is bool:
			vcol = theme_colors["true"] if eval_state else theme_colors["false"]
		var vw: float = _font.get_string_size(value_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		draw_string(_font, Vector2(size.x - PAD_X - vw, fy + 12.5), value_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, vcol)

	# Timer bar for timing nodes: how much of the interval is left.
	if data.is_timing():
		var by: float = fy + 19.0 + ROW_GAP
		var track: Rect2 = Rect2(PAD_X, by, size.x - PAD_X * 2.0, TIMER_BAR_H)
		draw_rect(track, theme_colors["panel"])
		draw_rect(track, line, false, 1.0)
		var fill: float = data.timer_progress()
		if fill > 0.0:
			var fill_col: Color = accent if eval_state != true else theme_colors["true"]
			draw_rect(Rect2(track.position, Vector2(track.size.x * fill, track.size.y)),
				fill_col)

	# Caret for gates with children.
	if data.is_gate() and not data.children.is_empty():
		var caret: String
		if ConditionNodeData.ascii_mode:
			caret = "v" if expanded else ">"
		else:
			caret = "\u25be" if expanded else "\u25b8"
		var ccol: Color = accent if expanded else faint_col
		draw_string(_font, Vector2(size.x - 15.0, size.y - 7.0), caret,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, ccol)

	# Package badge.
	if data.pkg_name != "":
		var mark: String = "#" if ConditionNodeData.ascii_mode else "\u25a3"
		var btxt: String = mark + " " + data.pkg_name.to_upper()
		var bw: float = _font.get_string_size(btxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
		var brect: Rect2 = Rect2(12, -9, bw + 12.0, 15.0)
		var bsb: StyleBoxFlat = StyleBoxFlat.new()
		bsb.bg_color = theme_colors["sel"]
		bsb.set_corner_radius_all(4)
		draw_style_box(bsb, brect)
		draw_string(_font, Vector2(18, 2.5), btxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
			Color("04121f"))

	if dimmed:
		modulate = Color(1, 1, 1, 0.34)
	else:
		modulate.a = 1.0
