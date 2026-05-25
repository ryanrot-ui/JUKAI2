extends "res://scripts/world/LevelManager.gd"

# _WORLD_SPAWN is inherited from LevelManager.
const _CAR_BUILDER := preload("res://scripts/world/JapaneseCompactCarBuilder.gd")
const _LOT_PROPS := preload("res://scripts/world/ParkingLotProps.gd")

# Geometry constants — kept here so spawners can avoid colliding with
# structures (signs, gate, cars) without magic numbers scattered around.
const LOT_HALF_X        := 22.0
const LOT_NORTH_Z       :=  16.0    # asphalt north edge
const LOT_SOUTH_Z       := -16.0    # asphalt south edge (gate is here)
const PATH_HALF_WIDTH   :=  2.3
const PATH_LENGTH       :=  44.0
const PATH_CENTER_Z     := -16.0    # path runs from z=+6 down to z=-38
const GATE_Z            := -12.0
const SIGN_POS          := Vector3(5.6, 0.0, -6.5)
const EXIT_TRIGGER_Z    := -34.0

func _ready() -> void:
	level_ambient_key = "forest_night"
	next_level_path = "res://scenes/levels/ForestEntrance.tscn"

	_make_world_env(
		Color(0.02, 0.018, 0.032),
		Color(0.03, 0.026, 0.048),
		Color(0.04, 0.034, 0.058),
		0.012)
	_make_directional_light(Color(0.18, 0.16, 0.24), 0.12)

	# Base ground — solid 140 x 200 forest floor under EVERYTHING. The asphalt
	# and dirt path are visual overlays on top, so the player has a continuous
	# walkable surface at y=0 and can never fall off the parking lot edge.
	_make_floor(Vector3(140, 0.4, 200))

	# Asphalt overlay — visual only, very thin, sits on the ground floor
	_make_asphalt_overlay(Vector3(LOT_HALF_X * 2.0, 0.04, (LOT_NORTH_Z - LOT_SOUTH_Z)),
		Vector3(0.0, 0.02, (LOT_NORTH_Z + LOT_SOUTH_Z) * 0.5))

	# Worn decor confined to the actual asphalt rectangle, avoiding cars/path
	_LOT_PROPS.spawn_decor(self, 8801)

	# Dirt path overlay — visual only, sits 1 cm above asphalt to read clearly
	# but well below any step height so the player walks straight onto it.
	_make_dirt_path(Vector3(0.0, 0.03, PATH_CENTER_Z), PATH_LENGTH, PATH_HALF_WIDTH * 2.0)

	# Player's car — compact JDM sedan, facing the forest path
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

	# Lights — more of them, brighter, so the lot reads at night
	_spawn_lot_light(Vector3(-9, 0, 4))
	_spawn_lot_light(Vector3( 9, 0, 4))
	_spawn_lot_light(Vector3(-9, 0, -8))
	_spawn_lot_light(Vector3( 9, 0, -8))

	# Treeline — thicker around the lot to feel enclosed
	_WORLD_SPAWN.add_tree_spawner(self, Vector3(-24, 0, -10), {
		"count": 60, "area_size": Vector2(20, 60), "avoid_center_radius": 12.0,
		"min_scale": 1.2, "max_scale": 2.4, "random_seed": 501,
		"cluster_count": 6, "cluster_density": 0.78})
	_WORLD_SPAWN.add_tree_spawner(self, Vector3( 24, 0, -10), {
		"count": 60, "area_size": Vector2(20, 60), "avoid_center_radius": 12.0,
		"min_scale": 1.2, "max_scale": 2.4, "random_seed": 502,
		"cluster_count": 6, "cluster_density": 0.78})
	# Forest backdrop deeper south (behind exit) so the path leads INTO something
	_WORLD_SPAWN.add_tree_spawner(self, Vector3(0, 0, -55), {
		"count": 70, "area_size": Vector2(80, 30), "avoid_center_radius": 6.0,
		"avoid_path_width": 4.0,
		"min_scale": 1.0, "max_scale": 2.2, "random_seed": 503,
		"cluster_count": 7, "cluster_density": 0.70})

	# A few ribbons along the path edge — far enough from path to not block
	_WORLD_SPAWN.add_ribbon_spawner(self, Vector3(0, 0, -25), {
		"ribbon_count": 12, "area_size": Vector2(18, 22)})

	# Torii-style gate at the forest entrance
	_spawn_gate(Vector3(0, 0, GATE_Z))

	# Information sign — off to the side, clear of the path AND clear of cars
	_spawn_sign(SIGN_POS, -22.0)

	# Exit trigger past the gate, slightly elevated so brushing the ground
	# can't accidentally fire it
	_make_exit_trigger(Vector3(0, 1.5, EXIT_TRIGGER_Z), Vector3(8, 5, 2))

	_spawn_player(Vector3(-4, 1.0, 11.0))
	_spawn_hud()
	_start_common()
	call_deferred("_play_intro")

