class_name MapView
extends Control
## Minimap (heading-up, 300 m radius) in the corner; tap it or press M for the full-town map.

const ROAD_COL := {"secondary": Color("f2d98a"), "tertiary": Color("ffffff"), "unclassified": Color("e6e6e6"), "residential": Color("d8d8d8"), "track": Color("b99c6a")}
var world: OsmWorld
var player: Vehicle
var route := PackedVector3Array()
var targets_fn := Callable()   # returns the next race target Vector3 or null
var full := false
var _acc := 0.0
const MINI := 280.0
const RANGE := 260.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	_layout()
	get_viewport().size_changed.connect(_layout)

func _layout() -> void:
	var vs := get_viewport_rect().size
	if full:
		var s := minf(vs.x, vs.y) - 60.0
		size = Vector2(s, s)
		position = (vs - size) * 0.5
	else:
		size = Vector2(MINI, MINI)
		position = Vector2(24, 196)
	queue_redraw()

func toggle() -> void:
	full = not full
	_layout()

func _gui_input(e: InputEvent) -> void:
	if (e is InputEventScreenTouch and e.pressed) or (e is InputEventMouseButton and e.pressed):
		if not full and e.position.x < 54.0 and e.position.y < 54.0:
			Settings.minimap_north = not Settings.minimap_north
			Settings.save_settings()
			queue_redraw()
		else:
			toggle()
		accept_event()

func _process(dt: float) -> void:
	_acc += dt
	if _acc > (0.06 if not full else 0.15):
		_acc = 0.0
		queue_redraw()

func _route_bounds() -> Rect2:
	var r := Rect2(route[0].x, route[0].z, 0, 0)
	for p in route:
		r = r.expand(Vector2(p.x, p.z))
	return r.grow(60.0)

func _draw() -> void:
	if world == null or player == null:
		return
	var racing := route.size() > 1
	var ppos := Vector2(player.global_position.x, player.global_position.z)
	var heading := player.heading()
	var scale_px: float
	var center_world: Vector2
	var rot := 0.0
	if full:
		var b := _route_bounds() if racing else world.bounds
		scale_px = minf(size.x, size.y) / (maxf(b.size.x, b.size.y) * (1.02 if racing else 1.05))
		center_world = b.get_center()
	else:
		var rng := RANGE if not racing else 190.0
		scale_px = size.x * 0.5 / rng
		center_world = ppos
		if not Settings.minimap_north:
			rot = heading
	var c := size * 0.5
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.13, 0.17, 0.14, 0.88))
	var to_px := func(w: Vector2) -> Vector2:
		var d: Vector2 = (w - center_world) * scale_px
		return c + d.rotated(rot)
	var cull := RANGE * 1.5
	var dim := 0.45 if racing else 1.0
	for rp in world.road_polylines:
		var pts: PackedVector2Array = rp["pts"]
		if not full:
			var m: Vector2 = pts[pts.size() / 2]
			if m.distance_to(ppos) > cull + pts.size() * 14.0:
				continue
		var out := PackedVector2Array()
		for p in pts:
			out.append(to_px.call(p))
		var wpx := clampf(float(rp["w"]) * scale_px, 1.2, 9.0)
		var col: Color = ROAD_COL.get(rp["c"], Color.WHITE)
		col.a = dim
		draw_polyline(out, col, wpx, true)
	if racing:
		var rr := PackedVector2Array()
		for p in route:
			rr.append(to_px.call(Vector2(p.x, p.z)))
		rr.append(rr[0])
		var lw := 8.0 if not full else 9.0
		draw_polyline(rr, Color(0.05, 0.05, 0.08, 0.95), lw + 4.0, true)
		draw_polyline(rr, Color("ff8a1f"), lw, true)
		var fp: Vector2 = rr[0]
		draw_line(fp, fp + Vector2(0, -26), Color.WHITE, 3.0)
		for k in 6:
			draw_rect(Rect2(fp.x + (k % 2) * 7.0, fp.y - 26.0 + (k / 2) * 7.0, 7, 7), Color.BLACK if (k + k / 2) % 2 == 0 else Color.WHITE)
	if targets_fn.is_valid():
		var t = targets_fn.call()
		if t is Vector3:
			var tp: Vector2 = to_px.call(Vector2(t.x, t.z))
			var inside := Rect2(Vector2(14, 14), size - Vector2(28, 28)).has_point(tp)
			tp = tp.clamp(Vector2(14, 14), size - Vector2(14, 14))
			var pulse := 1.0 + 0.25 * sin(Time.get_ticks_msec() * 0.008)
			draw_circle(tp, 15.0 * pulse, Color(0.2, 1.0, 0.4, 0.35))
			draw_circle(tp, 9.0, Color("1fe05a"))
			draw_arc(tp, 9.0, 0.0, TAU, 20, Color.WHITE, 2.0)
			if not inside:
				draw_string(ThemeDB.fallback_font, tp + Vector2(-4, 5), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.BLACK)
	if full or not racing:
		for lm in world.landmark_nodes:
			var lp: Vector2 = to_px.call(lm["pos"])
			if Rect2(Vector2.ZERO, size).has_point(lp):
				draw_circle(lp, 5.0 if lm["kind"] != "hospital" else 6.0, Color("e84a4a") if lm["kind"] == "hospital" else Color("4aa0e8"))
		if world.has_park and not racing:
			var pk: Vector2 = to_px.call(Vector2(world.park_center.x, world.park_center.z))
			if Rect2(Vector2.ZERO, size).has_point(pk):
				draw_circle(pk, 56.0 * scale_px, Color(0.4, 0.8, 0.3, 0.55))
	var arrow := PackedVector2Array([Vector2(0, -18), Vector2(11, 12), Vector2(0, 6), Vector2(-11, 12)])
	var pc: Vector2 = to_px.call(ppos)
	var ra := -heading + rot
	var pts2 := PackedVector2Array()
	for p in arrow:
		pts2.append(pc + p.rotated(ra))
	draw_colored_polygon(pts2, Color("2aa8ff"))
	draw_polyline(pts2 + PackedVector2Array([pts2[0]]), Color.WHITE, 2.5)
	draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE, false, 3.0)
	if not full:
		var north := Vector2(0, -1).rotated(rot)
		draw_circle(Vector2(26, 26), 20.0, Color(0, 0, 0, 0.55))
		draw_string(ThemeDB.fallback_font, Vector2(19, 33), "N" if not Settings.minimap_north else "^", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("ffe14a"))
		if not Settings.minimap_north:
			var np := Vector2(26, 26) + north * 24.0
			draw_circle(np.clamp(Vector2(6, 6), Vector2(size.x - 6, size.y - 6)), 3.0, Color("ffe14a"))
