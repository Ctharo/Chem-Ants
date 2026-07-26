class_name OutputRailWidget 
## Output rail (custom-drawn, built in code)

extends Control
signal rail_clicked
signal rail_port_pressed(event: InputEventMouseButton)

var colors: Dictionary
var font: Font
var glyph_text: String = ""
var glyph_color: Color = Color.WHITE
var gate_name: String = ""
var out_state: Variant = null   # null / true / false
var selected: bool = false
var _port: GraphNodeWidget.Port

func _init(p_colors: Dictionary, p_font: Font) -> void:
	colors = p_colors
	font = p_font
	size = Vector2(ConditionGraphEditor.RAIL_W, ConditionGraphEditor.RAIL_H)
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
	var sb: StyleBoxFlat = StyleBoxFlat.new()
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
	var cx: float = size.x * 0.5
	var t: String = "OUTPUT"
	var w: float = font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
	draw_string(font, Vector2(cx - w * 0.5, 24), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
		colors["faint"])
	var gtxt: String = glyph_text + "  " + gate_name
	w = font.get_string_size(gtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	w = minf(w, size.x - 16)
	draw_string(font, Vector2(cx - w * 0.5, 52), gtxt, HORIZONTAL_ALIGNMENT_LEFT,
		int(size.x - 16), 13, glyph_color)
	var vtxt: String = "?"
	var vcol: Color = colors["dim"]
	if out_state is bool:
		vtxt = "TRUE" if out_state else "FALSE"
		vcol = colors["true"] if out_state else colors["false"]
	w = font.get_string_size(vtxt, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var chip: Rect2 = Rect2(cx - w * 0.5 - 10, 68, w + 20, 26)
	var csb: StyleBoxFlat = StyleBoxFlat.new()
	csb.bg_color = colors["panel"]
	csb.set_corner_radius_all(7)
	draw_style_box(csb, chip)
	draw_string(font, Vector2(cx - w * 0.5, 86), vtxt, HORIZONTAL_ALIGNMENT_LEFT, -1,
		13, vcol)
