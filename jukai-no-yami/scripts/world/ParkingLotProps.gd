extends RefCounted
## Wet asphalt accents, puddles, leaves, debris — parking lot horror dressing.

const _ASPHALT_SHADER := preload("res://shaders/asphalt_wet.gdshader")

static func apply_wet_asphalt(mesh_inst: MeshInstance3D) -> void:
	var m := ShaderMaterial.new()
	m.shader = _ASPHALT_SHADER
	m.set_shader_parameter("asphalt_color", Color(0.10, 0.10, 0.11, 1.0))
	m.set_shader_parameter("wet_patches", 0.75)
	mesh_inst.material_override = m


static func spawn_decor(parent: Node3D, rng_seed: int = 8801) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed

	for i in 8:
		_spawn_puddle(parent, rng, Vector3(
			rng.randf_range(-14.0, 14.0),
			0.012,
			rng.randf_range(-10.0, 14.0)))

	for i in 22:
		_spawn_leaf(parent, rng, Vector3(
			rng.randf_range(-16.0, 16.0),
			0.018,
			rng.randf_range(-12.0, 15.0)))

	for i in 6:
		_spawn_debris(parent, rng, Vector3(
			rng.randf_range(-12.0, 12.0),
			0.02,
			rng.randf_range(-8.0, 12.0)))


static func _spawn_puddle(parent: Node3D, rng: RandomNumberGenerator, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	var r := rng.randf_range(0.35, 1.1)
	cyl.top_radius = r
	cyl.bottom_radius = r * 0.92
	cyl.height = 0.02
	cyl.radial_segments = 16
	mi.mesh = cyl
	mi.position = pos
	mi.rotation_degrees.x = 90.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.06, 0.07, 0.09, 0.85)
	mat.metallic = 0.35
	mat.roughness = 0.08
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


static func _spawn_leaf(parent: Node3D, rng: RandomNumberGenerator, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(rng.randf_range(0.08, 0.18), rng.randf_range(0.06, 0.14))
	mi.mesh = plane
	mi.position = pos
	mi.rotation_degrees = Vector3(
		rng.randf_range(-8.0, 8.0),
		rng.randf_range(0.0, 360.0),
		rng.randf_range(-12.0, 12.0))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(
		rng.randf_range(0.18, 0.28),
		rng.randf_range(0.22, 0.32),
		rng.randf_range(0.10, 0.16))
	mat.roughness = 0.95
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


static func _spawn_debris(parent: Node3D, rng: RandomNumberGenerator, pos: Vector3) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation_degrees.y = rng.randf_range(0.0, 360.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.14, 0.13, 0.12)
	mat.roughness = 0.92
	for j in rng.randi_range(1, 3):
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(
			rng.randf_range(0.04, 0.14),
			rng.randf_range(0.02, 0.06),
			rng.randf_range(0.04, 0.12))
		mi.mesh = bm
		mi.position = Vector3(rng.randf_range(-0.2, 0.2), 0.0, rng.randf_range(-0.2, 0.2))
		mi.rotation_degrees.y = rng.randf_range(0.0, 180.0)
		mi.material_override = mat
		root.add_child(mi)
	parent.add_child(root)
