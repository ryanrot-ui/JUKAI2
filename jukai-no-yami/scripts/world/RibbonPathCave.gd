extends "res://scripts/world/LevelManager.gd"

# _WORLD_SPAWN is inherited from LevelManager.
const _GHOST_DIRECTOR := preload("res://scripts/world/GhostSpawnDirector.gd")

const YUREI_SCENE = preload("res://scenes/entities/YureiEntity.tscn")
const ONRYO_SCENE = preload("res://scenes/entities/OnryoEntity.tscn")
const HANG_SCENE  = preload("res://scenes/entities/HangingSpirit.tscn")
const NOTE_SCENE  = preload("res://scenes/interactables/CollectibleNote.tscn")

var _exit_hint_shown: bool = false

func _ready() -> void:
	level_ambient_key = "cave_wind"
	is_final_level    = true

	_make_world_env(
		Color(0.008, 0.006, 0.016),
		Color(0.018, 0.014, 0.032),
		Color(0.028, 0.020, 0.048),
		0.032)
	_make_directional_light(Color(0.10, 0.08, 0.16), 0.05)

	_make_floor(Vector3(120, 0.4, 240))
	_add_guided_trail(Vector3(0, 0.03, -50), 120, 2.4, 3334444)

	_WORLD_SPAWN.add_tree_spawner(self, Vector3.ZERO, {
		"count": 155, "area_size": Vector2(100, 210), "min_scale": 1.0, "max_scale": 2.4,
		"avoid_center_radius": 5.0, "avoid_path_width": 3.0, "random_seed": 303,
		"cluster_count": 18, "cluster_radius": 9.0, "cluster_density": 0.85})
	_WORLD_SPAWN.add_tree_spawner(self, Vector3.ZERO, {
		"count": 45, "spawn_collision": false, "area_size": Vector2(115, 230),
		"min_scale": 0.6, "max_scale": 1.4, "avoid_center_radius": 10.0,
		"avoid_path_width": 7.0, "random_seed": 377, "cluster_density": 0.55})
	_WORLD_SPAWN.add_grass_spawner(self, Vector3.ZERO, {
		"count": 110, "area_size": Vector2(100, 210), "avoid_path_width": 2.0, "random_seed": 803})
	_WORLD_SPAWN.add_ribbon_spawner(self, Vector3.ZERO, {
		"ribbon_count": 42, "area_size": Vector2(65, 170)})
	_spawn_landmarks(5, Vector2(75, 185), 333)
	_WORLD_SPAWN.add_rock_spawner(self, Vector3.ZERO, {
		"count": 42, "area_size": Vector2(95, 195), "avoid_center_radius": 5.0,
		"avoid_path_width": 3.0, "random_seed": 993})

	# Very sparse dapple — final level should feel suffocating and lightless
	var note3 = NOTE_SCENE.instantiate()
	note3.note_id = 3; note3.trigger_ghost_on_pickup = false
	note3.position = Vector3(5.5, 0.1, -42)
	add_child(note3)

	var yurei_final = YUREI_SCENE.instantiate()
	yurei_final.name = "Yurei_Final"
	yurei_final.ghost_id = 5
	yurei_final.position = Vector3(0, 0, 500)
	add_child(yurei_final)

	var hang_a = HANG_SCENE.instantiate()
	hang_a.name = "HangingSpirit_A"
	hang_a.hang_height = 5.0
	hang_a.position = Vector3(-7, 0, -22)
	add_child(hang_a)

	var hang_b = HANG_SCENE.instantiate()
	hang_b.name = "HangingSpirit_B"
	hang_b.hang_height = 5.5
	hang_b.position = Vector3(5, 0, -58)
	add_child(hang_b)

	var onryo_cave = ONRYO_SCENE.instantiate()
	onryo_cave.name = "Onryo_Cave"
	onryo_cave.ghost_id = 12; onryo_cave.spawn_on_sanity = true
	onryo_cave.position = Vector3(-4, 0, -85)
	add_child(onryo_cave)

	# Warm beacon light ahead of exit so player has something to walk toward
	var exit_light = OmniLight3D.new()
	exit_light.position = Vector3(0, 2.5, -116)
	exit_light.light_color = Color(0.90, 0.84, 0.60)
	exit_light.light_energy = 3.4
	exit_light.omni_range = 18.0
	add_child(exit_light)

	var exit_fill = OmniLight3D.new()
	exit_fill.position = Vector3(0, 1.2, -110)
	exit_fill.light_color = Color(0.85, 0.78, 0.55)
	exit_fill.light_energy = 1.6
	exit_fill.omni_range = 10.0
	add_child(exit_fill)

	var director = Node.new()
	director.name = "GhostSpawnDirector"
	director.set_script(_GHOST_DIRECTOR)
	director.scare_5_yurei_path = NodePath("../Yurei_Final")
	director.scare_5_note_id = 3
	add_child(director)

	var exit_hint = Area3D.new()
	exit_hint.position = Vector3(0, 1.5, -95)
	exit_hint.collision_layer = 0
	exit_hint.collision_mask = 1
	var hint_shape = BoxShape3D.new()
	hint_shape.size = Vector3(14, 6, 8)
	var hint_col = CollisionShape3D.new()
	hint_col.shape = hint_shape
	exit_hint.add_child(hint_col)
	exit_hint.body_entered.connect(_on_exit_hint_entered)
	add_child(exit_hint)

	_make_exit_trigger(Vector3(0, 1.5, -112), Vector3(12, 5, 2))

	_spawn_player(Vector3(0, 1, 5))
	_spawn_hud()
	_start_common()
	_spawn_stalker(Vector3(0, 0, 500), 45.0)  # final level — most aggressive

func _on_exit_hint_entered(body: Node3D) -> void:
	if body.is_in_group("player") and not _exit_hint_shown:
		_exit_hint_shown = true
		NarrativeDirector.play_exit_approach()
