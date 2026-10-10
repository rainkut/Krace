extends SceneTree
## Scripted-driver lap test: godot --headless -s tools/lap_test.gd -- <race_id> <noise|throttle_only> [seconds]
## Presses the real input actions (so Game._drive_player, Easy assist and the stuck detector run).
var game: Node
var frame := 0
var kind := "noise"
var limit := 150.0
var t0 := -1.0
var laps := 0
var cps_seen := 0
var rng := RandomNumberGenerator.new()
var wob := 0.0

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var rid := str(a[0]) if a.size() > 0 else "ashapurna_gp"
	kind = str(a[1]) if a.size() > 1 else "noise"
	limit = float(a[2]) if a.size() > 2 else 150.0
	rng.seed = 7
	root.get_node("Save").wipe()
	root.get_node("Content").launch = {"mode": "race", "race_id": rid}
	Engine.time_scale = 4.0
	change_scene_to_file("res://scenes/game.tscn")

func _physics_process(dt: float) -> bool:
	frame += 1
	if frame == 30 and current_scene != null:
		game = current_scene
	if game == null or game.circuit == null:
		return false
	if game.state != "racing":
		return false
	if t0 < 0.0:
		t0 = game.race_time
		game.circuit.lap_done.connect(func(_r, lt, _b):
			laps += 1
			print("LAPTEST lap %d done in %.1fs (race_time %.1f)" % [laps, lt, game.race_time]))
	var el: float = game.race_time - t0
	Input.action_press("accelerate", 1.0)
	var v = game.player
	if kind == "noise":
		var ci: int = game._player_racer["ci"]
		var ahead := 3 + int(maxf(v.speed, 0.0) * 0.35 / 3.5)
		var tgt: Vector3 = game.circuit.aim(ci, ahead, 0.0, 0.0)
		var l: Vector3 = v.global_transform.affine_inverse() * tgt
		wob = lerpf(wob, rng.randf_range(-0.6, 0.6), 0.05)
		var s := clampf(atan2(l.x, -l.z) * 1.5 + wob, -1.0, 1.0)
		Input.action_release("steer_left")
		Input.action_release("steer_right")
		if s > 0.0:
			Input.action_press("steer_right", s)
		else:
			Input.action_press("steer_left", -s)
	if int(el) % 20 == 0 and frame % 60 == 0:
		print("LAPTEST t=%.0f ci=%d speed=%.1f resets_stuck=%d" % [el, game._player_racer["ci"], v.speed, game._stuck_count])
	if laps >= 1 or el > limit:
		print("LAPTEST RESULT kind=%s laps=%d elapsed=%.1f" % [kind, laps, el])
		quit(0 if laps >= 1 else 1)
	return false
