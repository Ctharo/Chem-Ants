class_name GraphLayout
extends RefCounted
## Placement engine for one layer of the condition graph.
##
## Static functions over a per-call [GraphLayout.Ctx] snapshot, so this class
## holds no state of its own and can never go stale when the editor swaps its
## expansion set or moves to another layer. The Dictionaries and Arrays inside
## a Ctx are the editor's own (shared by reference), so every write here lands
## directly in the editor's state - exactly as the old member functions did.
##
## Extracted from ConditionGraphEditor; the editor keeps thin const aliases
## (RAIL_KEY, GUTTER, RAIL_W, RAIL_H) so OutputRailWidget and the viewport
## extents code did not have to change.

## Reserved key inside a layer's position map holding the output rail's spot.
const RAIL_KEY: String = "#rail"

const V_GAP: float = 24.0       # vertical gap between sibling subtrees
const GUTTER: float = 56.0      # left gutter for auto-layout
const COL_GAP: float = 70.0     # horizontal gap between a parent and its children
const RAIL_W: float = 130.0
const RAIL_H: float = 112.0

## Keep the layer this far off the canvas origin: nothing left of x = 0 or
## above y = 0 is reachable, because the editor's pan clamp never lets the
## world scroll positive.
const EDGE_PAD: float = 24.0


## Everything one layout pass reads and writes. Built fresh at each call site
## by ConditionGraphEditor._layout_ctx().
class Ctx:
	var widgets: Dictionary = {}            # id -> GraphNodeWidget
	var node_pos: Dictionary = {}           # id -> Vector2 (layout targets)
	var expanded: Dictionary = {}           # id -> true
	var layer_positions: Dictionary = {}    # id -> Vector2 (persistent store)
	var visible_nodes: Array[ConditionNodeData] = []
	var stage_size: Vector2 = Vector2.ZERO


# ============================================================================
# Measuring and placing one subtree
# ============================================================================
static func sub_height(ctx: Ctx, n: ConditionNodeData) -> float:
	var h: float = (ctx.widgets[n.id] as GraphNodeWidget).size.y
	if not ctx.expanded.has(n.id) or n.children.is_empty():
		return h
	var s: float = 0.0
	for i: int in n.children.size():
		s += sub_height(ctx, n.children[i]) + (V_GAP if i > 0 else 0.0)
	return maxf(h, s)


static func place_tree(ctx: Ctx, n: ConditionNodeData, right_edge: float,
		top: float) -> void:
	var w: GraphNodeWidget = ctx.widgets[n.id]
	var s: float = sub_height(ctx, n)
	var lp: Dictionary = ctx.layer_positions
	var pos: Vector2
	if lp.has(n.id):
		pos = lp[n.id]
	else:
		pos = Vector2(right_edge - w.size.x, top + s * 0.5 - w.size.y * 0.5)
	ctx.node_pos[n.id] = pos
	if ctx.expanded.has(n.id) and not n.children.is_empty():
		var kid_total: float = 0.0
		for i: int in n.children.size():
			kid_total += sub_height(ctx, n.children[i]) + (V_GAP if i > 0 else 0.0)
		var cy: float = pos.y + w.size.y * 0.5 - kid_total * 0.5
		for c: ConditionNodeData in n.children:
			place_tree(ctx, c, pos.x - COL_GAP, cy)
			cy += sub_height(ctx, c) + V_GAP


# ============================================================================
# Whole-layer passes
# ============================================================================
## Give every top-level card a stored position. An empty layer gets the full
## tidy tree layout; a layer that already has positions only places newcomers,
## which is what keeps existing cards still.
static func ensure_top_positions(ctx: Ctx, f: ConditionNodeData,
		loose_roots: Array[ConditionNodeData]) -> void:
	var tops: Array[ConditionNodeData] = []
	for c: ConditionNodeData in f.children:
		tops.append(c)
	for n: ConditionNodeData in loose_roots:
		tops.append(n)
	if tops.is_empty():
		return
	var lp: Dictionary = ctx.layer_positions
	var known: int = 0
	for t: ConditionNodeData in tops:
		if lp.has(t.id):
			known += 1
	if known == 0:
		auto_layout_layer(ctx, f, loose_roots)
		return
	if known == tops.size():
		return
	var bottom: float = 44.0
	for t: ConditionNodeData in tops:
		if lp.has(t.id):
			bottom = maxf(bottom,
				(lp[t.id] as Vector2).y + (ctx.widgets[t.id] as GraphNodeWidget).size.y)
	var y: float = bottom + V_GAP
	for t: ConditionNodeData in tops:
		if lp.has(t.id):
			continue
		lp[t.id] = Vector2(GUTTER, y)
		y += (ctx.widgets[t.id] as GraphNodeWidget).size.y + V_GAP


