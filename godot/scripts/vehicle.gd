class_name Vehicle
extends Node3D
## A machine on the quarry ground. Drives on the height grid, tilts with the slope, never flips.
## Kinds: excavator, dump_truck, loader, bulldozer, plain (tractor, crane, roller, mixer...).
## Moving parts are looked up by node name from the model (see `parts` in main.gd's catalog);
## anything missing is simply not animated.

signal said(text: String)

var kind := "plain"
var title := "Truck"
var world: Node
var model: Node3D
var body: Node3D           # tilts with the ground
var length := 8.0
var max_speed := 7.0
var turn_rate := 0.9
var speed := 0.0
var yaw := 0.0
var throttle := 0.0        # -1..1 (player) — negative only brakes
var steer := 0.0
var goal = null            # Vector3 to auto-drive to, or null
var goal_cb: Callable      # called once on arrival
var goal_dist := 2.5
var load := 0.0            # scoops carried (truck bed or bucket)
var capacity := 3.0
var busy := false          # running a dig/dump sequence
var color := Color.WHITE
var wheels: Array[Node3D] = []
var parts := {}            # role -> Node3D
var rest := {}             # role -> Transform3D at rest
var axes := {}             # role -> rotation axis (sign folded in)
var angles := {}           # role -> current angle (radians)
var dirt_mesh: MeshInstance3D
var exhaust: CPUParticles3D


func setup(scene: PackedScene, cfg: Dictionary, w: Node) -> void:
	world = w
	kind = cfg.get("kind", "plain")
	title = cfg.get("title", "Truck")
	length = cfg.get("length", 8.0)
	max_speed = cfg.get("speed", 7.0)
	capacity = cfg.get("capacity", 3.0)
	body = Node3D.new()
	add_child(body)
	var pivot := Node3D.new()
	body.add_child(pivot)
	model = scene.instantiate()
	pivot.add_child(model)
	var box := _aabb(model, model)
	var ext := maxf(box.size.x, box.size.z)
	var s := length / maxf(ext, 0.001)
	model.scale = Vector3.ONE * s
	model.position = Vector3(-box.get_center().x * s, -box.position.y * s, -box.get_center().z * s)
	pivot.rotation.y = deg_to_rad(cfg.get("yaw", 0.0))
	# Each joint gets a clean pivot at the part's origin, aligned with the model's own axes, so
	# parts that live in oddly scaled frames still rotate cleanly. Order matters: parents first.
	var joints: Array = cfg.get("joints", [])
	for j in joints:
		var role: String = j["role"]
		var n := _find(model, j.get("node", ""))
		if n == null:
			continue
		var host: Node = parts[j["parent"]] if j.has("parent") and parts.has(j["parent"]) else n.get_parent()
		var pv := Node3D.new()
		pv.name = role + "_pivot"
		host.add_child(pv)
		pv.global_transform = Transform3D(model.global_basis.orthonormalized(), n.global_position)
		n.reparent(pv)
		parts[role] = pv
		rest[role] = pv.transform
		var ax: Array = j.get("axis", [1, 0, 0])
		axes[role] = Vector3(ax[0], ax[1], ax[2]).normalized() * float(j.get("sign", 1.0))
		angles[role] = 0.0
		if j.has("hide"):
			for h in j["hide"]:
				var hn := _find(model, h)
				if hn:
					hn.visible = false
	for wn in cfg.get("wheels", []):
		for n in model.find_children(wn, "Node3D", true, false):
			wheels.append(n)
	_make_dirt()
	exhaust = _smoke()
	body.add_child(exhaust)
	exhaust.position = Vector3(0, box.size.y * s * 0.95, 0)


func _find(root: Node, nm: String) -> Node3D:
	if nm == "":
		return null
	var list := root.find_children(nm, "Node3D", true, false)
	return list[0] if list.size() > 0 else null


func _aabb(n: Node, root: Node) -> AABB:
	var out := AABB()
	var first := true
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var t := Transform3D.IDENTITY
		var cur: Node = mi
		while cur and cur != root:
			if cur is Node3D:
				t = (cur as Node3D).transform * t
			cur = cur.get_parent()
		var b := t * mi.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out


## A heap of dirt shown in the truck bed / bucket; scaled by `load`.
func _make_dirt() -> void:
	dirt_mesh = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 1.0
	sm.is_hemisphere = true
	sm.radial_segments = 12
	sm.rings = 4
	dirt_mesh.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.38, 0.22)
	m.roughness = 1.0
	dirt_mesh.material_override = m
	dirt_mesh.visible = false


func _smoke() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.8, 0.8)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1, 0.5)
	m.albedo_texture = gt
	q.material = m
	p.mesh = q
	p.amount = 12
	p.lifetime = 1.6
	p.direction = Vector3(0, 1, 0)
	p.spread = 15
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 2.5
	p.gravity = Vector3(0, 0.4, 0)
	p.local_coords = false
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.3, 0.3, 0.3, 0.45))
	ramp.set_color(1, Color(0.5, 0.5, 0.5, 0.0))
	p.color_ramp = ramp
	p.emitting = false
	return p


