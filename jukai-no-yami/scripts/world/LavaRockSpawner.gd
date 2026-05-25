extends Node3D

# ─── Volcanic Rock Spawner — Aokigahara Style ────────────────────────────────
# Dark basalt boulders with moss/lichen overlay — characteristic of Aokigahara.

@export var count: int = 22
@export var area_size: Vector2 = Vector2(70, 70)
@export var avoid_center_radius: float = 4.0
@export var avoid_path_width: float = 3.5
@export var random_seed: int = 444

func _ready() -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = random_seed
	var placed = 0
	for _i in count * 4:
		if placed >= count:
			break
		var x = rng.randf_range(-area_size.x * 0.5, area_size.x * 0.5)
		var z = rng.randf_range(-area_size.y * 0.5, area_size.y * 0.5)
		if Vector2(x, z).length() < avoid_center_radius:
			continue
		if abs(x) < avoid_path_width:
			continue
		_spawn_rock_cluster(Vector3(x, 0, z), rng)
		placed += 1

func _spawn_rock_cluster(center: Vector3, rng: RandomNumberGenerator) -> void:
	var rock_count = rng.randi_range(2, 6)
	for _r in rock_count:
		var body = StaticBody3D.new()
		var rx = center.x + rng.randf_range(-1.0, 1.0)
		var rz = center.z + rng.randf_range(-1.0, 1.0)
		body.position = Vector3(rx, 0, rz)
		body.rotation_degrees.y = rng.randf_range(0, 360)

		var h = rng.randf_range(0.22, 0.85)
		var w = rng.randf_range(0.28, 0.92)
		var d = rng.randf_range(0.22, 0.78)

		# Mix box (blocky basalt slabs) with sphere (rounded boulders)
		var use_sphere = rng.randf() < 0.35
		var mi = MeshInstance3D.new()
		if use_sphere:
			var sm = SphereMesh.new()
			sm.radius = w * 0.5; sm.height = h
			sm.radial_segments = 8; sm.rings = 4
			mi.mesh = sm
		else:
			var bm = BoxMesh.new()
			bm.size = Vector3(w, h, d)
			mi.mesh = bm
		mi.position = Vector3(0, h * 0.5, 0)
		var rock_mat = StandardMaterial3D.new()
		rock_mat.albedo_color      = Color(0.135, 0.115, 0.095)
		rock_mat.roughness         = 0.96
		rock_mat.metallic          = 0.0
		rock_mat.metallic_specular = 0.02
		mi.material_override = rock_mat
		mi.visibility_range_end        = 50.0
		mi.visibility_range_end_margin = 5.0
		mi.visibility_range_fade_mode  = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(mi)

		# Moss / lichen cap on top — varies green to grey-green
		if rng.randf() < 0.72:
			var moss_mi = MeshInstance3D.new()
			if use_sphere:
				var msm = SphereMesh.new()
				msm.radius = w * 0.52; msm.height = h * 0.30
				msm.radial_segments = 8; msm.rings = 3
				moss_mi.mesh = msm
				moss_mi.position = Vector3(0, h * 0.70, 0)
			else:
				var mbm = BoxMesh.new()
				mbm.size = Vector3(w * 1.05, h * 0.18, d * 1.05)
				moss_mi.mesh = mbm
				moss_mi.position = Vector3(0, h, 0)
			var moss_mat = StandardMaterial3D.new()
			match rng.randi() % 3:
				0: moss_mat.albedo_color = Color(0.068, 0.138, 0.038)  # vivid forest moss
				1: moss_mat.albedo_color = Color(0.040, 0.085, 0.026)  # dark wet moss
				2: moss_mat.albedo_color = Color(0.092, 0.110, 0.058)  # grey-green lichen
			moss_mat.roughness = 1.0; moss_mat.metallic = 0.0; moss_mat.metallic_specular = 0.0
			moss_mi.material_override = moss_mat
			moss_mi.visibility_range_end        = 50.0
			moss_mi.visibility_range_end_margin = 5.0
			moss_mi.visibility_range_fade_mode  = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			moss_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			body.add_child(moss_mi)

		# Collision shape
		var col = CollisionShape3D.new()
		if use_sphere:
			var cs = SphereShape3D.new(); cs.radius = w * 0.5
			col.shape = cs
		else:
			var bs = BoxShape3D.new(); bs.size = Vector3(w, h, d)
			col.shape = bs
		col.position = Vector3(0, h * 0.5, 0)
		body.add_child(col)
		add_child(body)