## Full tidy pass for one layer: the wired tree fans right-to-left and is
## centred, unwired roots stack underneath. Results are stored, so this is the
## only thing that ever moves an existing card.
static func auto_layout_layer(ctx: Ctx, f: ConditionNodeData,
		loose_roots: Array[ConditionNodeData]) -> void:
	var lp: Dictionary = ctx.layer_positions
	lp.clear()
	ctx.node_pos.clear()
	var total: float = 0.0
	for i: int in f.children.size():
		total += sub_height(ctx, f.children[i]) + (V_GAP if i > 0 else 0.0)
	var tree_h: float = maxf(ctx.stage_size.y, total + 130.0)
	var col0: float = ctx.stage_size.x - 250.0
	var y: float = maxf(44.0, tree_h * 0.5 - total * 0.5)
	for r: ConditionNodeData in f.children:
		place_tree(ctx, r, col0, y)
		y += sub_height(ctx, r) + V_GAP

	var min_l: float = INF
	for n: ConditionNodeData in ctx.visible_nodes:
		if ctx.node_pos.has(n.id):
			min_l = minf(min_l, (ctx.node_pos[n.id] as Vector2).x)
	if min_l != INF and absf(GUTTER - min_l) > 0.5:
		var shift: float = GUTTER - min_l
		for n: ConditionNodeData in ctx.visible_nodes:
			if ctx.node_pos.has(n.id):
				ctx.node_pos[n.id].x += shift

	var bottom: float = 44.0
	for n: ConditionNodeData in ctx.visible_nodes:
		if ctx.node_pos.has(n.id):
			bottom = maxf(bottom,
				(ctx.node_pos[n.id] as Vector2).y + (ctx.widgets[n.id] as GraphNodeWidget).size.y)
	var ly: float = bottom + 40.0
	for n: ConditionNodeData in loose_roots:
		place_tree(ctx, n, GUTTER + (ctx.widgets[n.id] as GraphNodeWidget).size.x, ly)
		nudge_subtree_into_view(ctx, n)
		ly += sub_height(ctx, n) + V_GAP

	for c: ConditionNodeData in f.children:
		lp[c.id] = ctx.node_pos[c.id]
	for n: ConditionNodeData in loose_roots:
		lp[n.id] = ctx.node_pos[n.id]
	var tree_r: float = GUTTER
	for c: ConditionNodeData in f.children:
		tree_r = maxf(tree_r,
			(ctx.node_pos[c.id] as Vector2).x + (ctx.widgets[c.id] as GraphNodeWidget).size.x)
	lp[RAIL_KEY] = Vector2(maxf(ctx.stage_size.x - 150.0, tree_r + 90.0),
		tree_h * 0.5 - RAIL_H * 0.5)


## Shove an auto-placed subtree right if its expanded children ran off the left.
static func nudge_subtree_into_view(ctx: Ctx, root_node: ConditionNodeData) -> void:
	var ids: Array[String] = visible_subtree_ids(ctx, root_node)
	var lmin: float = INF
	for sid: String in ids:
		if ctx.node_pos.has(sid):
			lmin = minf(lmin, (ctx.node_pos[sid] as Vector2).x)
	if lmin == INF or lmin >= 20.0:
		return
	var d: float = 20.0 - lmin
	for sid: String in ids:
		if ctx.node_pos.has(sid):
			ctx.node_pos[sid].x += d