func forward() -> Vector3:
	return Vector3(-sin(yaw), 0, -cos(yaw))


func drive_to(p: Vector3, cb := Callable(), dist := 2.5) -> void:
	path.clear()
	goal = p
	goal_cb = cb
	goal_dist = dist
	_stuck = 0.0


## Like drive_to, but follows the haul road when going between the pit and the yard.
func drive_route(p: Vector3, cb := Callable(), dist := 2.5) -> void:
	var pts: Array = world.route(global_position, p)
	drive_to(pts[0], cb, dist if pts.size() == 1 else 5.0)
	for i in range(1, pts.size()):
		path.append(pts[i])
	_final_dist = dist


var path: Array[Vector3] = []
var _final_dist := 2.5
var _stuck := 0.0


func _physics_process(dt: float) -> void:
	var want := 0.0
	var st := steer
	if goal != null:
		var to: Vector3 = goal - global_position
		to.y = 0
		var d := to.length()
		if d < goal_dist and not path.is_empty():
			goal = path.pop_front()
			goal_dist = 5.0 if not path.is_empty() else _final_dist
		elif d < goal_dist:
			goal = null
			speed = 0.0
			if goal_cb.is_valid():
				var cb := goal_cb
				goal_cb = Callable()
				cb.call()
		else:
			var ty := atan2(-to.x, -to.z)
			var diff := angle_difference(yaw, ty)
			st = clampf(diff * 1.8, -1, 1)
			var slow := 1.0 if not path.is_empty() else clampf(d / 10.0, 0.35, 1.0)
			want = max_speed * slow * (1.0 if absf(diff) < 0.9 else 0.35)
	elif not busy:
		want = max_speed * maxf(throttle, 0.0)
	speed = move_toward(speed, want, dt * max_speed * (0.8 if want > speed else 1.6))
	if absf(speed) > 0.2 or goal != null:
		yaw += st * turn_rate * dt * clampf(0.4 + speed / max_speed, 0.4, 1.2)
	var np := global_position + forward() * speed * dt
	if world.drivable(np.x, np.z):
		global_position = np
		_stuck = 0.0
	else:
		speed = 0.0
		if goal != null:
			# Blocked by a wall: skip ahead on the route, or give up after a while.
			_stuck += dt
			if _stuck > 1.2:
				_stuck = 0.0
				if not path.is_empty():
					goal = path.pop_front()
				else:
					goal = null
					goal_cb = Callable()
	var h: float = world.ground_at(global_position.x, global_position.z)
	global_position.y = h
	rotation.y = yaw
	# Tilt the body to the slope under the machine.
	var f := forward() * length * 0.4
	var r := Vector3(-f.z, 0, f.x).normalized() * 1.5
	var hf: float = world.ground_at(global_position.x + f.x, global_position.z + f.z)
	var hb: float = world.ground_at(global_position.x - f.x, global_position.z - f.z)
	var hr: float = world.ground_at(global_position.x + r.x, global_position.z + r.z)
	var hl: float = world.ground_at(global_position.x - r.x, global_position.z - r.z)
	var pitch := atan2(hf - hb, length * 0.8)
	var roll := atan2(hl - hr, 3.0)
	body.rotation.x = lerpf(body.rotation.x, pitch, dt * 6)
	body.rotation.z = lerpf(body.rotation.z, roll, dt * 6)
	for w in wheels:
		w.rotate_object_local(Vector3.RIGHT, -speed * dt / 0.6)
	exhaust.emitting = absf(speed) > 0.5 or busy


func set_joint(role: String, a: float) -> void:
	angles[role] = a
	if parts.has(role):
		var n: Node3D = parts[role]
		var r: Transform3D = rest[role]
		n.transform = Transform3D(r.basis * Basis(axes[role], a), r.origin)


## Move several joints together over `t` seconds: await pose({"boom": 0.5}, 0.8)
func pose(targets: Dictionary, t: float) -> void:
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	for role in targets:
		var from: float = angles.get(role, 0.0)
		tw.tween_method(func(v: float) -> void: set_joint(role, v), from, float(targets[role]), t)
	await tw.finished


## Turn the whole machine on the spot to face a point (tracked machines can pivot).
func face(p: Vector3, t := 0.8) -> void:
	var to := p - global_position
	var ty := atan2(-to.x, -to.z)
	var tw := create_tween().set_trans(Tween.TRANS_SINE)
	tw.tween_method(func(v: float) -> void: yaw = v, yaw, yaw + angle_difference(yaw, ty), t)
	await tw.finished


## Show `load` as a heap of dirt on `holder` at local `at`, sized `s`.
func show_dirt(holder: Node3D, at: Vector3, s: Vector3) -> void:
	if dirt_mesh.get_parent() != holder:
		if dirt_mesh.get_parent():
			dirt_mesh.get_parent().remove_child(dirt_mesh)
		holder.add_child(dirt_mesh)
	dirt_mesh.position = at
	dirt_mesh.scale = s
	dirt_mesh.visible = load > 0.01


func add_load(n: float) -> void:
	load = minf(load + n, capacity)
	_dirt_changed()


func _dirt_changed() -> void:
	pass


func action_label() -> String:
	return "HONK"
