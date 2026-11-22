extends SceneTree
## Renders the app icon (1024x1024) from the game's own models.
##   godot --resolution 1024x1024 -s ../scripts/make_icon.gd   (run from godot/)
func _init() -> void:
	var dino := OS.get_cmdline_user_args().has("--quarry") == false
	var we := WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.15, 0.55, 0.35) if dino else Color(0.2, 0.5, 0.95)
	sm.sky_horizon_color = Color(0.75, 0.95, 0.55) if dino else Color(1.0, 0.85, 0.35)
	sm.ground_bottom_color = Color(0.2, 0.45, 0.15) if dino else Color(0.7, 0.5, 0.25)
	sm.ground_horizon_color = sm.sky_horizon_color
	sky.sky_material = sm
	e.sky = sky
	e.background_mode = Environment.BG_SKY
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.8
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	we.environment = e
	root.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 40, 0)
	sun.light_energy = 1.4
	root.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 40
	root.add_child(cam)
	var hero: Node3D
	if dino:
		hero = load("res://assets/models/dinos/trex.glb").instantiate()
		root.add_child(hero)
		for p in [[Vector3(-7, 0, -6), 1.9], [Vector3(8, 0, -9), 2.3], [Vector3(-11, 0, -14), 2.6]]:
			var palm: Node3D = load("res://assets/models/jungle/PalmTree_1.glb").instantiate()
			root.add_child(palm)
			palm.position = p[0]
			palm.scale = Vector3.ONE * p[1]
	else:
		hero = load("res://assets/models/vehicles/excavator.glb").instantiate()
		root.add_child(hero)
	await process_frame
	var box := AABB()
	var first := true
	for c in hero.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var s := 8.0 / maxf(maxf(box.size.x, box.size.z), box.size.y)
	hero.scale = Vector3.ONE * s
	hero.position = -Vector3(box.get_center().x, box.position.y, box.get_center().z) * s
	hero.rotation.y = deg_to_rad(-35.0 if dino else 145.0)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.35, 0.6, 0.2) if dino else Color(0.78, 0.6, 0.38)
	ground.material_override = gm
	root.add_child(ground)
	var h := box.size.y * s
	cam.look_at_from_position(Vector3(0, h * 0.55, 11.5), Vector3(0, h * 0.45, 0))
	await create_timer(0.6).timeout
	var img := root.get_texture().get_image()
	img.resize(1024, 1024, Image.INTERPOLATE_LANCZOS)
	img.convert(Image.FORMAT_RGB8)
	img.save_png("res://icon.png")
	print("ICON saved")
	quit()
