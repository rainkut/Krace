class_name HUD
extends Control
## In-race heads-up display, drawn in one pass.

var race: Race
var font: Font
var toasts: Array = []
var pts: PackedVector2Array = PackedVector2Array()
var sc_pts: PackedVector2Array = PackedVector2Array()
var mm_scale := 1.0
var mm_off := Vector2.ZERO
var show_debug := false
var hint_t := 14.0
var touch_mode := false
const MM_SIZE := Vector2(190, 130)

func bind(r: Race) -> void:
	race = r
	font = ThemeDB.fallback_font
	race.toast.connect(func(t: String, k: int) -> void:
		toasts.append({"t": t, "k": k, "age": 0.0})
		if toasts.size() > 4:
			toasts.pop_front())
	_build_minimap()
	touch_mode = DisplayServer.is_touchscreen_available()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)

func _build_minimap() -> void:
	var tr := race.track
	var raw: Array = []
	var mn := Vector2(1e9, 1e9)
	var mx := Vector2(-1e9, -1e9)
	var i := 0
	while i < tr.n - 1:
		var p := tr.pos[i]
		var q := Vector2(p.x, p.z)
		raw.append(q)
		mn = Vector2(minf(mn.x, q.x), minf(mn.y, q.y))
		mx = Vector2(maxf(mx.x, q.x), maxf(mx.y, q.y))
		i += 5
	var sz := mx - mn
	mm_scale = minf((MM_SIZE.x - 16.0) / maxf(sz.x, 1.0), (MM_SIZE.y - 16.0) / maxf(sz.y, 1.0))
	mm_off = Vector2(8, 8) + (MM_SIZE - Vector2(16, 16) - sz * mm_scale) * 0.5 - mn * mm_scale
	for q in raw:
		pts.append(q * mm_scale + mm_off)
	if tr.shortcut.y > 0.0:
		var a := int(tr.shortcut.x / (Track.STEP * 5.0))
		var b := int(tr.shortcut.y / (Track.STEP * 5.0))
		for k in range(a, mini(b, pts.size() - 1)):
			sc_pts.append(pts[k])

func _process(dt: float) -> void:
	size = get_viewport_rect().size
	if race == null:
		return
	for t in toasts:
		t["age"] += dt
	while not toasts.is_empty() and toasts[0]["age"] > 1.8:
		toasts.pop_front()
	if race.state == Race.RState.RACING:
		hint_t -= dt
	queue_redraw()