func _play_intro() -> void:
	await get_tree().create_timer(1.0).timeout
	NarrativeDirector.play_game_opening()

# Asphalt — visual only (collision is the forest floor underneath).
# Mesh top at y = center_y + size.y/2. Place so its TOP sits at y = 0.04.
func _make_asphalt_overlay(size: Vector3, center: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = center
	_LOT_PROPS.apply_wet_asphalt(mi)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

# Dirt path — visual overlay only, sits flush on the forest floor + asphalt.
# 4 cm thick mesh so it reads as worn dirt without a tripping step.
func _make_dirt_path(center: Vector3, length: float, width: float) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(width, 0.04, length)
	mi.mesh = bm
	mi.position = center
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.16, 0.10)
	mat.roughness = 0.98
	mat.metallic_specular = 0.02
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _spawn_lot_light(pos: Vector3) -> void:
	var pole := StaticBody3D.new()
	pole.position = pos

	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.38, 0.38, 0.40)
	pole_mat.roughness = 0.72

	var pole_m := CylinderMesh.new()
	pole_m.height = 6.0
	pole_m.top_radius = 0.038
	pole_m.bottom_radius = 0.065
	var pole_mi := MeshInstance3D.new()
	pole_mi.mesh = pole_m
	pole_mi.material_override = pole_mat
	pole_mi.position = Vector3(0, 3.0, 0)
	pole.add_child(pole_mi)

	var arm_m := BoxMesh.new()
	arm_m.size = Vector3(1.4, 0.07, 0.07)
	var arm_mi := MeshInstance3D.new()
	arm_mi.mesh = arm_m
	arm_mi.material_override = pole_mat
	arm_mi.position = Vector3(0.7, 6.0, 0)
	pole.add_child(arm_mi)

	var fixture_m := BoxMesh.new()
	fixture_m.size = Vector3(0.42, 0.10, 0.22)
	var fixture_mi := MeshInstance3D.new()
	fixture_mi.mesh = fixture_m
	var fix_mat := StandardMaterial3D.new()
	fix_mat.albedo_color = Color(0.96, 0.86, 0.55)
	fix_mat.emission_enabled = true
	fix_mat.emission = Color(0.95, 0.82, 0.45)
	fix_mat.emission_energy_multiplier = 0.95
	fixture_mi.material_override = fix_mat
	fixture_mi.position = Vector3(1.4, 6.0, 0)
	pole.add_child(fixture_mi)

	var light := OmniLight3D.new()
	light.light_color = Color(0.86, 0.78, 0.55)
	light.light_energy = 10.5
	light.omni_range = 28.0
	light.shadow_enabled = true
	light.position = Vector3(1.4, 5.95, 0)
	pole.add_child(light)

	var ps := CylinderShape3D.new()
	ps.height = 6.0
	ps.radius = 0.065
	var pc := CollisionShape3D.new()
	pc.shape = ps
	pc.position = Vector3(0, 3.0, 0)
	pole.add_child(pc)

	add_child(pole)

