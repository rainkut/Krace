extends MeshInstance3D
## Keeps the cloud dome centred on the active camera.

func _process(_dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam:
		global_position = cam.global_position
		scale = Vector3.ONE * (cam.far * 0.8 / 700.0)
