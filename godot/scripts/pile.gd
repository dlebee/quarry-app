class_name Pile
extends Node3D
## A heap of dirt or rock. `amount` is scoops; the heap's size follows it.
## Dig piles slowly refill so there is always something to dig.

var amount := 6.0
var max_amount := 12.0
var refill := 0.0          # scoops per second when below `refill_to`
var refill_to := 0.0
var color := Color(0.55, 0.38, 0.22)
var mesh: MeshInstance3D
var rocks: Array[MeshInstance3D] = []
var ground_y := 0.0


func _init(start: float, cap: float, col: Color) -> void:
	amount = start
	max_amount = cap
	color = col


func _ready() -> void:
	mesh = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 1.0
	sm.is_hemisphere = true
	sm.radial_segments = 24
	sm.rings = 8
	mesh.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = color.lightened(0.35)
	m.albedo_texture = load("res://assets/tex/dirt.jpg") if (color.s > 0.2 and color.r < 0.75) else load("res://assets/tex/gravel.jpg")
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * 0.12
	m.roughness = 1.0
	mesh.material_override = m
	add_child(mesh)
	var rm := StandardMaterial3D.new()
	rm.albedo_color = color.darkened(0.25)
	for i in 7:
		var r := MeshInstance3D.new()
		var b := SphereMesh.new()
		b.radius = randf_range(0.25, 0.5)
		b.height = b.radius * 1.6
		b.radial_segments = 6
		b.rings = 3
		r.mesh = b
		r.material_override = rm
		r.set_meta("dir", Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized() * randf_range(0.2, 0.9))
		mesh.add_child(r)
		rocks.append(r)
	_resize()


func radius() -> float:
	return 1.2 + sqrt(maxf(amount, 0.0)) * 1.5


func take(n := 1.0) -> bool:
	if amount < 0.5:
		return false
	amount = maxf(amount - n, 0.0)
	_resize()
	return true


func add(n := 1.0) -> void:
	amount = minf(amount + n, max_amount)
	_resize()


func _process(dt: float) -> void:
	if refill > 0.0 and amount < refill_to:
		amount += refill * dt
		_resize()


func _resize() -> void:
	var r := radius()
	var h := 0.4 + sqrt(maxf(amount, 0.0)) * 0.9
	mesh.visible = amount > 0.05
	mesh.scale = Vector3(r, h, r)
	for rk in rocks:
		var d: Vector2 = rk.get_meta("dir")
		rk.position = Vector3(d.x, 0.1, d.y)
		rk.scale = Vector3(1.0 / r, 1.0 / h, 1.0 / r) * clampf(r / 3.0, 0.6, 1.6)
