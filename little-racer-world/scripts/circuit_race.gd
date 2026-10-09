class_name CircuitRace
extends Node
## Closed-circuit (F1-style) race logic: lap/sector/checkpoint tracking, timing, positions, and the
## precomputed racing line + speed profile the AI rivals follow. Works on any closed polyline.

signal lap_done(r: Dictionary, lap_time: float, is_best: bool)
signal racer_finished(r: Dictionary)

var game: Node
var pts := PackedVector3Array()
var n := 0
var cum := PackedFloat32Array()
var seg := PackedFloat32Array()      # length of segment i -> i+1
var length := 1.0
var dir := PackedVector3Array()
var right := PackedVector3Array()
var off := PackedFloat32Array()      # racing-line lateral offset (+ = right of travel)
var prof := PackedFloat32Array()     # corner-limited speed profile (m/s)
var laps := 3
var cp_idx: Array[int] = []
var sec_idx: Array[int] = []
var racers: Array = []
var race_time := 0.0
var best_lap := INF
var best_lap_name := ""
var best_sec := [INF, INF, INF]
var wrong_t := 0.0
var finish_count := 0

func setup(g: Node, world_pts: PackedVector3Array, lap_count: int, sectors: Array, corner_g: float) -> void:
	game = g
	pts = world_pts
	n = pts.size()
	laps = lap_count
	cum.resize(n)
	seg.resize(n)
	dir.resize(n)
	right.resize(n)
	var acc := 0.0
	for i in n:
		cum[i] = acc
		var d := pts[(i + 1) % n] - pts[i]
		d.y = 0.0
		seg[i] = d.length()
		acc += seg[i]
	length = acc
	for i in n:
		var d := pts[(i + 1) % n] - pts[(i - 1 + n) % n]
		d.y = 0.0
		dir[i] = d.normalized()
		right[i] = Vector3(-dir[i].z, 0.0, dir[i].x)
	for s in sectors:
		sec_idx.append(int(s))
	var step := 30
	var k := step
	while k < n - 10:
		cp_idx.append(k)
		k += step
	_racing_line(corner_g)

func _turn(i: int) -> float:
	var a := dir[(i - 1 + n) % n]
	var b := dir[(i + 1) % n]
	return asin(clampf(a.x * b.z - a.z * b.x, -1.0, 1.0))

func _racing_line(corner_g: float) -> void:
	var t := PackedFloat32Array()
	t.resize(n)
	for i in n:
		t[i] = _turn(i)
	var tsum := PackedFloat32Array()
	tsum.resize(n)
	for i in n:
		var s := 0.0
		for k in range(-5, 6):
			s += t[(i + k + n) % n]
		tsum[i] = s
	off.resize(n)
	for i in n:
		var inside := clampf(tsum[i] / 1.57 * 1.9, -1.9, 1.9)
		var entry := -clampf(tsum[(i + 8) % n] / 1.57 * 1.2, -1.2, 1.2) * (1.0 - clampf(absf(inside) / 1.9, 0.0, 1.0))
		off[i] = clampf(inside + entry, -2.4, 2.4)
	prof.resize(n)
	for i in n:
		var s := 0.0
		for k in range(-2, 3):
			s += t[(i + k + n) % n]
		var kappa := absf(s) / (5.0 * maxf(length / n, 0.5))
		prof[i] = 999.0 if kappa < 0.0005 else sqrt(corner_g / kappa)
	for _pass in 2:
		for j in range(n * 2 - 1, -1, -1):
			var i := j % n
			var nx := prof[(i + 1) % n]
			prof[i] = minf(prof[i], sqrt(nx * nx + 2.0 * 20.0 * seg[i]))

func widx(i: int) -> int:
	return ((i % n) + n) % n

## Lateral aim point on the racing line `ahead` points past the racer's index.
func aim(ci: int, ahead: int, lane: float, shift: float) -> Vector3:
	var j := widx(ci + ahead)
	return pts[j] + right[j] * clampf(off[j] + lane + shift, -2.8, 2.8)

func init_racer(r: Dictionary) -> void:
	var v: Vehicle = r["vehicle"]
	var best := 0
	var bd := 1e18
	for i in n:
		var d := pts[i] - v.global_position
		d.y = 0.0
		var l := d.length_squared()
		if l < bd:
			bd = l
			best = i
	r["cur"] = best
	r["cnt"] = best
	r["ci"] = best
	r["started"] = false
	r["laps_done"] = 0
	r["cp_next"] = 0
	r["lap_start"] = 0.0
	r["lap_times"] = []
	r["best_lap"] = INF
	r["sec"] = 0
	r["sec_start"] = 0.0
	r["sec_times"] = []
	r["off_t"] = 0.0
	racers.append(r)

