class_name TrafficManager
extends Node
## Ambient AI cars that wander along real OSM roads (driving on the LEFT, like India).
## Cars that fall far behind the player are re-spawned ahead of them, so the count stays constant.

const KEEP_RADIUS := 380.0
const SPAWN_MIN := 90.0
const SPAWN_MAX := 330.0
const POOL := ["sunny_hatch", "zippy_taxi", "bruno_suv", "sedan_sam", "van_vinnie", "delivery_dev", "truck_tom", "garbage_gus", "sedan_sam", "zippy_taxi"]

var world: OsmWorld
var player: Vehicle
var cars: Array = []
var _rng := RandomNumberGenerator.new()
var _check_t := 0.0

func setup(w: OsmWorld, p: Vehicle, count: int) -> void:
	world = w
	player = p
	_rng.seed = 777
	for i in count:
		_add_car(i)

func _add_car(i: int) -> void:
	var vid: String = POOL[i % POOL.size()]
	var def := Content.get_vehicle(vid)
	var v := Vehicle.create(def, _rng.randi() % maxi(1, Content.paints.size()))
	v.max_speed = float(def.get("max_speed", 28)) * 0.5
	add_child(v)
	v.road_query = Callable(world, "is_road_at")
	var d := AIDriver.new()
	var racer := {"count": 0}
	d.car = v
	d.racer = racer
	d.skill = _rng.randf_range(0.55, 0.8)
	d.lane = -1.7
	d.ambient = true
	add_child(d)
	var c := {"car": v, "ai": d, "racer": racer, "route_end": -1}
	cars.append(c)
	_respawn(c, true)

func _respawn(c: Dictionary, anywhere: bool) -> void:
	var pp := player.global_position
	var center := Vector2(pp.x, pp.z)
	var start := world.random_node_near(center, 20.0 if anywhere else SPAWN_MIN, SPAWN_MAX)
	var route := world.random_route(start, 900.0)
	if route.size() < 4:
		return
	var ai: AIDriver = c["ai"]
	ai.route = route
	c["racer"]["count"] = 1
	var a := route[0]
	var b := route[1]
	var dir := (b - a).normalized()
	var left := Vector3(dir.z, 0, -dir.x)
	var pos := a + left * 1.7
	pos.y = 0.7
	var car: Vehicle = c["car"]
	car.teleport_to(Transform3D(Basis(Vector3.UP, atan2(-dir.x, -dir.z)), pos))
	car.frozen_control = false

func _physics_process(dt: float) -> void:
	_check_t -= dt
	if _check_t > 0.0 or player == null:
		return
	_check_t = 1.0
	var pp := player.global_position
	for c in cars:
		var car: Vehicle = c["car"]
		var far := Vector2(car.global_position.x - pp.x, car.global_position.z - pp.z).length() > KEEP_RADIUS
		var route: PackedVector3Array = (c["ai"] as AIDriver).route
		var idx: int = int(c["racer"]["count"])
		var finished := idx >= route.size() - 2
		if far or finished or car.global_position.y < -5.0:
			_respawn(c, false)
