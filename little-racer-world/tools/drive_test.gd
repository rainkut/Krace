extends SceneTree
## Scripted-input drive test in free roam: godot -s tools/drive_test.gd (needs a renderer, e.g. xvfb).
## Timed in physics ticks so it is independent of the render frame rate.
var game: Node
var fails := 0
var start := -1
var stage := 0
var mark := 0
var h0 := 0.0
var v_peak := 0.0

func check(ok: bool, msg: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + msg)
	if not ok:
		fails += 1

func _initialize() -> void:
	root.get_node("Save").wipe()
	root.get_node("Content").launch = {"mode": "roam"}
	change_scene_to_file("res://scenes/game.tscn")

func _physics_process(_dt: float) -> bool:
	if game == null:
		if current_scene != null and current_scene.get("player") != null:
			game = current_scene
			start = Engine.get_physics_frames()
			Input.action_press("accelerate")
		return false
	var t := Engine.get_physics_frames() - start
	var v: float = game.player.linear_velocity.length()
	if stage == 0 and t >= 90:
		v_peak = v
		check(v > 12.0, "accelerate: %.1f m/s after 1.5 s" % v)
		Input.action_release("accelerate")
		Input.action_press("brake")
		stage = 1
		mark = t
	elif stage == 1 and t - mark >= 30:
		check(v < v_peak * 0.7, "brake slows the car (%.1f -> %.1f m/s in 0.5 s)" % [v_peak, v])
		Input.action_release("brake")
		Input.action_press("accelerate")
		stage = 2
		mark = t
	elif stage == 2 and t - mark >= 30:
		h0 = game.player.heading()
		Input.action_press("steer_left")
		stage = 3
		mark = t
	elif stage == 3 and t - mark >= 45:
		var dh := absf(angle_difference(h0, game.player.heading()))
		check(dh > 0.2, "steer_left turns the car (%.0f deg in 0.75 s)" % rad_to_deg(dh))
		Input.action_release("steer_left")
		Input.action_release("accelerate")
		print("DRIVE %s" % ("PASS" if fails == 0 else "FAIL"))
		quit(0 if fails == 0 else 1)
	return false