func _txt(s: String, p: Vector2, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
	draw_string_outline(font, p, s, align, w, size, maxi(2, size / 8), Color(0, 0, 0, 0.75))
	draw_string(font, p, s, align, w, size, col)

func _bar(r: Rect2, v: float, col: Color, label := "") -> void:
	draw_rect(r, Color(0, 0, 0, 0.55))
	draw_rect(Rect2(r.position + Vector2(2, 2), Vector2((r.size.x - 4) * clampf(v, 0, 1), r.size.y - 4)), col)
	if label != "":
		_txt(label, r.position + Vector2(6, r.size.y - 4), int(r.size.y) - 6, Color.WHITE)

func _ord(n: int) -> String:
	return ["", "1st", "2nd", "3rd", "4th", "5th", "6th", "7th", "8th"][clampi(n, 0, 8)]

func _draw() -> void:
	if race == null:
		return
	var W := size.x
	var H := size.y
	var p := race.player
	var white := Color(0.97, 0.97, 0.95)
	var accent := Color(1.0, 0.55, 0.12)
	# damage / nitro vignette
	if p.hit_flash > 0.0:
		draw_rect(Rect2(0, 0, W, H), Color(1, 0.1, 0.05, p.hit_flash * 0.8))
	if p.nitro_on:
		draw_rect(Rect2(0, 0, W, 40), Color(0.2, 0.8, 1.0, 0.18))
		draw_rect(Rect2(0, H - 40, W, 40), Color(0.2, 0.8, 1.0, 0.18))
	# position
	var multi := race.racers.size() > 1
	if multi:
		_txt("%d" % p.place, Vector2(24, 78), 72, accent)
		_txt("/ %d" % _alive_count(), Vector2(88 if p.place < 10 else 110, 78), 30, white)
	# progress
	var prog := race.progress()
	_bar(Rect2(24, 94, 220, 18), prog, accent)
	_txt("%.1f / %.1f km" % [p.s / 1000.0, race.track.finish_s / 1000.0], Vector2(24, 134), 20, white)
	# objective
	var obj := _objective()
	if obj != "":
		_txt(obj, Vector2(W * 0.42, 44), 30, white, HORIZONTAL_ALIGNMENT_CENTER, 600)
	var tt := _timer()
	if tt != "":
		_txt(tt, Vector2(W * 0.42, 82), 36, accent, HORIZONTAL_ALIGNMENT_CENTER, 400)
	# minimap
	var mp := Vector2(W - MM_SIZE.x - 20, 20)
	draw_rect(Rect2(mp, MM_SIZE), Color(0, 0, 0, 0.5))
	if pts.size() > 1:
		var tp := PackedVector2Array()
		for q in pts:
			tp.append(q + mp)
		draw_polyline(tp, Color(0.8, 0.8, 0.85, 0.85), 2.0)
		if sc_pts.size() > 1:
			var sp := PackedVector2Array()
			for q in sc_pts:
				sp.append(q + mp)
			draw_polyline(sp, Color(1.0, 0.8, 0.1), 3.0)
		var fi := mini(int(race.track.finish_s / (Track.STEP * 5.0)), pts.size() - 1)
		draw_circle(pts[fi] + mp, 4.0, Color.WHITE)
		for r in race.racers:
			if r.eliminated:
				continue
			var idx := clampi(int(r.s / (Track.STEP * 5.0)), 0, pts.size() - 1)
			draw_circle(pts[idx] + mp, 5.0 if r.is_player else 3.5, Color(1, 1, 1) if r.is_player else (r.color as Color))
		var pi := clampi(int(p.s / (Track.STEP * 5.0)), 0, pts.size() - 1)
		draw_arc(pts[pi] + mp, 7.0, 0, TAU, 14, accent, 2.0)
	# health + condition + weapon
	var bx := 24.0
	var by := H - 130.0
	if touch_mode:
		by = H - 250.0
	_bar(Rect2(bx, by, 260, 24), p.health / p.max_health, Color(0.9, 0.2, 0.2) if p.health / p.max_health < 0.3 else Color(0.35, 0.85, 0.4), "RIDER")
	_bar(Rect2(bx, by + 30, 260, 18), p.cond / 100.0, Color(0.95, 0.75, 0.2), "BIKE")
	var wname: String = Data.WEAPONS[p.weapon]["name"]
	var wtxt: String = wname if p.weapon == "punch" else "%s  x%d" % [wname, p.weapon_dur]
	_txt(wtxt, Vector2(bx, by + 76), 24, white)
	# speed + nitro
	var kmh := int(p.v * 3.6)
	var cx := W - 150.0
	var cy := H - 170.0
	if touch_mode:
		cy = H - 330.0
	var vm := float(p.stats["vmax"]) * 1.2
	draw_arc(Vector2(cx, cy), 82.0, deg_to_rad(150), deg_to_rad(390), 40, Color(0, 0, 0, 0.55), 12.0)
	var frac := clampf(p.v / vm, 0.0, 1.0)
	draw_arc(Vector2(cx, cy), 82.0, deg_to_rad(150), deg_to_rad(150 + 240 * frac), 40, accent if not p.nitro_on else Color(0.3, 0.85, 1.0), 12.0)
	_txt("%d" % kmh, Vector2(cx, cy + 14), 52, white, HORIZONTAL_ALIGNMENT_CENTER, 140)
	_txt("km/h", Vector2(cx, cy + 40), 20, Color(0.8, 0.8, 0.85), HORIZONTAL_ALIGNMENT_CENTER, 140)
	_bar(Rect2(cx - 100, cy + 70, 200, 20), p.nitro / float(p.stats["nitro_cap"]), Color(0.3, 0.8, 1.0), "NITRO")
	# combo / score
	if race.combo > 1:
		_txt("COMBO x%d" % race.combo, Vector2(W * 0.5, H * 0.72), 34, Color(1.0, 0.9, 0.3), HORIZONTAL_ALIGNMENT_CENTER, 500)
	# toasts
	var ty := H * 0.30
	for i in range(toasts.size() - 1, -1, -1):
		var t: Dictionary = toasts[i]
		var a := clampf(1.0 - (float(t["age"]) - 1.2) / 0.6, 0.0, 1.0)
		var col: Color = [white, Color(0.45, 1.0, 0.55), Color(1.0, 0.4, 0.35), Color(1.0, 0.85, 0.2)][int(t["k"])]
		col.a = a
		_txt(String(t["t"]), Vector2(W * 0.5, ty), 36 if int(t["k"]) >= 3 else 30, col, HORIZONTAL_ALIGNMENT_CENTER, 700)
		ty += 40.0
	# countdown
	if race.state == Race.RState.COUNTDOWN:
		var n := int(ceil(race.cd - 0.4))
		var s := "GO!" if n <= 0 else str(clampi(n, 1, 3))
		if race.cd > 3.4:
			s = ""
		_txt(s, Vector2(W * 0.5, H * 0.45), 150, accent, HORIZONTAL_ALIGNMENT_CENTER, 400)
	elif race.time < 1.2 and race.state == Race.RState.RACING:
		_txt("GO!", Vector2(W * 0.5, H * 0.45), 150, accent, HORIZONTAL_ALIGNMENT_CENTER, 400)
	# hints
	if Save.setting("tutorial") and hint_t > 0.0 and race.state != Race.RState.GAME_OVER:
		var hint := "Drag the pads to steer, punch with the side buttons, tap NITRO" if touch_mode else "W/S gas+brake   A/D steer   SPACE punch   Q/R left-right   E kick   SHIFT nitro   ESC pause"
		_txt(hint, Vector2(W * 0.5, H - 24), 22, Color(0.9, 0.9, 0.9, clampf(hint_t, 0, 1)), HORIZONTAL_ALIGNMENT_CENTER, W - 40)
	if show_debug:
		var y := 170.0
		for line in race.dbg_text().split("\n"):
			_txt(line, Vector2(24, y), 16, Color(0.6, 1, 0.6))
			y += 18.0

func _alive_count() -> int:
	var n := 0
	for r in race.racers:
		if not r.eliminated:
			n += 1
	return n

func _objective() -> String:
	match race.mode:
		"knockout":
			return "KNOCKOUT  next cut in %d s" % int(ceil(race.elim_t))
		"time":
			return "TIME TRIAL"
		"rival":
			return "RIVAL BATTLE  vs Mara Slate"
		"survival":
			return "SURVIVE"
		"highway":
			return "HIGHWAY RUN  score %d / %d" % [int(race.score), int(race.def["score_goal"])]
		"revenge":
			return "REVENGE  take down Tank Orlo"
	return ""

func _timer() -> String:
	if race.mode in ["time", "highway", "survival"]:
		var t := maxf(0.0, race.time_left)
		return "%d:%02d" % [int(t) / 60, int(t) % 60]
	return "%d:%02d" % [int(race.time) / 60, int(race.time) % 60]
