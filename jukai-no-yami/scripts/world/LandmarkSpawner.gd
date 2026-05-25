extends Node3D

@export var count: int = 6
@export var area_size: Vector2 = Vector2(60, 60)
@export var avoid_center_radius: float = 10.0
@export var random_seed: int = 777

func _ready() -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = random_seed
	var placed = 0
	for _i in count * 5:
		if placed >= count:
			break
		var x = rng.randf_range(-area_size.x * 0.5, area_size.x * 0.5)
		var z = rng.randf_range(-area_size.y * 0.5, area_size.y * 0.5)
		if Vector2(x, z).length() < avoid_center_radius:
			continue
		if rng.randf() < 0.5:
			_spawn_pillar(Vector3(x, 0, z), rng)
		else:
			_spawn_torii(Vector3(x, 0, z), rng)
		placed += 1

func _spawn_pillar(pos: Vector3, rng: RandomNumberGenerator) -> void:
	var h = rng.randf_range(3.8, 8.0)
	var r = rng.randf_range(0.32, 0.72)
	var body = StaticBody3D.new()
	body.position = pos

	var cshape = CylinderShape3D.new()
	cshape.height = h; cshape.radius = r
	var col = CollisionShape3D.new()
	col.shape = cshape; col.position = Vector3(0, h * 0.5, 0)
	body.add_child(col)

	var cmesh = CylinderMesh.new()
	cmesh.height = h; cmesh.top_radius = r; cmesh.bottom_radius = r * 1.18
	var mi = MeshInstance3D.new()
	mi.mesh = cmesh; mi.position = Vector3(0, h * 0.5, 0)
	mi.material_override = _stone_mat()
	mi.visibility_range_end        = 60.0
	mi.visibility_range_end_margin = 6.0
	mi.visibility_range_fade_mode  = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(mi)

	add_child(body)

func _spawn_torii(pos: Vector3, rng: RandomNumberGenerator) -> void:
	var body = StaticBody3D.new()
	body.position = pos
	body.rotation_degrees.y = rng.randf_range(0.0, 360.0)
	var mat = _wood_mat()

	for side in [-1, 1]:
		var pm = BoxMesh.new()
		pm.size = Vector3(0.22, 4.6, 0.22)
		var pi = MeshInstance3D.new()
		pi.mesh = pm; pi.material_override = mat
		pi.position = Vector3(side * 1.25, 2.3, 0)
		body.add_child(pi)

	var top_beam = BoxMesh.new()
	top_beam.size = Vector3(3.0, 0.24, 0.24)
	var tbi = MeshInstance3D.new()
	tbi.mesh = top_beam; tbi.material_override = mat
	tbi.position = Vector3(0, 4.72, 0)
	body.add_child(tbi)

	var low_beam = BoxMesh.new()
	low_beam.size = Vector3(2.6, 0.18, 0.18)
	var lbi = MeshInstance3D.new()
	lbi.mesh = low_beam; lbi.material_override = mat
	lbi.position = Vector3(0, 3.85, 0)
	body.add_child(lbi)

	var bshape = BoxShape3D.new()
	bshape.size = Vector3(3.0, 5.2, 0.45)
	var bcol = CollisionShape3D.new()
	bcol.shape = bshape; bcol.position = Vector3(0, 2.6, 0)
	body.add_child(bcol)

	add_child(body)

func _stone_mat() -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = Color(0.20, 0.18, 0.17)
	m.roughness = 1.0; m.metallic = 0.0; m.metallic_specular = 0.0
	return m

func _wood_mat() -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.albedo_color = Color(0.16, 0.10, 0.06)
	m.roughness = 1.0; m.metallic = 0.0; m.metallic_specular = 0.0
	return m
