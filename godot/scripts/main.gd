extends Node3D
## Quarry Builders: pick a machine at the bottom, drive it, and move dirt.
## Drive: the stick (up = go, sideways = turn; let go = stop) or tap the ground to drive there.
## The big button does the machine's job: dig and dump, scoop, push, tip the truck bed.
## Hard parts drive themselves: "dig" drives to the nearest dirt first, a full truck drives
## itself to the crusher and back, and the machines you aren't driving help out.

const CRUSHER := Vector3(165, 0, 45)
const DUMP_SPOT := Vector3(160, 0, 28)
const PIT_R := 107.0
const WORLD_R := 185.0

var heights: Heights
var vehicles: Array[Vehicle] = []
var cur: Vehicle
var piles: Array[Pile] = []
var stock: Pile
var crushed := 0
var cam: Camera3D
var cam_yaw := 0.0
var cam_pitch := 0.42
var cam_dist := 22.0
var dump_ring: MeshInstance3D
var target_ring: MeshInstance3D

# HUD
var hud: CanvasLayer
var stick: Stick
var action_btn: Tap
var horn_btn: Tap
var picker: Array[Tap] = []
var thumbs := {}
var score_lbl: Label
var _drag_id := -1
var _drag_start := Vector2.ZERO
var _drag_moved := false
var _drag_t := 0
var _t := 0.0
var autoplay_dir := ""
var _shot_t := 0.0
var _shots := 0
var horn_player := AudioStreamPlayer.new()
var engine_player := AudioStreamPlayer.new()


func _ready() -> void:
	randomize()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--autoplay="):
			autoplay_dir = a.substr(11)
	heights = Heights.new("res://assets/models/quarry_heights.bin")
	_load_road()
	_build_world()
	_build_site()
	_spawn_vehicles()
	_build_hud()
	add_child(horn_player)
	add_child(engine_player)
	horn_player.stream = Synth.horn()
	engine_player.stream = Synth.engine()
	engine_player.volume_db = linear_to_db(0.25)
	engine_player.play()
	Sfx.start_music()
	_select(vehicles[0] if vehicles.size() > 0 else null)
	for a in OS.get_cmdline_user_args():
		if a == "--full-truck":
			# Test: start in a loaded dump truck so the road trip to the crusher runs right away.
			for v in vehicles:
				if v is DumpTruck:
					v.add_load(v.capacity)
					_select(v)
					break
	if autoplay_dir != "":
		DirAccess.make_dir_recursive_absolute(autoplay_dir)
	await get_tree().create_timer(0.8).timeout
	Sfx.say("Welcome to the quarry! Let's dig!")


# ---------------------------------------------------------------- world

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.3, 0.55, 0.9)
	sm.sky_horizon_color = Color(0.8, 0.87, 0.95)
	sm.ground_horizon_color = Color(0.8, 0.87, 0.95)
	sm.ground_bottom_color = Color(0.45, 0.4, 0.35)
	sky.sky_material = sm
	e.sky = sky
	e.background_mode = Environment.BG_SKY
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.55
	e.fog_enabled = true
	e.fog_light_color = Color(0.8, 0.86, 0.93)
	e.fog_density = 0.0025
	e.fog_sky_affect = 0.0
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -40, 0)
	sun.light_energy = 1.2
	sun.light_color = Color(1, 0.96, 0.9)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 90.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(sun)
	var terrain: Node3D = load("res://assets/models/quarry_terrain.glb").instantiate()
	add_child(terrain)
	var gm := ShaderMaterial.new()
	gm.shader = load("res://assets/terrain.gdshader")
	gm.set_shader_parameter("mode", 1)
	gm.set_shader_parameter("tex_a", load("res://assets/tex/gravel.jpg"))
	gm.set_shader_parameter("tex_b", load("res://assets/tex/grass.jpg"))
	gm.set_shader_parameter("tex_c", load("res://assets/tex/rock.jpg"))
	gm.set_shader_parameter("tex_d", load("res://assets/tex/dirt.jpg"))
	for mi in terrain.find_children("*", "MeshInstance3D", true, false):
		(mi as MeshInstance3D).material_override = gm
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func ground_at(x: float, z: float) -> float:
	return heights.at(x, z)


func drivable(x: float, z: float) -> bool:
	if Vector2(x, z).length() > WORLD_R:
		return false
	return heights.normal(x, z).y > 0.82


