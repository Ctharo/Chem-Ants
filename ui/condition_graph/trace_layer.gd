class_name TraceLayer
extends Control
## Draws the bezier "traces" between nodes plus the dashed preview wire while
## the user drags a connection. Purely visual; the editor pushes trace data in.

const SEGMENTS := 28

## Each entry: {"a": Vector2, "b": Vector2, "color": Color, "width": float}
var traces: Array[Dictionary] = []

var preview_active := false
var preview_from := Vector2.ZERO
var preview_to := Vector2.ZERO
var preview_sign := 1.0 # 1 = dragging from an OUT port, -1 = from an IN port
var preview_color := Color.WHITE


func set_traces(list: Array[Dictionary]) -> void:
	traces = list
	queue_redraw()


func set_preview(active: bool, from := Vector2.ZERO, to := Vector2.ZERO,
		sign_dir := 1.0) -> void:
	preview_active = active
	preview_from = from
	preview_to = to
	preview_sign = sign_dir
	queue_redraw()


static func bezier_points(a: Vector2, b: Vector2, sign_dir := 1.0) -> PackedVector2Array:
	var dx := maxf(60.0, absf(b.x - a.x) * 0.42) * sign_dir
	var c1 := a + Vector2(dx, 0)
	var c2 := b - Vector2(dx, 0)
	var pts := PackedVector2Array()
	pts.resize(SEGMENTS + 1)
	for i in SEGMENTS + 1:
		var t := float(i) / float(SEGMENTS)
		pts[i] = a.bezier_interpolate(c1, c2, b, t)
	return pts


func _draw() -> void:
	for tr in traces:
		draw_polyline(bezier_points(tr["a"], tr["b"]), tr["color"], tr["width"], true)
	if preview_active:
		_draw_dashed_bezier(
			bezier_points(preview_from, preview_to, preview_sign), preview_color)


func _draw_dashed_bezier(pts: PackedVector2Array, color: Color) -> void:
	# Walk the polyline emitting 5-on / 4-off dashes.
	var on := true
	var budget := 5.0
	var prev := pts[0]
	for i in range(1, pts.size()):
		var seg_from := prev
		var seg_to := pts[i]
		var seg_len := seg_from.distance_to(seg_to)
		while seg_len > 0.0:
			var step := minf(budget, seg_len)
			var next := seg_from + (seg_to - seg_from).normalized() * step
			if on:
				draw_line(seg_from, next, color, 2.5, true)
			seg_from = next
			seg_len -= step
			budget -= step
			if budget <= 0.0:
				on = not on
				budget = 5.0 if on else 4.0
		prev = pts[i]
