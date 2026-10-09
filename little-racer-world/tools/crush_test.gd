extends SceneTree
## godot --headless --path . -s tools/crush_test.gd -- <obstacles 0|1|2>  -> "CRUSHTEST PASS"
var frame := 0
var crush
var item: Dictionary
var car: RigidBody3D
var ok_phase := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	root.get_node("Settings").obstacles = int(args[0]) if args.size() > 0 else 1
	root.get_node("Content").launch = {"mode": "roam", "town": "sheoganj"}
	change_scene_to_file("res://scenes/game.tscn")

func _find(n: Node):
	var sc = n.get_script()
	if sc != null and sc.get_global_name() == &"ClutterCrush":
		return n
	for c in n.get_children():
		var r = _find(c)
		if r:
			return r
	return null

func _process(_dt: float) -> bool:
	frame += 1
	if frame == 30:
		crush = _find(current_scene)
		if crush == null:
			print("CRUSHTEST: no crushables (obstacles=%d)" % root.get_node("Settings").obstacles)
			quit(0 if root.get_node("Settings").obstacles == 0 else 1)
			return false
		print("CRUSHTEST: %d crushables" % crush._items.size())
		item = crush._items[0]
		car = get_nodes_in_group("crush_cars")[0]
		var o: Vector3 = item["xf"].origin
		car.global_position = o + Vector3(-6, 0.6, 0)
		car.linear_velocity = Vector3(12, 0, 0)
	if frame > 30 and frame < 90 and car:
		car.linear_velocity.x = maxf(car.linear_velocity.x, 8.0)
	if frame == 90:
		if item["alive"]:
			print("CRUSHTEST FAIL: item still alive")
			quit(1)
		else:
			print("CRUSHTEST PASS")
			quit(0)
	return false
