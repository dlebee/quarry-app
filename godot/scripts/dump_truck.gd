class_name DumpTruck
extends Vehicle
## Gets filled by an excavator or loader. DUMP: drives itself to the crusher if needed, tips the bed.
## GO (when empty): drives back next to the nearest excavator.

var home_exc: Vehicle


func action_label() -> String:
	if busy or goal != null:
		return "WAIT"
	if load > 0.01:
		return "DUMP"
	return "GO"


func bed_point() -> Vector3:
	return global_position + forward() * (-length * 0.2) + Vector3(0, length * 0.3, 0)


func act() -> void:
	if busy:
		return
	if load > 0.01:
		go_dump()
	else:
		go_load()


func go_dump() -> void:
	if world.near_dump(global_position):
		_tip()
	else:
		drive_route(world.DUMP_SPOT, _tip, 3.0)


func go_load() -> void:
	var e: Vehicle = world.nearest_vehicle(global_position, ["excavator", "loader"])
	if e == null:
		return
	home_exc = e
	var side := e.forward().rotated(Vector3.UP, PI / 2) * e.length * 0.9
	drive_route(e.global_position + side, func() -> void:
		await face(e.global_position + e.forward() * e.length)
		Sfx.say("Ready! Fill me up!") if world.cur == self else null, 2.5)


func _tip() -> void:
	busy = true
	speed = 0.0
	# Back toward the crusher: turn so the bed faces the dump spot.
	await face(global_position + (global_position - world.CRUSHER), 1.0)
	await pose({"bed": 0.9}, 1.3)
	var n := load
	load = 0.0
	_dirt_changed()
	world.drop_dirt(world.DUMP_SPOT, n)
	await get_tree().create_timer(0.6).timeout
	await pose({"bed": 0.0}, 1.2)
	busy = false
	if world.cur != self:
		go_load()


func _dirt_changed() -> void:
	var b: Node3D = parts.get("bed", body)
	var k := load / maxf(capacity, 1.0)
	if b == body:
		show_dirt(body, Vector3(0, length * 0.28, length * 0.18), Vector3(length * 0.13, length * 0.1 * k + 0.01, length * 0.22))
	else:
		var s := 1.0 / maxf(b.global_transform.basis.get_scale().x, 0.0001)
		show_dirt(b, Vector3(0, length * 0.05 * s, 0), Vector3(length * 0.13, length * 0.1 * k + 0.01, length * 0.2) * s)