# ============================================================================
# Keeping an expansion on screen
# ============================================================================
## Children fan out to the *left* of their parent, so expanding a deep gate can
## push cards past x = 0 (unreachable) and can grow a subtree straight through
## its siblings. This runs after placement and fixes both, writing results back
## to the layer store so the shuffle is permanent rather than cosmetic.
## `separate` is the editor's consumed _needs_room flag: plain rebuilds leave
## hand-placed cards exactly where they are.
static func make_room(ctx: Ctx, f: ConditionNodeData,
		loose_roots: Array[ConditionNodeData], separate: bool) -> void:
	var tops: Array[ConditionNodeData] = []
	for c: ConditionNodeData in f.children:
		tops.append(c)
	for n: ConditionNodeData in loose_roots:
		tops.append(n)
	if tops.is_empty():
		return
	if separate:
		separate_subtrees(ctx, tops)
	shift_into_canvas(ctx)


## Bounding box of everything currently drawn for this root.
static func subtree_rect(ctx: Ctx, n: ConditionNodeData) -> Rect2:
	var out: Rect2 = Rect2()
	var started: bool = false
	for sid: String in visible_subtree_ids(ctx, n):
		if not ctx.node_pos.has(sid) or not ctx.widgets.has(sid):
			continue
		var box: Rect2 = Rect2(ctx.node_pos[sid], (ctx.widgets[sid] as GraphNodeWidget).size)
		if started:
			out = out.merge(box)
		else:
			out = box
			started = true
	return out


static func shift_subtree(ctx: Ctx, n: ConditionNodeData, delta: Vector2) -> void:
	if delta.is_zero_approx():
		return
	var lp: Dictionary = ctx.layer_positions
	for sid: String in visible_subtree_ids(ctx, n):
		if ctx.node_pos.has(sid):
			ctx.node_pos[sid] = (ctx.node_pos[sid] as Vector2) + delta
		if lp.has(sid):
			lp[sid] = (lp[sid] as Vector2) + delta


## Top-down sweep: each subtree drops below anything it collides with.
static func separate_subtrees(ctx: Ctx, tops: Array[ConditionNodeData]) -> void:
	var order: Array[ConditionNodeData] = tops.duplicate()
	order.sort_custom(func(a: ConditionNodeData, b: ConditionNodeData) -> bool:
		return subtree_rect(ctx, a).position.y < subtree_rect(ctx, b).position.y)
	var taken: Array[Rect2] = []
	for n: ConditionNodeData in order:
		var box: Rect2 = subtree_rect(ctx, n)
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
		shift_subtree(ctx, n, Vector2(0.0, box.position.y - start_y))
		taken.append(box)


## The canvas grows right and down on its own, but the pan clamp never scrolls
## positive, so anything at negative coordinates is unreachable. Move the layer
## instead of the view.
static func shift_into_canvas(ctx: Ctx) -> void:
	var min_l: float = INF
	var min_t: float = INF
	for n: ConditionNodeData in ctx.visible_nodes:
		if not ctx.node_pos.has(n.id):
			continue
		var p: Vector2 = ctx.node_pos[n.id]
		min_l = minf(min_l, p.x)
		min_t = minf(min_t, p.y)
	if min_l == INF:
		return
	var delta: Vector2 = Vector2(maxf(0.0, EDGE_PAD - min_l), maxf(0.0, EDGE_PAD - min_t))
	if delta.is_zero_approx():
		return
	var lp: Dictionary = ctx.layer_positions
	for key: String in lp.keys():
		lp[key] = (lp[key] as Vector2) + delta
	for nid: String in ctx.node_pos.keys():
		ctx.node_pos[nid] = (ctx.node_pos[nid] as Vector2) + delta


# ============================================================================
# Visibility walks
# ============================================================================
## Pre-order ids of a subtree's drawn cards: the root plus every descendant
## reachable through expanded gates that currently owns a widget.
static func visible_subtree_ids(ctx: Ctx, root_node: ConditionNodeData) -> Array[String]:
	var out: Array[String] = []
	_collect_visible_ids(ctx, root_node, out)
	return out


static func _collect_visible_ids(ctx: Ctx, n: ConditionNodeData,
		out: Array[String]) -> void:
	out.append(n.id)
	if not ctx.expanded.has(n.id):
		return
	for c: ConditionNodeData in n.children:
		if ctx.widgets.has(c.id):
			_collect_visible_ids(ctx, c, out)
