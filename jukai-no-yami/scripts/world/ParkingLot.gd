extends "res://scripts/world/LevelManager.gd"

# _WORLD_SPAWN is inherited from LevelManager — re-declaring it here is a
# parse error in Godot 4 (constants cannot shadow parent class members).
const _CAR_BUILDER := preload("res://scripts/world/JapaneseCompactCarBuilder.gd")
const _LOT_PROPS := preload("res://scripts/world/ParkingLotProps.gd")

func _ready() -> void:
	level_ambient_key = "forest_night"
	next_level_path = "res://scenes/levels/ForestEntrance.tscn"

	_make_world_env(
		Color(0.02, 0.018, 0.032),
		Color(0.03, 0.026, 0.048),
		Color(0.04, 0.034, 0.058),
		0.014)
	_make_directional_light(Color(0.12, 0.10, 0.18), 0.08)

	# Wet asphalt parking lot
	_make_asphalt_floor(Vector3(44, 0.2, 32))
	_LOT_PROPS.spawn_decor(self, 8801)

	# Dirt path from parking lot into forest (runs along -Z)
	_make_dirt_path(Vector3(0, 0, -14), 40, 4.6)

	# Player's car — compact JDM sedan, slightly worn, facing the forest path
	_CAR_BUILDER.build(
		self, Vector3(-6.2, 0, 8.5),
		Color(0.14, 0.16, 0.22),
		-12.0,
		{"name": "PlayerCar", "dirt": 0.28, "headlights_on": true, "front_steer_deg": 4.0})

	_CAR_BUILDER.build(
		self, Vector3(7.5, 0, 10.5),
		Color(0.18, 0.14, 0.12),
		18.0,
		{"name": "AbandonedCar", "abandoned": true, "dirt": 0.55, "rust": 0.22, "headlights_on": false})

	# Parking lot lights on poles
	_spawn_lot_light(Vector3(-8, 0, 2))
	_spawn_lot_light(Vector3(10, 0, -1))
	_spawn_lot_light(Vector3(0, 0, 8))

	_WORLD_SPAWN.add_tree_spawner(self, Vector3(-20, 0, -30), {
		"count": 68, "area_size": Vector2(24, 52), "avoid_center_radius": 14.0,
		"min_scale": 1.0, "max_scale": 2.3, "random_seed": 501,
		"cluster_count": 7, "cluster_density": 0.78})
	_WORLD_SPAWN.add_tree_spawner(self, Vector3(20, 0, -30), {
		"count": 68, "area_size": Vector2(24, 52), "avoid_center_radius": 14.0,
		"min_scale": 1.0, "max_scale": 2.3, "random_seed": 502,
		"cluster_count": 7, "cluster_density": 0.78})
	_WORLD_SPAWN.add_ribbon_spawner(self, Vector3(0, 0, -20), {
		"ribbon_count": 18, "area_size": Vector2(20, 30)})

	# Wooden torii-style gate at forest entrance
	_spawn_gate(Vector3(0, 0, -12))

	# Info sign board near path start
	_spawn_sign(Vector3(3.5, 0, -8))

	# Exit trigger — when player walks deep into path
	_make_exit_trigger(Vector3(0, 1.5, -33), Vector3(8, 5, 2))

	_spawn_player(Vector3(-4, 1, 12))
	_spawn_hud()
	_start_common()
	call_deferred("_play_intro")

func _play_intro() -> void:
	await get_tree().create_timer(1.0).timeout
	NarrativeDirector.play_game_opening()

func _make_asphalt_floor(size: Vector3) -> void:
	var body = StaticBody3D.new()
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = size
	col.shape = shape
	col.position = Vector3(0, -size.y * 0.5, 0)
	body.add_child(col)
	var mi = MeshInstance3D.new()
	var bm = BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = Vector3(0, -size.y * 0.5, 0)
	_LOT_PROPS.apply_wet_asphalt(mi)
	body.add_child(mi)
	add_child(body)

func _make_dirt_path(center: Vector3, length: float, width: float) -> void:
	var body = StaticBody3D.new()
	body.position = center
	var col = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(width, 0.24, length)
	col.shape = shape
	body.add_child(col)
	var mi = MeshInstance3D.new()
	var bm = BoxMesh.new()
	bm.size = Vector3(width, 0.24, length)
	mi.mesh = bm
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.20, 0.15, 0.10)
	mat.roughness = 0.98
	mat.metallic_specular = 0.01
	mi.material_override = mat
	body.add_child(mi)
	add_child(body)

