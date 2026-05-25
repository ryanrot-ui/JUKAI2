extends StaticBody3D

const SHRINE_RADIUS   = 5.0
const BATTERY_RESTORE = 80.0
const SANITY_RESTORE  = 25.0

@export var shrine_id: int   = 0
@export var already_used: bool = false

var _light: OmniLight3D
var _prompt: Label3D
var _area: Area3D
var _player_in_range: bool = false

func _ready() -> void:
	add_to_group("interactable")
	add_to_group("shrine")
	collision_layer = 4

	_build_shrine_mesh()

	var box = BoxShape3D.new()
	box.size = Vector3(1.2, 1.6, 0.8)
	var col = CollisionShape3D.new()
	col.shape = box
	col.position = Vector3(0, 0.8, 0)
	add_child(col)

	_light = OmniLight3D.new()
	_light.position = Vector3(0, 1.5, 0)
	_light.omni_range = 6.0
	add_child(_light)

	_prompt = Label3D.new()
	_prompt.position = Vector3(0, 2.6, 0)
	_prompt.pixel_size = 0.004
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.text = "[E] 祈る — Pray (restore calm)"
	_prompt.font_size = 22
	_prompt.modulate = Color(0.95, 0.88, 0.65)
	_prompt.visible = false
	add_child(_prompt)

	var sphere = SphereShape3D.new()
	sphere.radius = 4.0
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 1
	var area_col = CollisionShape3D.new()
	area_col.shape = sphere
	_area.add_child(area_col)
	add_child(_area)
	_area.body_entered.connect(_on_body_entered)
	_area.body_exited.connect(_on_body_exited)

	_update_light()

func _build_shrine_mesh() -> void:
	var wood = StandardMaterial3D.new()
	wood.albedo_color = Color(0.14, 0.09, 0.05)
	wood.roughness = 0.94

	# Torii posts
	for side in [-1, 1]:
		var post = MeshInstance3D.new()
		var pm = CylinderMesh.new()
		pm.height = 2.4
		pm.top_radius = 0.07
		pm.bottom_radius = 0.09
		post.mesh = pm
		post.material_override = wood
		post.position = Vector3(side * 0.55, 1.2, 0)
		add_child(post)

	var beam = MeshInstance3D.new()
	var bm = BoxMesh.new()
	bm.size = Vector3(1.35, 0.1, 0.1)
	beam.mesh = bm
	beam.material_override = wood
	beam.position = Vector3(0, 2.35, 0)
	add_child(beam)

	var altar = MeshInstance3D.new()
	var am = BoxMesh.new()
	am.size = Vector3(0.5, 0.35, 0.4)
	altar.mesh = am
	altar.material_override = wood
	altar.position = Vector3(0, 0.18, 0)
	add_child(altar)

	# Sacred rope
	var rope = MeshInstance3D.new()
	var rm = CylinderMesh.new()
	rm.height = 0.04
	rm.top_radius = 0.55
	rm.bottom_radius = 0.55
	rope.mesh = rm
	var rope_mat = StandardMaterial3D.new()
	rope_mat.albedo_color = Color(0.75, 0.12, 0.10)
	rope_mat.emission_enabled = true
	rope_mat.emission = Color(0.9, 0.15, 0.1)
	rope_mat.emission_energy_multiplier = 0.2
	rope.material_override = rope_mat
	rope.position = Vector3(0, 1.85, 0)
	rope.rotation_degrees.x = 90.0
	add_child(rope)

func _update_light() -> void:
	if already_used:
		_light.light_energy = 0.3
		_light.light_color = Color(0.4, 0.4, 0.5)
	else:
		_light.light_energy = 1.4
		_light.light_color = Color(0.9, 0.85, 0.6)

func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	_player_in_range = true
	if not already_used:
		_prompt.visible = true
	_repel_nearby_onryo()

func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		_prompt.visible = false
		if GameManager.sanity_ref:
			GameManager.sanity_ref.is_near_shrine = false

func interact(_player: CharacterBody3D) -> void:
	if already_used:
		return
	already_used = true
	_prompt.visible = false
	var flashlight = GameManager.player_ref.get_node_or_null("Camera3D/HandPivot/Flashlight") if GameManager.player_ref else null
	if flashlight and flashlight.has_method("recharge"):
		flashlight.recharge(BATTERY_RESTORE)
	if GameManager.sanity_ref:
		GameManager.sanity_ref.restore(SANITY_RESTORE)
		GameManager.sanity_ref.is_near_shrine = false
	_update_light()
	AudioManager.play_sfx("shrine_charge")
	_repel_nearby_onryo()
	if GameManager.ui_ref and GameManager.ui_ref.has_method("show_subtitle"):
		GameManager.ui_ref.show_subtitle(
			"神はまだここにいる… / The shrine still holds power. I can breathe again.", 3.5)

func _repel_nearby_onryo() -> void:
	for o in get_tree().get_nodes_in_group("onryo"):
		if o.global_position.distance_to(global_position) < SHRINE_RADIUS * 2.0:
			if o.has_method("repel"):
				o.repel()

func _process(_delta: float) -> void:
	if _player_in_range and not already_used and GameManager.sanity_ref:
		GameManager.sanity_ref.is_near_shrine = true
	if not already_used:
		var pulse = (sin(Time.get_ticks_msec() * 0.0022) + 1.0) * 0.5
		_light.light_energy = lerpf(1.0, 1.9, pulse)
