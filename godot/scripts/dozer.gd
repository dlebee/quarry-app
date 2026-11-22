class_name Dozer
extends Vehicle
## PUSH: rolls forward with the blade down and shoves any pile in front of it.
## Push a pile into the yellow ring and it goes into the crusher.


func action_label() -> String:
	return "WAIT" if goal != null else "PUSH"


func act() -> void:
	if goal != null:
		return
	pose({"blade": 0.25}, 0.4)
	var to := global_position + forward() * 16.0
	if not world.drivable(to.x, to.z):
		to = global_position + forward() * 6.0
	drive_to(to, func() -> void: pose({"blade": 0.0}, 0.5), 1.5)


func _physics_process(dt: float) -> void:
	super._physics_process(dt)
	if speed < 0.3:
		return
	var front := global_position + forward() * (length * 0.55)
	for p in world.piles:
		var d := Vector2(p.global_position.x - front.x, p.global_position.z - front.z)
		if d.length() < p.radius() + 0.5:
			var np: Vector3 = p.global_position + forward() * speed * dt
			np.y = world.ground_at(np.x, np.z) - 0.2
			p.global_position = np
			if world.near_dump(np) and p.amount > 0.5:
				var n: float = p.amount
				p.amount = 0.0
				p.add(0.0)
				world.drop_dirt(world.DUMP_SPOT, n)