# Torii-style gate. Posts on each side, top beam, second beam, shimenawa rope,
# and shide (paper streamers) that actually HANG DOWN from the top beam.
func _spawn_gate(pos: Vector3) -> void:
	var gate := StaticBody3D.new()
	gate.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.09, 0.05)
	mat.roughness = 0.94

	# Vertical posts (4 m tall)
	for side: float in [-1.0, 1.0]:
		var pm := BoxMesh.new()
		pm.size = Vector3(0.24, 4.0, 0.24)
		var pi := MeshInstance3D.new()
		pi.mesh = pm; pi.material_override = mat
		pi.position = Vector3(side * 2.8, 2.0, 0)
		gate.add_child(pi)

	# Top beam — kasagi (slight outward overhang)
	var tb := BoxMesh.new()
	tb.size = Vector3(6.6, 0.26, 0.28)
	var tbi := MeshInstance3D.new()
	tbi.mesh = tb; tbi.material_override = mat
	tbi.position = Vector3(0, 4.0, 0)
	gate.add_child(tbi)

	# Second beam — shimaki, slightly below
	var lb := BoxMesh.new()
	lb.size = Vector3(5.6, 0.18, 0.20)
	var lbi := MeshInstance3D.new()
	lbi.mesh = lb; lbi.material_override = mat
	lbi.position = Vector3(0, 3.55, 0)
	gate.add_child(lbi)

	# Shimenawa — twisted rope spanning the gate
	var rope := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.height = 5.4
	rm.top_radius = 0.06
	rm.bottom_radius = 0.06
	rope.mesh = rm
	rope.rotation_degrees.z = 90.0
	rope.position = Vector3(0, 3.30, 0)
	var rope_mat := StandardMaterial3D.new()
	rope_mat.albedo_color = Color(0.78, 0.72, 0.55)
	rope_mat.roughness = 1.0
	rope.material_override = rope_mat
	gate.add_child(rope)

	# Shide — white paper streamers that ACTUALLY HANG DOWN from the rope.
	# Top of streamer at y=3.25 (just below rope), length 1.8 m so they
	# end at y=1.45 — clearly above head-height, framing the entrance.
	var shide_mat := StandardMaterial3D.new()
	shide_mat.albedo_color = Color(0.92, 0.90, 0.84)
	shide_mat.roughness = 0.95
	shide_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in 5:
		var sh_top := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.10, 1.80, 0.012)
		sh_top.mesh = sm
		sh_top.material_override = shide_mat
		sh_top.position = Vector3(-2.0 + i * 1.0, 2.35, 0)
		gate.add_child(sh_top)

	# Collision — only the posts. Walking under the gate must NOT be blocked.
	for side: float in [-1.0, 1.0]:
		var ps := BoxShape3D.new()
		ps.size = Vector3(0.24, 4.0, 0.24)
		var pc := CollisionShape3D.new()
		pc.shape = ps
		pc.position = Vector3(side * 2.8, 2.0, 0)
		gate.add_child(pc)

	add_child(gate)

# Sign — wooden post with a board, set perpendicular to the path so the
# label faces the player walking south. `yaw_deg` rotates the whole sign.
func _spawn_sign(pos: Vector3, yaw_deg: float = 0.0) -> void:
	var sign_body := StaticBody3D.new()
	sign_body.position = pos
	sign_body.rotation_degrees.y = yaw_deg

	var post_m := CylinderMesh.new()
	post_m.height = 2.2; post_m.top_radius = 0.05; post_m.bottom_radius = 0.06
	var post_mi := MeshInstance3D.new()
	post_mi.mesh = post_m
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.22, 0.16, 0.10)
	post_mat.roughness = 0.95
	post_mi.material_override = post_mat
	post_mi.position = Vector3(0, 1.1, 0)
	sign_body.add_child(post_mi)

	var board_m := BoxMesh.new()
	board_m.size = Vector3(1.30, 0.70, 0.05)
	var board_mi := MeshInstance3D.new()
	board_mi.mesh = board_m
	var board_mat := StandardMaterial3D.new()
	board_mat.albedo_color = Color(0.55, 0.42, 0.22)
	board_mat.roughness = 0.92
	board_mi.material_override = board_mat
	board_mi.position = Vector3(0, 2.15, 0)
	sign_body.add_child(board_mi)

	var warn := Label3D.new()
	warn.text = "樹海への立入注意\nSuicide Forest — Enter at your own risk"
	# Slight forward offset so the text reads ON the board face, not inside it
	warn.position = Vector3(0.0, 0.0, 0.030)
	warn.pixel_size = 0.0028
	warn.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	warn.font_size = 14
	warn.modulate = Color(0.88, 0.80, 0.62)
	warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warn.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	board_mi.add_child(warn)

	# Thin post collision — just enough to not be walked through
	var pcs := CylinderShape3D.new()
	pcs.radius = 0.07; pcs.height = 2.2
	var pcoll := CollisionShape3D.new()
	pcoll.shape = pcs
	pcoll.position = Vector3(0, 1.1, 0)
	sign_body.add_child(pcoll)

	add_child(sign_body)
