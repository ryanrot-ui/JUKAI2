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

	# Collision wraps the stone base + cabinet (matches the new hokora shape).
	var box = BoxShape3D.new()
	box.size = Vector3(1.40, 1.40, 1.10)
	var col = CollisionShape3D.new()
	col.shape = box
	col.position = Vector3(0, 0.70, 0)
	add_child(col)

	_light = OmniLight3D.new()
	_light.position = Vector3(0, 1.10, 0)
	_light.omni_range = 5.5
	add_child(_light)

	_prompt = Label3D.new()
	_prompt.position = Vector3(0, 1.90, 0)
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
	# ── Hokora (祠) — traditional tiny Japanese roadside shrine ──────────
	# Layered construction: stone base → wooden shrine cabinet with sloped
	# roof → mini torii in front → offerings (stones, sake bottle) → shimenawa
	# rope with shide paper streamers at the torii.

	var stone_mat := StandardMaterial3D.new()
	stone_mat.albedo_color = Color(0.42, 0.42, 0.38)
	stone_mat.roughness = 0.95
	stone_mat.metallic = 0.0
	stone_mat.metallic_specular = 0.05

	var dark_stone_mat := StandardMaterial3D.new()
	dark_stone_mat.albedo_color = Color(0.32, 0.32, 0.30)
	dark_stone_mat.roughness = 0.97

	var moss_stone_mat := StandardMaterial3D.new()
	moss_stone_mat.albedo_color = Color(0.30, 0.34, 0.24)
	moss_stone_mat.roughness = 0.95

	var wood_dark := StandardMaterial3D.new()
	wood_dark.albedo_color = Color(0.18, 0.10, 0.06)
	wood_dark.roughness = 0.92

	var wood_red := StandardMaterial3D.new()
	wood_red.albedo_color = Color(0.42, 0.10, 0.08)
	wood_red.roughness = 0.85
	wood_red.metallic_specular = 0.20

	var tile_mat := StandardMaterial3D.new()
	tile_mat.albedo_color = Color(0.16, 0.16, 0.18)
	tile_mat.roughness = 0.62
	tile_mat.metallic = 0.10
	tile_mat.metallic_specular = 0.45

	var gold_mat := StandardMaterial3D.new()
	gold_mat.albedo_color = Color(0.85, 0.70, 0.32)
	gold_mat.metallic = 0.78
	gold_mat.roughness = 0.32
	gold_mat.emission_enabled = true
	gold_mat.emission = Color(0.95, 0.78, 0.42)
	gold_mat.emission_energy_multiplier = 0.18

	var shide_mat := StandardMaterial3D.new()
	shide_mat.albedo_color = Color(0.94, 0.92, 0.86)
	shide_mat.roughness = 0.95
	shide_mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	# ── Stone base (3 layers — flat slab on the ground, then a stepped plinth)
	_add_block(Vector3(1.40, 0.10, 1.10), Vector3(0, 0.05, 0), moss_stone_mat)
	_add_block(Vector3(1.10, 0.20, 0.90), Vector3(0, 0.20, 0), stone_mat)
	_add_block(Vector3(0.85, 0.16, 0.70), Vector3(0, 0.38, 0), dark_stone_mat)

	# ── Wooden shrine cabinet (honden) on top of the plinth
	var cabinet_y := 0.46
	# Cabinet walls (back + 2 sides). Front is left open for the offering.
	_add_block(Vector3(0.72, 0.62, 0.08), Vector3(0,    cabinet_y + 0.31, -0.30), wood_dark)  # back wall
	_add_block(Vector3(0.08, 0.62, 0.60), Vector3(-0.32, cabinet_y + 0.31,  0.00), wood_dark)  # left wall
	_add_block(Vector3(0.08, 0.62, 0.60), Vector3( 0.32, cabinet_y + 0.31,  0.00), wood_dark)  # right wall
	# Floor of cabinet (dark wood)
	_add_block(Vector3(0.72, 0.05, 0.60), Vector3(0, cabinet_y + 0.025, 0), wood_red)
	# Small gold offering tablet inside the cabinet
	_add_block(Vector3(0.18, 0.22, 0.04), Vector3(0, cabinet_y + 0.15, -0.20), gold_mat)

	# ── Pitched roof: two angled boards meeting at the ridge ────────────────
	# Left slope
	_add_block(Vector3(0.46, 0.06, 0.78), Vector3(-0.20, cabinet_y + 0.78, 0), tile_mat, Vector3(0, 0, -28.0))
	# Right slope
	_add_block(Vector3(0.46, 0.06, 0.78), Vector3( 0.20, cabinet_y + 0.78, 0), tile_mat, Vector3(0, 0, 28.0))
	# Ridge piece (katsuogi-like)
	_add_block(Vector3(0.06, 0.10, 0.84), Vector3(0, cabinet_y + 0.92, 0), wood_dark)
	# Roof gable end (front triangle filler — small box for now)
	_add_block(Vector3(0.74, 0.18, 0.06), Vector3(0, cabinet_y + 0.78, 0.40), wood_dark)

	# ── Mini torii in front of the shrine (entrance gate, ~1 m tall) ────────
	var torii_z := 0.62
	# Two vertical posts
	_add_cylinder(0.05, 1.05, Vector3(-0.42, 0.52, torii_z), wood_red)
	_add_cylinder(0.05, 1.05, Vector3( 0.42, 0.52, torii_z), wood_red)
	# Top beam (kasagi) — slight overhang to either side
	_add_block(Vector3(1.05, 0.07, 0.10), Vector3(0, 1.04, torii_z), wood_red)
	# Second beam (nuki) just below
	_add_block(Vector3(0.92, 0.05, 0.07), Vector3(0, 0.92, torii_z), wood_red)
	# Shimenawa — thick twisted rope spanning between the two posts
	var shimenawa := MeshInstance3D.new()
	var srm := CylinderMesh.new()
	srm.height = 0.94
	srm.top_radius = 0.035
	srm.bottom_radius = 0.035
	shimenawa.mesh = srm
	shimenawa.material_override = _make_rope_mat()
	shimenawa.rotation_degrees.z = 90.0
	shimenawa.position = Vector3(0, 0.84, torii_z)
	add_child(shimenawa)
	# Shide — paper streamers that hang DOWN from the shimenawa
	for i in 4:
		var sh := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.05, 0.30, 0.008)
		sh.mesh = sm
		sh.material_override = shide_mat
		sh.position = Vector3(-0.32 + i * 0.22, 0.68, torii_z + 0.01)
		add_child(sh)

	# ── Offerings on the plinth in front of the cabinet ─────────────────────
	# Small rounded stones (river pebbles)
	for i in 3:
		var pebble := MeshInstance3D.new()
		var pm := SphereMesh.new()
		pm.radius = 0.045 + float(i) * 0.012
		pm.height = pm.radius * 2.0
		pebble.mesh = pm
		pebble.material_override = dark_stone_mat
		pebble.position = Vector3(-0.18 + i * 0.18, 0.50, 0.28)
		add_child(pebble)
	# Sake bottle (small white cylinder)
	var bottle := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.height = 0.18; bm.top_radius = 0.04; bm.bottom_radius = 0.055
	bottle.mesh = bm
	var bottle_mat := StandardMaterial3D.new()
	bottle_mat.albedo_color = Color(0.88, 0.85, 0.78)
	bottle_mat.roughness = 0.32
	bottle_mat.metallic = 0.05
	bottle.material_override = bottle_mat
	bottle.position = Vector3(0.25, 0.55, 0.20)
	add_child(bottle)

	# ── Small soft glow inside the cabinet (sacred presence) ────────────────
	var inner_light := OmniLight3D.new()
	inner_light.position = Vector3(0, cabinet_y + 0.25, -0.10)
	inner_light.light_color = Color(0.96, 0.82, 0.48)
	inner_light.light_energy = 0.55
	inner_light.omni_range = 1.6
	inner_light.shadow_enabled = false
	add_child(inner_light)


# Helper — add a box with optional rotation, parented to the shrine.
func _add_block(size: Vector3, pos: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.material_override = mat
	add_child(mi)


# Helper — add a cylinder (vertical by default).
func _add_cylinder(radius: float, height: float, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = height
	cm.radial_segments = 14
	mi.mesh = cm
	mi.position = pos
	mi.material_override = mat
	add_child(mi)


# Thick twisted-rope material for the shimenawa.
func _make_rope_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.82, 0.74, 0.55)
	m.roughness = 0.96
	m.metallic = 0.0
	return m

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