func _spawn_lot_light(pos: Vector3) -> void:
	var pole = StaticBody3D.new()
	pole.position = pos

	var pole_mat = StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.38, 0.38, 0.40)
	pole_mat.roughness = 0.72

	var pole_m = CylinderMesh.new()
	pole_m.height = 6.0
	pole_m.top_radius = 0.038
	pole_m.bottom_radius = 0.065
	var pole_mi = MeshInstance3D.new()
	pole_mi.mesh = pole_m
	pole_mi.material_override = pole_mat
	pole_mi.position = Vector3(0, 3.0, 0)
	pole.add_child(pole_mi)

	var arm_m = BoxMesh.new()
	arm_m.size = Vector3(1.4, 0.07, 0.07)
	var arm_mi = MeshInstance3D.new()
	arm_mi.mesh = arm_m
	arm_mi.material_override = pole_mat
	arm_mi.position = Vector3(0.7, 6.0, 0)
	pole.add_child(arm_mi)

	var fixture_m = BoxMesh.new()
	fixture_m.size = Vector3(0.42, 0.10, 0.22)
	var fixture_mi = MeshInstance3D.new()
	fixture_mi.mesh = fixture_m
	var fix_mat = StandardMaterial3D.new()
	fix_mat.albedo_color = Color(0.85, 0.80, 0.60)
	fix_mat.emission_enabled = true
	fix_mat.emission = Color(0.72, 0.64, 0.38) * 0.45
	fixture_mi.material_override = fix_mat
	fixture_mi.position = Vector3(1.4, 6.0, 0)
	pole.add_child(fixture_mi)

	var light = OmniLight3D.new()
	light.light_color = Color(0.82, 0.78, 0.60)
	light.light_energy = 8.0
	light.omni_range = 24.0
	light.shadow_enabled = true
	light.position = Vector3(1.4, 5.95, 0)
	pole.add_child(light)

	var ps = CylinderShape3D.new()
	ps.height = 6.0
	ps.radius = 0.065
	var pc = CollisionShape3D.new()
	pc.shape = ps
	pc.position = Vector3(0, 3.0, 0)
	pole.add_child(pc)

	add_child(pole)

func _spawn_gate(pos: Vector3) -> void:
	var gate = StaticBody3D.new()
	gate.position = pos
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.09, 0.05)
	mat.roughness = 0.94

	# Two vertical posts
	for side in [-1, 1]:
		var pm = BoxMesh.new()
		pm.size = Vector3(0.24, 5.2, 0.24)
		var pi = MeshInstance3D.new()
		pi.mesh = pm; pi.material_override = mat
		pi.position = Vector3(side * 2.8, 2.6, 0)
		gate.add_child(pi)

	# Top beam
	var tb = BoxMesh.new()
	tb.size = Vector3(6.2, 0.26, 0.26)
	var tbi = MeshInstance3D.new()
	tbi.mesh = tb; tbi.material_override = mat
	tbi.position = Vector3(0, 5.35, 0)
	gate.add_child(tbi)

	# Lower beam
	var lb = BoxMesh.new()
	lb.size = Vector3(5.6, 0.20, 0.20)
	var lbi = MeshInstance3D.new()
	lbi.mesh = lb; lbi.material_override = mat
	lbi.position = Vector3(0, 4.45, 0)
	gate.add_child(lbi)

	# Rope ribbons hanging from top beam
	for i in 5:
		var rm = BoxMesh.new()
		rm.size = Vector3(0.03, 0.9, 0.03)
		var rmi = MeshInstance3D.new()
		rmi.mesh = rm
		var rmat = StandardMaterial3D.new()
		rmat.albedo_color = Color(0.68, 0.65, 0.62, 0.45)
		rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rmat.emission_enabled = false
		rmi.material_override = rmat
		rmi.position = Vector3(-2.0 + i * 1.0, 4.90, 0)
		gate.add_child(rmi)

	# Collision
	var bs = BoxShape3D.new()
	bs.size = Vector3(6.4, 5.6, 0.5)
	var bc = CollisionShape3D.new()
	bc.shape = bs; bc.position = Vector3(0, 2.8, 0)
	gate.add_child(bc)

	add_child(gate)

func _spawn_sign(pos: Vector3) -> void:
	var sign_body = StaticBody3D.new()
	sign_body.position = pos

	var post_m = CylinderMesh.new()
	post_m.height = 2.2; post_m.top_radius = 0.04; post_m.bottom_radius = 0.05
	var post_mi = MeshInstance3D.new()
	post_mi.mesh = post_m
	var post_mat = StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.22, 0.16, 0.10)
	post_mat.roughness = 0.95
	post_mi.material_override = post_mat
	post_mi.position = Vector3(0, 1.1, 0)
	sign_body.add_child(post_mi)

	var board_m = BoxMesh.new()
	board_m.size = Vector3(1.1, 0.60, 0.05)
	var board_mi = MeshInstance3D.new()
	board_mi.mesh = board_m
	var board_mat = StandardMaterial3D.new()
	board_mat.albedo_color = Color(0.55, 0.42, 0.22)
	board_mat.roughness = 0.92
	board_mi.material_override = board_mat
	board_mi.position = Vector3(0, 2.1, 0)
	sign_body.add_child(board_mi)

	var warn = Label3D.new()
	warn.text = "樹海への立入注意\nSuicide Forest — Enter at your own risk"
	warn.position = Vector3(0.0, 0.0, 0.032)
	warn.pixel_size = 0.0026
	warn.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	warn.font_size = 14
	warn.modulate = Color(0.85, 0.78, 0.65)
	warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warn.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	board_mi.add_child(warn)

	add_child(sign_body)
