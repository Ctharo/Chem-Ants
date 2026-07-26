class_name GraphTheme
extends RefCounted
## Palette, font and control styling for the condition-graph editor.
##
## Owns [member ui_scale]. Every font size and pixel margin the editor draws is
## authored at 1.0 and routed through [method fs] / [method px], so text is
## re-rasterised at the target size rather than magnified. The canvas folds the
## same scale into its transform; see ConditionGraphEditor._view_scale().
##
## Held under a name other than `theme` at every call site, because [Control]
## already owns that identifier. This is a plain [RefCounted] that builds
## StyleBoxes on demand, not a [Theme] resource.

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

const MIN_UI_SCALE: float = 0.75
const MAX_UI_SCALE: float = 2.5
const UI_SCALE_STEP: float = 0.05
## Height the layout was authored against; used to derive an automatic scale.
const DESIGN_HEIGHT: float = 900.0

## Every glyph the graph cards and chrome draw. A fallback font missing any one
## of them drops the whole editor into ConditionNodeData.ascii_mode rather than
## rendering tofu boxes; see [method has_all_glyphs].
const REQUIRED_GLYPHS: String = "\u2227\u2228\u00ac\u2295\u2264\u2265\u2260\u25c6\u25b8\u25be\u25a3\u25ce\u00d7\u2220\u2212\u21bb\u00fb\u03b8\u00b7"

var ui_scale: float = 1.0
var font: Font = null


func _init(p_font: Font, p_ui_scale: float = 1.0) -> void:
	font = p_font
	ui_scale = clamp_scale(p_ui_scale)


# ============================================================================
# Interface size
# ============================================================================
## Starting point on a fresh launch: match the height the layout was authored at.
static func auto_scale(window_height: float) -> float:
	return clampf(window_height / DESIGN_HEIGHT, MIN_UI_SCALE, MAX_UI_SCALE)


func clamp_scale(value: float) -> float:
	return clampf(snappedf(value, UI_SCALE_STEP), MIN_UI_SCALE, MAX_UI_SCALE)


## Font size authored at 1.0, scaled for the current interface size.
func fs(base: int) -> int:
	return maxi(1, roundi(float(base) * ui_scale))


## Pixel distance authored at 1.0, scaled for the current interface size.
func px(base: float) -> float:
	return base * ui_scale


## Label for the interface-size readout, e.g. "125%".
func percent_text() -> String:
	return "%d%%" % roundi(ui_scale * 100.0)


# ============================================================================
# Font coverage
# ============================================================================
func has_all_glyphs() -> bool:
	if font == null:
		return false
	for i: int in REQUIRED_GLYPHS.length():
		if not font.has_char(REQUIRED_GLYPHS.unicode_at(i)):
			return false
	return true


# ============================================================================
# Styling
# ============================================================================
func panel_style(bg: Color, border: Color, radius: int = 13,
		margin: int = 13) -> StyleBoxFlat:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(roundi(px(float(radius))))
	sb.set_content_margin_all(px(float(margin)))
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 14
	sb.shadow_offset = Vector2(0, 8)
	return sb


## kind: "normal" | "primary" | "danger" | "flat".
func style_button(btn: Button, kind: String = "normal") -> void:
	var normal: StyleBoxFlat = StyleBoxFlat.new()
	normal.set_corner_radius_all(roundi(px(8.0)))
	normal.set_border_width_all(1)
	normal.content_margin_left = px(11.0)
	normal.content_margin_right = px(11.0)
	normal.content_margin_top = px(7.0)
	normal.content_margin_bottom = px(7.0)
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
	btn.add_theme_font_size_override("font_size", fs(12))
	btn.focus_mode = Control.FOCUS_NONE


func style_line_edit(le: LineEdit) -> void:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = COLORS["panel"]
	sb.border_color = COLORS["line"]
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(roundi(px(8.0)))
	sb.set_content_margin_all(px(9.0))
	var focus: StyleBoxFlat = sb.duplicate()
	focus.border_color = COLORS["sel"]
	le.add_theme_stylebox_override("normal", sb)
	le.add_theme_stylebox_override("focus", focus)
	le.add_theme_color_override("font_color", COLORS["text"])
	le.add_theme_font_size_override("font_size", fs(13))


func style_spin(spin: SpinBox) -> void:
	style_line_edit(spin.get_line_edit())
	spin.add_theme_font_size_override("font_size", fs(13))


func style_option(ob: OptionButton) -> void:
	style_button(ob)
	ob.add_theme_font_size_override("font_size", fs(13))


func tiny_label(p_text: String, p_color: Color, font_size: int = 9) -> Label:
	var l: Label = Label.new()
	l.text = p_text
	l.add_theme_font_size_override("font_size", fs(font_size))
	l.add_theme_color_override("font_color", p_color)
	return l
