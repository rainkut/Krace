extends SceneTree
func _init():
	var list = ["cars/sedan","cars/race","cars/taxi","cars/suv","cars/hatchback-sports","cars/police","cars/van","cars/truck","suburban/building-type-a","suburban/building-type-h","suburban/building-type-u","suburban/tree-large","suburban/tree-small","nature/tree_oak","nature/tree_pineTallA","nature/plant_bush","roads/light-square","roads/road-sign-stop"]
	for n in list:
		var p = load("res://assets/kenney/%s.glb" % n)
		var inst = p.instantiate()
		root.add_child(inst)
		var mn = Vector3(1e9,1e9,1e9); var mx = -mn
		for c in inst.find_children("*","MeshInstance3D",true,false):
			var a: AABB = c.global_transform * c.get_aabb()
			mn = mn.min(a.position); mx = mx.max(a.end)
		print(n, " min=", mn, " size=", mx-mn)
	quit()
