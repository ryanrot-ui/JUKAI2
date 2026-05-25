extends "res://scripts/world/LevelManager.gd"

const _WORLD_SPAWN := preload("res://scripts/world/WorldSpawnUtil.gd")
const _CAR_BUILDER := preload("res://scripts/world/JapaneseCompactCarBuilder.gd")
const _LOT_PROPS := preload("res://scripts/world/ParkingLotProps.gd")
const _GHOST_DIRECTOR := preload("res://scripts/world/GhostSpawnDirector.gd")

const YUREI_SCENE  = preload("res://scenes/entities/YureiEntity.tscn")
const NOTE_SCENE   = preload("res://scenes/interactables/CollectibleNote.tscn")
const SHRINE_SCENE = preload("res://scenes/interactables/Shrine.tscn")

func _ready() -> void:
	level_ambient_key = "forest_night"
	next_level_path   = "res://scenes/levels/DenseTreeSea.tscn"

	_make_world_env(
		Color(0.012, 0.010, 0.022),
		Color(0.028, 0.022, 0.048),
		Color(0.042, 0.034, 0.068),
		0.022)
	_make_directional_light(Color(0.14, 0.12, 0.20), 0.07)

	# Full terrain base (forest floor shader handles everything beneath)
	_make_floor(Vector3(200, 0.4, 200))

	# ── Parking lot (concrete overlay, Z = -6 to +22) ─────────────────────────
	_build_parking_lot()

	# ── Guided trail — lanterns + emissive path (semi-linear, not a corridor) ─
	_add_guided_trail(Vector3(0, 0.03, -40), 68, 2.6, 4242)

	_WORLD_SPAWN.add_tree_spawner(self, Vector3(0, 0, -55), {
		"count": 165, "area_size": Vector2(120, 80), "min_scale": 1.0, "max_scale": 2.4,
		"avoid_center_radius": 5.0, "avoid_path_width": 3.4, "random_seed": 101,
		"cluster_count": 14, "cluster_radius": 10.0, "cluster_density": 0.78})
	_WORLD_SPAWN.add_tree_spawner(self, Vector3(0, 0, -58), {
		"count": 55, "spawn_collision": false, "area_size": Vector2(130, 90),
		"min_scale": 0.8, "max_scale": 1.6, "avoid_center_radius": 8.0,
		"avoid_path_width": 5.5, "random_seed": 199, "cluster_count": 6, "cluster_density": 0.55})
	_WORLD_SPAWN.add_grass_spawner(self, Vector3(0, 0, -50), {
		"count": 130, "area_size": Vector2(120, 80), "avoid_path_width": 2.0, "random_seed": 801})
	_WORLD_SPAWN.add_ribbon_spawner(self, Vector3(0, 0, -55), {
		"ribbon_count": 22, "area_size": Vector2(100, 80)})
	_spawn_landmarks(6, Vector2(100, 80), 111)
	_WORLD_SPAWN.add_rock_spawner(self, Vector3(0, 0, -50), {
		"count": 26, "area_size": Vector2(110, 80), "avoid_center_radius": 5.5,
		"avoid_path_width": 3.0, "random_seed": 991})

	var shrine = SHRINE_SCENE.instantiate()
	shrine.position = Vector3(5.5, 0, -26)
	shrine.shrine_id = 0
	add_child(shrine)

	var note0 = NOTE_SCENE.instantiate()
	note0.note_id = 0; note0.trigger_ghost_on_pickup = false
	note0.position = Vector3(-5.5, 0.1, -34)
	add_child(note0)

	var yurei_edge = YUREI_SCENE.instantiate()
	yurei_edge.name = "Yurei_Edge"
	yurei_edge.ghost_id = 1
	yurei_edge.position = Vector3(0, 0, -30)
	add_child(yurei_edge)

	var yurei_behind = YUREI_SCENE.instantiate()
	yurei_behind.name = "Yurei_Behind"
	yurei_behind.ghost_id = 2
	yurei_behind.position = Vector3(0, 0, -80)
	add_child(yurei_behind)

	var director = Node.new()
	director.name = "GhostSpawnDirector"
	director.set_script(_GHOST_DIRECTOR)
	director.scare_1_ghost_path = NodePath("../Yurei_Edge")
	director.scare_1_delay      = 90.0
	director.scare_2_ghost_path = NodePath("../Yurei_Behind")
	director.scare_2_note_id    = 0
	add_child(director)

	_make_clearing_area(Vector3(0, 2, -10), Vector3(28, 4, 16))
	_make_exit_trigger(Vector3(0, 1.5, -72), Vector3(10, 4, 2))

	# Blue shimmer near the note (just off the right-side trail edge)
	var shimmer0 = OmniLight3D.new()
	shimmer0.position = Vector3(-5.5, 2.8, -34)
	shimmer0.light_color  = Color(0.72, 0.84, 1.0)
	shimmer0.light_energy = 0.14
	shimmer0.omni_range   = 11.0
	shimmer0.shadow_enabled = false
	add_child(shimmer0)

	# Player spawns in the parking lot, facing the forest
	_spawn_player(Vector3(0, 1, 10))
	_spawn_hud()
	_start_common()
	_spawn_stalker(Vector3(0, 0, -500), 65.0)

