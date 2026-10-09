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
const MINI := 250.0
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
		position = Vector2(24, 150)
	queue_redraw()

func toggle() -> void:
	full = not full
	_layout()

func _gui_input(e: InputEvent) -> void:
	if (e is InputEventScreenTouch and e.pressed) or (e is InputEventMouseButton and e.pressed):
		toggle()
		accept_event()

func _process(dt: float) -> void:
	_acc += dt
	if _acc > (0.06 if not full else 0.15):
		_acc = 0.0
		queue_redraw()

func _draw() -> void:
	if world == null or player == null:
		return
	var ppos := Vector2(player.global_position.x, player.global_position.z)
	var heading := player.heading()
	var scale_px: float
	var center_world: Vector2
	var rot := 0.0
	if full:
		scale_px = size.x / (world.extent * 2.2)
		center_world = Vector2.ZERO
	else:
		scale_px = size.x * 0.5 / RANGE
		center_world = ppos
		rot = heading
	var c := size * 0.5
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.16, 0.2, 0.17, 0.82))
	var to_px := func(w: Vector2) -> Vector2:
		var d: Vector2 = (w - center_world) * scale_px
		return c + d.rotated(rot)
	var cull := RANGE * 1.5
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
		draw_polyline(out, ROAD_COL.get(rp["c"], Color.WHITE), wpx, true)
	if route.size() > 1:
		var rr := PackedVector2Array()
		for p in route:
			rr.append(to_px.call(Vector2(p.x, p.z)))
		rr.append(rr[0])
		draw_polyline(rr, Color(1.0, 0.45, 0.1, 0.9), 3.0 if not full else 4.0, true)
	if targets_fn.is_valid():
		var t = targets_fn.call()
		if t is Vector3:
			var tp: Vector2 = to_px.call(Vector2(t.x, t.z))
			tp = tp.clamp(Vector2(8, 8), size - Vector2(8, 8))
			draw_circle(tp, 7.0, Color("ffe14a"))
	for lm in world.landmark_nodes:
		var lp: Vector2 = to_px.call(lm["pos"])
		if Rect2(Vector2.ZERO, size).has_point(lp):
			draw_circle(lp, 5.0 if lm["kind"] != "hospital" else 6.0, Color("e84a4a") if lm["kind"] == "hospital" else Color("4aa0e8"))
	if world.has_park:
		var pk: Vector2 = to_px.call(Vector2(world.park_center.x, world.park_center.z))
		if Rect2(Vector2.ZERO, size).has_point(pk):
			draw_circle(pk, 56.0 * scale_px, Color(0.4, 0.8, 0.3, 0.55))
	var a := Vector2.ZERO
	var tip := Vector2(0, -12)
	var arrow := PackedVector2Array([tip, Vector2(8, 9), Vector2(0, 4), Vector2(-8, 9)])
	var ang := 0.0 if not full else -(heading) * -1.0
	var pc: Vector2 = to_px.call(ppos)
	var pts2 := PackedVector2Array()
	var ra := 0.0 if not full else -heading
	for p in arrow:
		pts2.append(pc + p.rotated(ra))
	draw_colored_polygon(pts2, Color("2aa8ff"))
	draw_polyline(pts2 + PackedVector2Array([pts2[0]]), Color.WHITE, 1.5)
	draw_rect(Rect2(Vector2.ZERO, size), Color.WHITE, false, 3.0)
	if not full:
		draw_string(ThemeDB.fallback_font, Vector2(8, 22), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 1, 1, 0.5))
