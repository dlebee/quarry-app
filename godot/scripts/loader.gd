class_name Loader
extends Vehicle
## SCOOP: drives into the nearest pile with the bucket down and lifts a big scoop.
## DUMP: drives to the nearest truck that has room (or the crusher) and pours it in.
## Joints: arms (lift), bucket (tilt).


func action_label() -> String:
	if busy or goal != null:
		return "WAIT"
	return "DUMP" if load > 0.01 else "SCOOP"


func act() -> void:
	if busy:
		return
	if load > 0.01:
		_go_dump()
	else:
		_go_scoop()


func _go_scoop() -> void:
	var p: Pile = world.nearest_pile(global_position)
	if p == null:
		Sfx.say("No more dirt! Wait a little.")
		return
	var to := p.global_position - global_position
	to.y = 0
	var stop := p.global_position - to.normalized() * (p.radius() + length * 0.55)
	if to.length() - p.radius() > length * 0.9:
		drive_to(stop, _go_scoop, 2.0)
		return
	busy = true
	await face(p.global_position, 0.6)
	await pose({"arms": 0.25, "bucket": -0.3}, 0.6)
	# Push in.
	var tw := create_tween()
	var start := global_position
	tw.tween_method(func(v: float) -> void:
		var q := start + forward() * v
		global_position = Vector3(q.x, world.ground_at(q.x, q.z), q.z), 0.0, 2.0, 0.7)
	await tw.finished
	if p.take(2.0):
		load = 2.0
		Synth.play_scoop(self)
	_dirt_changed()
	await pose({"arms": -0.5, "bucket": 0.6}, 0.8)
	busy = false


func _go_dump() -> void:
	var truck: Vehicle = world.nearest_vehicle(global_position, ["dump_truck"], 90.0, true)
	var at: Vector3 = truck.bed_point() if truck else world.DUMP_SPOT
	var to := at - global_position
	to.y = 0
	if to.length() > length * 1.1:
		drive_route(at - to.normalized() * length * 0.9, _go_dump, 2.0)
		return
	busy = true
	await face(at, 0.6)
	await pose({"arms": -1.0, "bucket": 0.6}, 0.8)
	await pose({"bucket": -0.9}, 0.6)
	var n := load
	load = 0.0
	_dirt_changed()
	if truck and truck.global_position.distance_to(global_position) < length * 2.0:
		truck.add_load(n)
		Synth.play_rumble(world)
	else:
		world.drop_dirt(at, n)
	await pose({"arms": 0.0, "bucket": 0.0}, 0.8)
	busy = false


func _dirt_changed() -> void:
	var b: Node3D = parts.get("bucket", body)
	if b == body:
		show_dirt(body, Vector3(0, length * 0.25, -length * 0.55), Vector3.ONE * length * 0.09)
	else:
		var s := 1.0 / maxf(b.global_transform.basis.get_scale().x, 0.0001)
		show_dirt(b, Vector3.ZERO, Vector3.ONE * length * 0.08 * s)