func _build_site() -> void:
	# Dig piles of dirt, gravel and sand on the pit floor and the benches (spots from site/piles.json).
	var cols := {"dirt": Color(0.62, 0.42, 0.24), "gravel": Color(0.6, 0.6, 0.6), "sand": Color(0.86, 0.72, 0.45)}
	var spots: Array = JSON.parse_string(FileAccess.get_file_as_string("res://assets/models/site/piles.json"))
	for s in spots:
		var p := Pile.new(randf_range(7.0, 12.0), 14.0, cols.get(s[2], cols["dirt"]))
		p.refill = 0.08
		p.refill_to = 10.0
		add_child(p)
		p.global_position = Vector3(s[0], ground_at(s[0], s[1]) - 0.2, s[1])
		piles.append(p)
	# Rock crusher: hopper on legs, a conveyor and the stockpile it makes.
	var base_y := ground_at(CRUSHER.x, CRUSHER.z)
	var crusher := Node3D.new()
	crusher.position = Vector3(CRUSHER.x, base_y, CRUSHER.z)
	add_child(crusher)
	var yel := _mat(Color(0.98, 0.75, 0.1))
	var grey := _mat(Color(0.35, 0.37, 0.4))
	_box(crusher, Vector3(7, 4, 7), Vector3(0, 2, 0), grey)
	var hop := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 6.0
	cm.bottom_radius = 2.8
	cm.height = 3.5
	cm.radial_segments = 4
	hop.mesh = cm
	hop.material_override = yel
	hop.position = Vector3(0, 5.8, 0)
	hop.rotation.y = PI / 4
	crusher.add_child(hop)
	var conv := _box(crusher, Vector3(2.2, 0.5, 22), Vector3(0, 6, 13), grey)
	conv.rotation.x = deg_to_rad(-14)
	_box(crusher, Vector3(0.5, 6, 0.5), Vector3(0, 3, 22), yel)
	stock = Pile.new(4.0, 60.0, Color(0.6, 0.6, 0.6))
	add_child(stock)
	stock.global_position = Vector3(CRUSHER.x, ground_at(CRUSHER.x, CRUSHER.z + 26) - 0.2, CRUSHER.z + 26)
	dump_ring = _ring(Color(1, 0.85, 0.1), 6.0)
	dump_ring.global_position = Vector3(DUMP_SPOT.x, ground_at(DUMP_SPOT.x, DUMP_SPOT.z) + 0.15, DUMP_SPOT.z)
	target_ring = _ring(Color(0.3, 1, 0.4), 2.0)
	target_ring.visible = false
	_scatter_props()


func _ring(col: Color, r: float) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = r - 0.5
	t.outer_radius = r
	m.mesh = t
	m.scale.y = 0.2
	m.material_override = _mat(col, true)
	add_child(m)
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, m: Material) -> MeshInstance3D:
	var b := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	b.mesh = bm
	b.material_override = m
	b.position = pos
	parent.add_child(b)
	return b


