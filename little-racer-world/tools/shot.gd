extends SceneTree
## Dev tool: godot -s tools/shot.gd -- <scene> '<launch json>' <frame>:<out.png> ... [scale=N] [quit=frame]
var frame := 0
var shots := {}
var quit_at := 99999
var page_calls := {}

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var scene: String = args[0]
	var launch = JSON.parse_string(args[1])
	root.get_node("Content").launch = launch if launch is Dictionary else {}
	for a in args.slice(2):
		if a.begins_with("scale="):
			Engine.time_scale = float(a.substr(6))
		elif a.begins_with("quit="):
			quit_at = int(a.substr(5))
		elif a == "touch":
			root.get_node("Settings").force_touch = true
		elif a.begins_with("page="):
			page_calls[int(a.get_slice("@", 1))] = a.get_slice("@", 0).substr(5)
		elif ":" in a:
			var p := a.split(":", false, 1)
			shots[int(p[0])] = p[1]
	change_scene_to_file(scene)

func _process(_dt: float) -> bool:
	frame += 1
	if page_calls.has(frame) and current_scene.has_method("show_page"):
		current_scene.call("show_page", page_calls[frame])
	if shots.has(frame):
		var img := root.get_texture().get_image()
		img.save_png(shots[frame])
		print("shot ", frame, " -> ", shots[frame])
	if frame >= quit_at:
		quit()
	return false
