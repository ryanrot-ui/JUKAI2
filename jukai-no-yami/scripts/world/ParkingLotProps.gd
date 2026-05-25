extends RefCounted
## Wet-asphalt accents, puddles, leaves, debris.
## Decor is constrained to the asphalt rectangle (x ±22, z [-16, 16]) and
## avoids the central path corridor + the four lot lights + the two parked
## cars — i.e. it cannot spawn inside another mesh.

const _ASPHALT_SHADER := preload("res://shaders/asphalt_wet.gdshader")

# Reject positions inside any of these axis-aligned rectangles (XZ plane).
# Keep this list in sync with ParkingLot.gd structures.
const _AVOID_BOXES: Array = [
	# Path corridor (full length, generous margin)
	Rect2(-3.0, -38.0, 6.0, 44.0),
	# Player car
	Rect2(-8.2, 6.5, 4.0, 4.0),
	# Abandoned car
	Rect2(5.5, 8.5, 4.0, 4.0),
	# Side lights
	Rect2(-9.7, 3.3, 1.4, 1.4),
	Rect2( 8.3, 3.3, 1.4, 1.4),
	Rect2(-9.7, -8.7, 1.4, 1.4),
	Rect2( 8.3, -8.7, 1.4, 1.4),
	# Sign
	Rect2(4.6, -7.5, 2.0, 2.0),
	# Gate footprint
	Rect2(-3.4, -12.6, 6.8, 1.2),
]


static func apply_wet_asphalt(mesh_inst: MeshInstance3D) -> void:
	var m := ShaderMaterial.new()
	m.shader = _ASPHALT_SHADER
	m.set_shader_parameter("asphalt_color", Color(0.10, 0.10, 0.11, 1.0))
	m.set_shader_parameter("wet_patches", 0.75)
	mesh_inst.material_override = m


static func spawn_decor(parent: Node3D, rng_seed: int = 8801) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	# Puddles — flat, on asphalt, away from structures
	for i in 7:
		var p := _pick(rng, 0.4)
		if p == Vector3.INF:
			continue
		_spawn_puddle(parent, rng, p)
	# Leaves
	for i in 28:
		var p := _pick(rng, 0.2)
		if p == Vector3.INF:
			continue
		_spawn_leaf(parent, rng, p)
	# Debris piles
	for i in 5:
		var p := _pick(rng, 0.3)
		if p == Vector3.INF:
			continue
		_spawn_debris(parent, rng, p)


# Returns Vector3.INF if no acceptable point found within budget.
static func _pick(rng: RandomNumberGenerator, prop_radius: float) -> Vector3:
	# Asphalt rect (matches LOT_HALF_X / LOT_NORTH_Z / LOT_SOUTH_Z in ParkingLot)
	for _attempt in 20:
		var x := rng.randf_range(-20.0, 20.0)
		var z := rng.randf_range(-14.0, 14.0)
		var ok := true
		for r: Rect2 in _AVOID_BOXES:
			# Inflate avoid rect by the prop radius so a circle of that size
			# fully clears the structure.
			var inflated := r.grow(prop_radius)
			if inflated.has_point(Vector2(x, z)):
				ok = false
				break
		if ok:
			# Sit on top of asphalt overlay (top at y=0.04) — well above the
			# forest floor at y=0 so puddles read as on-the-surface, not below.
			return Vector3(x, 0.045, z)
	return Vector3.INF


static func _spawn_puddle(parent: Node3D, rng: RandomNumberGenerator, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	# Use a flat PlaneMesh instead of a rotated cylinder — no thickness, no
	# edge artefacts, no chance of looking like a floating disc from below.
	var plane := PlaneMesh.new()
	var r := rng.randf_range(0.7, 1.8)
	plane.size = Vector2(r, r * rng.randf_range(0.7, 1.1))
	mi.mesh = plane
	mi.position = pos
	mi.rotation_degrees.y = rng.randf_range(0.0, 180.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.06, 0.08, 0.88)
	mat.metallic = 0.40
	mat.roughness = 0.08
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Visible only from above (the player's natural viewpoint) — eliminates
	# the "disc seen from underneath" artefact.
	mat.cull_mode = BaseMaterial3D.CULL_BACK
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
		mi.position = Vector3(rng.randf_range(-0.2, 0.2), bm.size.y * 0.5, rng.randf_range(-0.2, 0.2))
		mi.rotation_degrees.y = rng.randf_range(0.0, 180.0)
		mi.material_override = mat
		root.add_child(mi)
	parent.add_child(root)