func physics(dt: float) -> void:
	race_time = game.race_time
	for r in racers:
		_track(r)
		_progress(r)
	_wrong_way(dt)

func _track(r: Dictionary) -> void:
	var v: Vehicle = r["vehicle"]
	var p := v.global_position
	var cur: int = r["cur"]
	var best_k := 0
	var bd := 1e18
	for k in range(-2, 14):
		var q := pts[widx(cur + k)]
		var d := Vector2(q.x - p.x, q.z - p.z).length_squared()
		if d < bd:
			bd = d
			best_k = k
	if bd > 28.0 * 28.0:
		return
	cur += best_k
	r["cur"] = cur
	r["ci"] = widx(cur)
	var cnt: int = r["cnt"]
	while cnt < cur:
		cnt += 1
		r["cnt"] = cnt
		_event(r, widx(cnt))

func _event(r: Dictionary, idx: int) -> void:
	var is_player: bool = r["is_player"]
	if idx == 0:
		if not r["started"]:
			r["started"] = true
			r["lap_start"] = 0.0
			r["sec_start"] = 0.0
			r["sec"] = 0
			return
		if r["finished"]:
			return
		if int(r["cp_next"]) >= cp_idx.size():
			_complete_lap(r)
		elif is_player:
			game.hud.show_message("Missed a checkpoint!", 1.2, Color("ff8a8a"))
		return
	if not r["started"] or r["finished"]:
		return
	var cpn: int = r["cp_next"]
	if cpn < cp_idx.size() and idx == cp_idx[cpn]:
		r["cp_next"] = cpn + 1
	var sn: int = r["sec"]
	if sn < sec_idx.size() and idx == sec_idx[sn]:
		var t: float = race_time - float(r["sec_start"])
		r["sec_start"] = race_time
		r["sec"] = sn + 1
		r["sec_times"].append(t)
		if t < best_sec[sn]:
			best_sec[sn] = t
		if is_player:
			game.hud.set_sector("S%d  %.2f" % [sn + 1, t], t <= best_sec[sn] + 0.001)

func _complete_lap(r: Dictionary) -> void:
	var lt: float = race_time - float(r["lap_start"])
	var t: float = race_time - float(r["sec_start"])
	r["sec_times"].append(t)
	if t < best_sec[2]:
		best_sec[2] = t
	r["lap_times"].append(lt)
	var is_best: bool = lt < float(r["best_lap"])
	if is_best:
		r["best_lap"] = lt
	if lt < best_lap:
		best_lap = lt
		best_lap_name = str(r["name"])
	r["laps_done"] = int(r["laps_done"]) + 1
	r["lap_start"] = race_time
	r["sec_start"] = race_time
	r["sec"] = 0
	r["cp_next"] = 0
	lap_done.emit(r, lt, is_best)
	if int(r["laps_done"]) >= laps:
		r["finished"] = true
		r["finish_time"] = race_time
		r["finish_order"] = finish_count
		finish_count += 1
		racer_finished.emit(r)

func _progress(r: Dictionary) -> void:
	var ci: int = r["ci"]
	var v: Vehicle = r["vehicle"]
	var p := v.global_position - pts[ci]
	var proj := clampf(p.dot(dir[ci]), -3.5, seg[ci] + 3.5)
	var base := float(r["laps_done"]) * length + cum[ci] + proj
	if not r["started"]:
		base -= length
	r["progress"] = base

func _wrong_way(dt: float) -> void:
	var p: Dictionary = game._player_racer
	if game.state != "racing" or p["finished"]:
		game.hud.set_hint("")
		return
	var v: Vehicle = p["vehicle"]
	var fwd := -v.global_transform.basis.z
	fwd.y = 0.0
	var against := fwd.normalized().dot(dir[p["ci"]]) < -0.3 and absf(v.speed) > 3.0
	wrong_t = wrong_t + dt if against else maxf(0.0, wrong_t - dt * 2.0)
	game.hud.set_hint("Wrong way!  Turn around  (R = reset)" if wrong_t > 1.5 else "")

func next_checkpoint_pos(r: Dictionary) -> Vector3:
	var cpn: int = r["cp_next"]
	if cpn < cp_idx.size():
		return pts[cp_idx[cpn]]
	return pts[0]

func reset_pose(r: Dictionary) -> Transform3D:
	var i := widx(int(r["ci"]) - 1)
	var d := dir[i]
	return Transform3D(Basis(Vector3.UP, atan2(-d.x, -d.z)), Vector3(pts[i].x, 0.65, pts[i].z))
