extends SceneTree
var game
var f := 0
func _initialize() -> void:
	root.get_node("Save").wipe()
	root.get_node("Content").launch = {"mode": "race", "race_id": "sunny_circuit", "autodrive": true}
	Engine.time_scale = 3.0
	change_scene_to_file("res://scenes/game.tscn")
func _physics_process(_d) -> bool:
	if game == null:
		if current_scene != null and current_scene.get("player") != null: game = current_scene
		return false
	f += 1
	if f % 60 == 0:
		for r in game.racers:
			var v = r["vehicle"]
			var d = r.get("driver")
			print(f, " ", r["name"], " cnt=", r["count"], " pos=", v.global_position.snapped(Vector3.ONE*0.1), " spd=", snappedf(v.speed,0.1), " th=", v.throttle, " br=", v.brake, " rev=", v.reverse_now, " rt=", d._reverse_t if d else -1)
	return f > 1500
