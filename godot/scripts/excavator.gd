class_name Excavator
extends Vehicle
## DIG: drives to the nearest dirt if it's too far, swings, digs a bucketful.
## DUMP: swings to the nearest dump truck (or the crusher) and pours it in, else onto the ground.
## Joints (from the catalog): cab (swing, Y axis), boom, arm, bucket.

const DIG_POSE := {"boom": 0.55, "arm": -0.5, "bucket": -0.7}
const CURL_POSE := {"boom": 0.35, "arm": 0.35, "bucket": 0.9}
const UP_POSE := {"boom": -0.35, "arm": 0.2, "bucket": 0.9}
const POUR_POSE := {"boom": -0.25, "arm": -0.35, "bucket": -0.9}


func action_label() -> String:
	if busy:
		return "WAIT"
	return "DUMP" if load > 0.01 else "DIG"


func reach() -> float:
	return length * 0.95


func act() -> void:
	if busy:
		return
	if load > 0.01:
		_dump()
	else:
		_dig()


func _dig() -> void:
	var p: Pile = world.nearest_pile(global_position)
	if p == null:
		Sfx.say("No more dirt! Wait a little.")
		return
	var to := p.global_position - global_position
	to.y = 0
	var gap := to.length() - p.radius()
	if gap > reach():
		# Too far: drive up to the pile first, then dig.
		var stop := p.global_position - to.normalized() * (p.radius() + reach() * 0.7)
		drive_to(stop, _dig, 2.0)
		return
	busy = true
	await _swing_to(p.global_position)
	await pose(DIG_POSE, 0.9)
	await pose(CURL_POSE, 0.8)
	if p.take(1.0):
		load = 1.0
		Synth.play_scoop(self)
	_dirt_changed()
	await pose(UP_POSE, 0.7)
	busy = false


func _dump() -> void:
	var truck: Vehicle = world.nearest_vehicle(global_position, ["dump_truck"], length * 1.9, true)
	var at: Vector3
	if truck:
		at = truck.bed_point()
	elif world.near_dump(global_position + forward() * reach()) or Vector2(global_position.x - world.CRUSHER.x, global_position.z - world.CRUSHER.z).length() < 20:
		at = world.CRUSHER
	else:
		at = global_position + _arm_dir() * reach()
	busy = true
	await _swing_to(at)
	await pose(POUR_POSE, 0.8)
	var n := load
	load = 0.0
	_dirt_changed()
	if truck and is_instance_valid(truck) and truck.global_position.distance_to(global_position) < length * 1.8:
		truck.add_load(n)
		Synth.play_rumble(world)
	else:
		world.drop_dirt(at, n)
	await pose(UP_POSE, 0.6)
	await _swing_home()
	busy = false


func _arm_dir() -> Vector3:
	var a: float = angles.get("cab", 0.0) if parts.has("cab") else 0.0
	return forward().rotated(Vector3.UP, a)


func _swing_to(p: Vector3) -> void:
	if parts.has("cab"):
		var to := p - global_position
		var ty := atan2(-to.x, -to.z)
		var rel := angle_difference(yaw, ty)
		await pose({"cab": float(angles.get("cab", 0.0)) + angle_difference(float(angles.get("cab", 0.0)), rel)}, 0.9)
	else:
		await face(p)


func _swing_home() -> void:
	if parts.has("cab") and absf(angles.get("cab", 0.0)) > 0.01:
		await pose({"cab": 0.0}, 0.9)


func _dirt_changed() -> void:
	var b: Node3D = parts.get("bucket", body)
	if b == body:
		show_dirt(body, Vector3(0, length * 0.25, -length * 0.55), Vector3.ONE * length * 0.07)
	else:
		var s := 1.0 / maxf(b.global_transform.basis.get_scale().x, 0.0001)
		show_dirt(b, Vector3.ZERO, Vector3.ONE * length * 0.06 * s)
