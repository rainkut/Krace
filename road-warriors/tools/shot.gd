extends SceneTree
## godot -s tools/shot.gd -- <frame>:<out.png> | <frame>@<method> ... ; runs main scene
var frame := 0
var shots := {}
var calls := {}
var quit_at := 99999

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("quit="):
			quit_at = int(a.substr(5))
		elif "@" in a:
			var p := a.split("@", false, 1)
			calls[int(p[0])] = p[1]
		elif ":" in a:
			var q := a.split(":", false, 1)
			shots[int(q[0])] = q[1]
	change_scene_to_file("res://scenes/main.tscn")

func _process(_dt: float) -> bool:
	frame += 1
	if calls.has(frame) and current_scene != null:
		current_scene.call(calls[frame])
	if shots.has(frame):
		root.get_texture().get_image().save_png(shots[frame])
		print("shot ", frame, " -> ", shots[frame])
	if frame >= quit_at:
		quit()
	return false