# ── Parking lot construction ──────────────────────────────────────────────────

func _build_parking_lot() -> void:
	# Main concrete slab (visual only — forest floor StaticBody handles collision)
	var slab = MeshInstance3D.new()
	var slab_mesh = BoxMesh.new()
	slab_mesh.size = Vector3(52.0, 0.04, 32.0)
	slab.mesh = slab_mesh
	slab.position = Vector3(0, 0.02, 5.0)
	_LOT_PROPS.apply_wet_asphalt(slab)
	add_child(slab)
	_LOT_PROPS.spawn_decor(self, 8802)

	# Kerb / raised edge at forest boundary
	var kerb_mat = StandardMaterial3D.new()
	kerb_mat.albedo_color = Color(0.60, 0.58, 0.55)
	kerb_mat.roughness = 0.88
	var kerb = MeshInstance3D.new()
	var kerb_mesh = BoxMesh.new()
	kerb_mesh.size = Vector3(52.0, 0.14, 0.28)
	kerb.mesh = kerb_mesh
	kerb.position = Vector3(0, 0.07, -10.8)
	kerb.material_override = kerb_mat
	add_child(kerb)

	# Parking lines
	var line_mat = StandardMaterial3D.new()
	line_mat.albedo_color = Color(0.70, 0.68, 0.62)
	line_mat.roughness = 0.84

	# Left bay lines (separating spaces along Z)
	for i in 5:
		var z = -2.0 + float(i) * 5.2
		_stripe(Vector3(-10.5, 0.03, z), Vector3(9.0, 0.03, 0.14), line_mat)

	# Right bay lines
	for i in 5:
		var z = -2.0 + float(i) * 5.2
		_stripe(Vector3(10.5, 0.03, z), Vector3(9.0, 0.03, 0.14), line_mat)

	# Centre aisle dashed line
	for i in 5:
		var z = -3.0 + float(i) * 4.0
		_stripe(Vector3(0, 0.03, z), Vector3(0.14, 0.03, 2.5), line_mat)

	# ── Parked compacts (realistic proportions, wet paint) ───────────────────
	_CAR_BUILDER.build(self, Vector3(-12.4, 0, 1.0), Color(0.10, 0.12, 0.18), 90.0, {"dirt": 0.32})
	_CAR_BUILDER.build(self, Vector3(-12.4, 0, 11.2), Color(0.15, 0.06, 0.05), 88.0, {"abandoned": true, "dirt": 0.48})
	_CAR_BUILDER.build(self, Vector3(12.4, 0, -0.8), Color(0.06, 0.06, 0.08), -90.0, {"dirt": 0.35})
	_CAR_BUILDER.build(self, Vector3(12.4, 0, 12.8), Color(0.14, 0.18, 0.12), -92.0, {"abandoned": true, "rust": 0.15})

func _stripe(pos: Vector3, size: Vector3, mat: StandardMaterial3D) -> void:
	var mi = MeshInstance3D.new()
	var bm = BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	add_child(mi)