func _mat(c: Color, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.7
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


## Props from assets/models/site/props.json: [{"file": "cone.glb", "at": [x, z], "yaw": 0, "size": 1}, ...]
func _scatter_props() -> void:
	var path := "res://assets/models/site/props.json"
	if not FileAccess.file_exists(path):
		return
	var list: Array = JSON.parse_string(FileAccess.get_file_as_string(path))
	var cache := {}
	for it in list:
		var f: String = "res://assets/models/site/" + it["file"]
		if not cache.has(f):
			cache[f] = load(f)
		if cache[f] == null:
			continue
		var n: Node3D = cache[f].instantiate()
		var at: Array = it["at"]
		n.position = Vector3(at[0], ground_at(at[0], at[1]), at[1])
		n.rotation.y = deg_to_rad(it.get("yaw", 0.0))
		add_child(n)
		var sz := float(it.get("size", 1.0))
		if it.has("height"):
			var box := _bounds(n)
			sz = float(it["height"]) / maxf(box.size.y, 0.001)
		n.scale = Vector3.ONE * sz
		var fname: String = it["file"]
		if fname.begins_with("LP_") or fname.begins_with("rocks") or fname.begins_with("pipe"):
			_paint(n, fname.begins_with("pipe"))


var _rock_mat: StandardMaterial3D
var _concrete_mat: StandardMaterial3D

## Some CC0 props lost their textures in conversion: give rocks photo rock, pipes plain concrete.
func _paint(n: Node3D, concrete: bool) -> void:
	if _rock_mat == null:
		_rock_mat = StandardMaterial3D.new()
		_rock_mat.albedo_texture = load("res://assets/tex/rock.jpg")
		_rock_mat.albedo_color = Color(0.85, 0.8, 0.75)
		_rock_mat.uv1_triplanar = true
		_rock_mat.uv1_world_triplanar = true
		_rock_mat.uv1_scale = Vector3.ONE * 0.25
		_rock_mat.roughness = 1.0
		_concrete_mat = StandardMaterial3D.new()
		_concrete_mat.albedo_texture = load("res://assets/tex/gravel.jpg")
		_concrete_mat.albedo_color = Color(0.72, 0.72, 0.7)
		_concrete_mat.uv1_triplanar = true
		_concrete_mat.uv1_scale = Vector3.ONE * 0.5
	for c in n.find_children("*", "MeshInstance3D", true, false):
		(c as MeshInstance3D).material_override = _concrete_mat if concrete else _rock_mat


func _bounds(n: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var b := n.global_transform.affine_inverse() * mi.global_transform * mi.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out


# ---------------------------------------------------------------- vehicles

func _spawn_vehicles() -> void:
	var path := "res://assets/models/vehicles/catalog.json"
	if not FileAccess.file_exists(path):
		return
	var list: Array = JSON.parse_string(FileAccess.get_file_as_string(path))
	for cfg in list:
		var ps: PackedScene = load("res://assets/models/vehicles/" + cfg["file"])
		if ps == null:
			continue
		var v: Vehicle
		match cfg.get("kind", "plain"):
			"excavator":
				v = Excavator.new()
			"dump_truck":
				v = DumpTruck.new()
			"loader":
				v = Loader.new()
			"bulldozer":
				v = Dozer.new()
			_:
				v = Vehicle.new()
		add_child(v)
		v.setup(ps, cfg, self)
		var at: Array = cfg.get("at", [0, 0])
		v.global_position = Vector3(at[0], ground_at(at[0], at[1]), at[1])
		v.yaw = deg_to_rad(cfg.get("face", 0.0))
		vehicles.append(v)


func _select(v: Vehicle) -> void:
	if v == null:
		return
	if cur:
		cur.throttle = 0.0
		cur.steer = 0.0
	cur = v
	cur.goal = null
	cam_yaw = cur.yaw
	cam_dist = clampf(cur.length * 2.4, 14.0, 34.0)
	Sfx.say(cur.title + "!")
	for p in picker:
		p.queue_redraw()


func nearest_pile(from: Vector3, min_amount := 0.8) -> Pile:
	var best: Pile = null
	var bd := INF
	for p in piles:
		if p.amount < min_amount:
			continue
		var d := Vector2(p.global_position.x - from.x, p.global_position.z - from.z).length() - p.radius()
		if d < bd:
			bd = d
			best = p
	return best


func nearest_vehicle(from: Vector3, kinds: Array, max_d := INF, not_full := false) -> Vehicle:
	var best: Vehicle = null
	var bd := max_d
	for v in vehicles:
		if not (v.kind in kinds):
			continue
		if not_full and v.load >= v.capacity - 0.01:
			continue
		var d := v.global_position.distance_to(from)
		if d < bd:
			bd = d
			best = v
	return best


## Drop dirt on the ground at `at`: into the crusher if close, else onto/into a pile.
func drop_dirt(at: Vector3, n: float) -> void:
	if Vector2(at.x - CRUSHER.x, at.z - CRUSHER.z).length() < 14.0 or Vector2(at.x - DUMP_SPOT.x, at.z - DUMP_SPOT.z).length() < 9.0:
		crushed += int(round(n))
		stock.add(n)
		score_lbl.text = str(crushed)
		Synth.play_rumble(self)
		if crushed % 5 == 0 or n >= 2.5:
			Sfx.chime()
			Sfx.say(["Great job!", "Rocks in the crusher!", "You're a super builder!", "Crunch crunch crunch!"][randi() % 4])
		return
	for p in piles:
		if Vector2(p.global_position.x - at.x, p.global_position.z - at.z).length() < p.radius() + 1.5:
			p.add(n)
			Synth.play_rumble(self)
			return
	var np := Pile.new(n, 14.0, Color(0.62, 0.42, 0.24))
	add_child(np)
	np.global_position = Vector3(at.x, ground_at(at.x, at.z) - 0.2, at.z)
	piles.append(np)
	Synth.play_rumble(self)


var road: Array[Vector3] = []   # haul road, floor end first (from quarry_road.json)


func _load_road() -> void:
	var path := "res://assets/models/quarry_road.json"
	if not FileAccess.file_exists(path):
		return
	for p in JSON.parse_string(FileAccess.get_file_as_string(path)):
		road.append(Vector3(p[0], p[1], p[2]))


func in_pit(p: Vector3) -> bool:
	return Vector2(p.x, p.z).length() < PIT_R - 3.0 and p.y < -1.0


## Waypoints from `a` to `b`: straight if both are in the pit or both outside, else along the haul road.
func route(a: Vector3, b: Vector3) -> Array:
	if road.is_empty() or in_pit(a) == in_pit(b):
		return [b]
	var near := func(p: Vector3) -> int:
		var bi := 0
		var bd := INF
		for i in road.size():
			var d := road[i].distance_to(p)
			if d < bd:
				bd = d
				bi = i
		return bi
	var out: Array = []
	if in_pit(a):
		for i in range(near.call(a), road.size()):
			out.append(road[i])
	else:
		for i in range(road.size() - 1, near.call(b) - 1, -1):
			out.append(road[i])
	out.append(b)
	return out


func near_dump(p: Vector3) -> bool:
	return Vector2(p.x - DUMP_SPOT.x, p.z - DUMP_SPOT.z).length() < 9.0


# ---------------------------------------------------------------- loop

func _physics_process(dt: float) -> void:
	_t += dt
	if cur == null:
		return
	# Camera follows behind the machine you drive; drag on the screen swings it around.
	var want_yaw := cur.yaw if absf(cur.speed) > 0.5 and _drag_id == -1 else cam_yaw
	cam_yaw = lerp_angle(cam_yaw, want_yaw, dt * 1.5)
	var dir := Vector3(sin(cam_yaw) * cos(cam_pitch), sin(cam_pitch), cos(cam_yaw) * cos(cam_pitch))
	var focus := cur.global_position + Vector3(0, cur.length * 0.25, 0)
	var cp := focus + dir * cam_dist
	cp.y = maxf(cp.y, ground_at(cp.x, cp.z) + 2.0)
	cam.position = cam.position.lerp(cp, clampf(dt * 5, 0, 1))
	cam.look_at(focus)
	dump_ring.scale = Vector3.ONE * (1.0 + 0.06 * sin(_t * 4)) * Vector3(1, 0.2, 1)
	if cur.goal != null:
		target_ring.visible = true
		var g: Vector3 = cur.goal
		target_ring.global_position = Vector3(g.x, ground_at(g.x, g.z) + 0.2, g.z)
	else:
		target_ring.visible = false
	engine_player.pitch_scale = 0.8 + absf(cur.speed) / maxf(cur.max_speed, 1.0) * 0.6 + (0.2 if cur.busy else 0.0)
	_helpers()
	action_btn.queue_redraw()
	if Engine.get_physics_frames() % 15 == 0:
		for pk in picker:
			pk.queue_redraw()
	if autoplay_dir != "":
		_autoplay(dt)


## Machines you aren't driving help: trucks that are full go dump, excavators load nearby trucks.
func _helpers() -> void:
	for v in vehicles:
		if v == cur or v.busy or v.goal != null:
			continue
		if v is DumpTruck:
			if v.load >= v.capacity - 0.01:
				(v as DumpTruck).go_dump()
		elif v is Excavator:
			var t := nearest_vehicle(v.global_position, ["dump_truck"], v.length * 1.5, true)
			if t and absf(t.speed) < 0.2 and t.goal == null:
				(v as Excavator).act()


# ---------------------------------------------------------------- HUD + input

func _build_hud() -> void:
	cam = Camera3D.new()
	cam.fov = 60
	cam.far = 1200
	add_child(cam)
	hud = CanvasLayer.new()
	add_child(hud)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(root)
	stick = Stick.new(false, func(x: float, y: float) -> void:
		if cur == null:
			return
		cur.throttle = maxf(y, 0.0) if absf(x) < 0.9 else maxf(y, 0.35)
		cur.steer = -x
		if x != 0.0 or y != 0.0:
			cur.goal = null)
	root.add_child(stick)
	action_btn = Tap.new(Vector2(230, 230), _paint_action, func() -> void:
		if cur and cur.has_method("act"):
			cur.act()
		else:
			_honk())
	root.add_child(action_btn)
	horn_btn = Tap.new(Vector2(130, 130), _paint_horn, _honk)
	root.add_child(horn_btn)
	score_lbl = Label.new()
	score_lbl.text = "0"
	score_lbl.add_theme_font_size_override("font_size", 56)
	score_lbl.add_theme_color_override("font_color", Color.WHITE)
	score_lbl.add_theme_color_override("font_outline_color", Color(0.3, 0.2, 0.05))
	score_lbl.add_theme_constant_override("outline_size", 14)
	root.add_child(score_lbl)
	var rock_icon := Tap.new(Vector2(70, 70), func(c: Control) -> void:
		c.draw_circle(Vector2(35, 40), 26, Color(0.6, 0.6, 0.62))
		c.draw_circle(Vector2(25, 32), 12, Color(0.75, 0.75, 0.77)))
	rock_icon.name = "RockIcon"
	root.add_child(rock_icon)
	_make_thumbs()
	for v in vehicles:
		var vv := v
		var t := Tap.new(Vector2(150, 110), func(c: Control) -> void: _paint_pick(c, vv), func() -> void: _select(vv))
		root.add_child(t)
		picker.append(t)
	get_viewport().size_changed.connect(_layout)
	_layout()


func _layout() -> void:
	var vs := get_viewport().get_visible_rect().size
	var pad := 30.0
	stick.position = Vector2(pad, vs.y - stick.size.y - pad - 120)
	action_btn.position = Vector2(vs.x - action_btn.size.x - pad, vs.y - action_btn.size.y - pad - 130)
	horn_btn.position = Vector2(vs.x - horn_btn.size.x - pad - 250, vs.y - horn_btn.size.y - pad - 150)
	score_lbl.position = Vector2(vs.x - 150, 26)
	hud.get_child(0).get_node("RockIcon").position = Vector2(vs.x - 230, 26)
	var n := picker.size()
	var w := minf(150.0, (vs.x - 40) / maxf(n, 1) - 10)
	for i in n:
		picker[i].size = Vector2(w, 110)
		picker[i].position = Vector2(vs.x / 2 - n * (w + 10) / 2 + i * (w + 10), vs.y - 120)


## Render a little picture of every machine once, for the picker buttons.
func _make_thumbs() -> void:
	for v in vehicles:
		var sv := SubViewport.new()
		sv.size = Vector2i(256, 180)
		sv.transparent_bg = true
		sv.own_world_3d = true
		sv.render_target_update_mode = SubViewport.UPDATE_ONCE
		add_child(sv)
		var copy: Node3D = v.model.duplicate()
		var holder := Node3D.new()
		holder.add_child(copy)
		copy.transform = v.model.get_parent().transform * v.model.transform
		sv.add_child(holder)
		var l := DirectionalLight3D.new()
		l.rotation_degrees = Vector3(-40, -30, 0)
		sv.add_child(l)
		var amb := WorldEnvironment.new()
		var e := Environment.new()
		e.background_mode = Environment.BG_CLEAR_COLOR
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(0.7, 0.7, 0.7)
		amb.environment = e
		sv.add_child(amb)
		var c := Camera3D.new()
		c.fov = 35
		var L := v.length
		c.position = Vector3(L * 1.15, L * 0.75, -L * 1.25)
		sv.add_child(c)
		c.look_at(Vector3(0, L * 0.18, 0))
		thumbs[v] = sv.get_texture()


func _paint_pick(c: Control, v: Vehicle) -> void:
	var on := v == cur
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 0.8, 0.15, 0.95) if on else Color(0.15, 0.15, 0.15, 0.55)
	sb.set_corner_radius_all(20)
	sb.border_color = Color(1, 1, 1, 0.9 if on else 0.4)
	sb.set_border_width_all(5 if on else 3)
	c.draw_style_box(sb, Rect2(Vector2.ZERO, c.size))
	if thumbs.has(v):
		var tex: Texture2D = thumbs[v]
		var s := minf(c.size.x / 256.0, c.size.y / 180.0) * 0.98
		var sz := Vector2(256, 180) * s
		c.draw_texture_rect(tex, Rect2((c.size - sz) / 2, sz), false)
	if v.capacity > 0 and v.load > 0.01:
		c.draw_circle(Vector2(c.size.x - 18, 18), 12, Color(0.55, 0.38, 0.22))


func _paint_action(c: Control) -> void:
	var r := c.size.x / 2
	var ctr := c.size / 2
	var label := "HONK"
	var col := Color(0.3, 0.6, 0.95)
	if cur and cur.has_method("action_label"):
		label = cur.action_label()
	match label:
		"DIG", "SCOOP":
			col = Color(0.95, 0.6, 0.1)
		"DUMP":
			col = Color(0.8, 0.35, 0.15)
		"GO":
			col = Color(0.25, 0.75, 0.3)
		"PUSH":
			col = Color(0.95, 0.75, 0.1)
		"WAIT":
			col = Color(0.5, 0.5, 0.5)
	var pulse := 1.0 + (0.04 * sin(_t * 6) if label != "WAIT" else 0.0)
	c.draw_circle(ctr, r * pulse, Color(1, 1, 1, 0.9))
	c.draw_circle(ctr, (r - 8) * pulse, col)
	c.draw_circle(ctr + Vector2(-r * 0.2, -r * 0.25), r * 0.45, col.lightened(0.15))
	var f := ThemeDB.fallback_font
	c.draw_string(f, Vector2(0, ctr.y + 20), label, HORIZONTAL_ALIGNMENT_CENTER, c.size.x, 58, Color.WHITE)


func _paint_horn(c: Control) -> void:
	var ctr := c.size / 2
	c.draw_circle(ctr, 62, Color(1, 1, 1, 0.85))
	c.draw_circle(ctr, 55, Color(0.85, 0.2, 0.25))
	# Little horn shape.
	var pts := PackedVector2Array([ctr + Vector2(-30, -10), ctr + Vector2(-8, -10), ctr + Vector2(25, -28), ctr + Vector2(25, 28), ctr + Vector2(-8, 10), ctr + Vector2(-30, 10)])
	c.draw_colored_polygon(pts, Color.WHITE)


func _honk() -> void:
	horn_player.pitch_scale = 1.0 if cur == null else clampf(10.0 / cur.length, 0.7, 1.3)
	horn_player.play()


func _unhandled_input(event: InputEvent) -> void:
	# One finger on empty screen: drag swings the camera, a quick tap drives there.
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		if e.pressed and _drag_id == -1:
			_drag_id = e.index
			_drag_start = e.position
			_drag_moved = false
			_drag_t = Time.get_ticks_msec()
		elif not e.pressed and e.index == _drag_id:
			_drag_id = -1
			if not _drag_moved and Time.get_ticks_msec() - _drag_t < 450:
				_tap_ground(e.position)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _drag_id:
			if d.position.distance_to(_drag_start) > 25:
				_drag_moved = true
			if _drag_moved:
				cam_yaw -= d.relative.x * 0.006
				cam_pitch = clampf(cam_pitch + d.relative.y * 0.004, 0.15, 1.2)


func _tap_ground(sp: Vector2) -> void:
	if cur == null or cur.busy:
		return
	var o := cam.project_ray_origin(sp)
	var dir := cam.project_ray_normal(sp)
	var p := o
	for i in 600:
		p += dir * 0.5
		if p.y <= ground_at(p.x, p.z):
			if drivable(p.x, p.z):
				cur.drive_route(p)
				Synth.beep(self)
			return


# ---------------------------------------------------------------- test autopilot

var _auto_step := 0
var _auto_t := 0.0

func _autoplay(dt: float) -> void:
	_auto_t += dt
	_shot_t += dt
	if _shot_t > 3.0:
		_shot_t = 0
		_shots += 1
		get_viewport().get_texture().get_image().save_png("%s/shot_%02d.png" % [autoplay_dir, _shots])
		print("AUTOPLAY shot %d crushed %d cur %s load %.1f pos %s goal %s path %d busy %s" % [_shots, crushed, cur.title, cur.load, cur.global_position.round(), str(cur.goal.round()) if cur.goal != null else "-", cur.path.size(), cur.busy])
		if _shots >= 40:
			get_tree().quit()
	# Press the big button whenever the machine is idle; swap machines now and then.
	if not cur.busy and cur.goal == null and _auto_t > 1.0:
		_auto_t = 0.0
		_auto_step += 1
		if _auto_step % 9 == 0 and vehicles.size() > 1:
			_select(vehicles[(vehicles.find(cur) + 1) % vehicles.size()])
		elif cur.has_method("act"):
			cur.act()
