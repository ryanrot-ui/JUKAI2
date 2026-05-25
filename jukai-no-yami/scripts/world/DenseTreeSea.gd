extends "res://scripts/world/LevelManager.gd"

# _WORLD_SPAWN is inherited from LevelManager.
const _GHOST_DIRECTOR := preload("res://scripts/world/GhostSpawnDirector.gd")

const YUREI_SCENE  = preload("res://scenes/entities/YureiEntity.tscn")
const ONRYO_SCENE  = preload("res://scenes/entities/OnryoEntity.tscn")
const HANG_SCENE   = preload("res://scenes/entities/HangingSpirit.tscn")
const NOTE_SCENE   = preload("res://scenes/interactables/CollectibleNote.tscn")
const SHRINE_SCENE = preload("res://scenes/interactables/Shrine.tscn")

func _ready() -> void:
	level_ambient_key = "deep_forest"
	next_level_path   = "res://scenes/levels/RibbonPathCave.tscn"

	_make_world_env(
		Color(0.010, 0.008, 0.018),
		Color(0.022, 0.016, 0.038),
		Color(0.034, 0.024, 0.055),
		0.022)
	_make_directional_light(Color(0.18, 0.16, 0.24), 0.10)

	_make_floor(Vector3(200, 0.4, 200))
	_add_guided_trail(Vector3(0, 0.03, -38), 100, 2.5, 7773322)

	_WORLD_SPAWN.add_tree_spawner(self, Vector3.ZERO, {
		"count": 195, "area_size": Vector2(170, 170), "min_scale": 1.2, "max_scale": 2.6,
		"avoid_center_radius": 4.8, "avoid_path_width": 3.2, "random_seed": 202,
		"cluster_count": 16, "cluster_radius": 11.0, "cluster_density": 0.82})
	_WORLD_SPAWN.add_tree_spawner(self, Vector3.ZERO, {
		"count": 50, "spawn_collision": false, "area_size": Vector2(190, 190),
		"min_scale": 0.6, "max_scale": 1.5, "avoid_center_radius": 12.0,
		"avoid_path_width": 8.0, "random_seed": 299, "cluster_density": 0.50})
	_WORLD_SPAWN.add_grass_spawner(self, Vector3.ZERO, {
		"count": 150, "area_size": Vector2(160, 160), "avoid_path_width": 2.2, "random_seed": 802})
	_WORLD_SPAWN.add_ribbon_spawner(self, Vector3.ZERO, {
		"ribbon_count": 38, "area_size": Vector2(130, 130)})
	_spawn_landmarks(8, Vector2(140, 140), 222)
	_WORLD_SPAWN.add_rock_spawner(self, Vector3.ZERO, {
		"count": 32, "area_size": Vector2(160, 160), "avoid_center_radius": 4.8,
		"avoid_path_width": 3.8, "random_seed": 992})

	# Fewer dapple lights — this zone should feel oppressive
	var shrine = SHRINE_SCENE.instantiate()
	shrine.position = Vector3(-6.0, 0, -28)
	shrine.shrine_id = 1
	add_child(shrine)

	var note1 = NOTE_SCENE.instantiate()
	note1.note_id = 1; note1.trigger_ghost_on_pickup = false
	note1.position = Vector3(5.5, 0.1, -18)
	add_child(note1)

	var note2 = NOTE_SCENE.instantiate()
	note2.note_id = 2; note2.trigger_ghost_on_pickup = false
	note2.position = Vector3(-5.5, 0.1, -52)
	add_child(note2)

	var onryo_flicker = ONRYO_SCENE.instantiate()
	onryo_flicker.name = "Onryo_Flicker"
	onryo_flicker.ghost_id = 10; onryo_flicker.spawn_on_sanity = false
	onryo_flicker.position = Vector3(9, 0, -24)
	add_child(onryo_flicker)

	var hang_scare4 = HANG_SCENE.instantiate()
	hang_scare4.name = "HangingSpirit_Scare4"
	hang_scare4.hang_height = 6.0
	hang_scare4.position = Vector3(-5.5, 0, -52)
	add_child(hang_scare4)

	var yurei_ambient = YUREI_SCENE.instantiate()
	yurei_ambient.name = "Yurei_Ambient"
	yurei_ambient.ghost_id = 3
	yurei_ambient.position = Vector3(34, 0, -20)
	add_child(yurei_ambient)

	var onryo_sanity = ONRYO_SCENE.instantiate()
	onryo_sanity.name = "Onryo_Sanity"
	onryo_sanity.ghost_id = 11; onryo_sanity.spawn_on_sanity = true
	onryo_sanity.position = Vector3(-9, 0, -26)
	add_child(onryo_sanity)

	var director = Node.new()
	director.name = "GhostSpawnDirector"
	director.set_script(_GHOST_DIRECTOR)
	director.scare_3_onryo_path = NodePath("../Onryo_Flicker")
	director.scare_3_delay      = 62.0
	director.scare_4_hang_path  = NodePath("../HangingSpirit_Scare4")
	director.scare_4_note_id    = 2
	add_child(director)

	_make_clearing_area(Vector3(5.5, 2, -18), Vector3(14, 4, 14))
	_make_exit_trigger(Vector3(0, 1.5, -82), Vector3(10, 4, 2))

	# Path corridor markers — sparser spacing in the denser level feels more oppressive
	var shimmer1 = OmniLight3D.new()
	shimmer1.position = Vector3(5.5, 2.8, -18)
	shimmer1.light_color  = Color(0.70, 0.80, 1.0)
	shimmer1.light_energy = 0.14
	shimmer1.omni_range   = 12.0
	shimmer1.shadow_enabled = false
	add_child(shimmer1)

	var shimmer2 = OmniLight3D.new()
	shimmer2.position = Vector3(-5.5, 2.8, -52)
	shimmer2.light_color  = Color(0.70, 0.80, 1.0)
	shimmer2.light_energy = 0.14
	shimmer2.omni_range   = 12.0
	shimmer2.shadow_enabled = false
	add_child(shimmer2)

	_spawn_player(Vector3(0, 1, 5))
	_spawn_hud()
	_start_common()
	_spawn_stalker(Vector3(0, 0, 500), 55.0)  # more aggressive in second level
