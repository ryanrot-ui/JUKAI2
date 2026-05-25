extends Node3D

# ─── Ground Vegetation Spawner ────────────────────────────────────────────────
# Scatters low-poly grass tufts across the forest floor.
# Two-sided cross-plane geometry, properly shaded so flashlight reveals them.

@export var count: int = 140
@export var area_size: Vector2 = Vector2(80.0, 80.0)
@export var avoid_center_radius: float = 0.0
@export var avoid_path_width: float = 0.0    # skip |x| < this (for paths)
@export var random_seed: int = 555

# Palette — varied greens for depth
const COLORS = [
	Color(0.04, 0.07, 0.025),
	Color(0.03, 0.05, 0.018),
	Color(0.025, 0.04, 0.014),
	Color(0.05, 0.06, 0.028),
	Color(0.035, 0.055, 0.02),
]

func _ready() -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = random_seed

	# Build one MultiMesh per color bucket to avoid per-instance coloring overhead
	var buckets: Dictionary = {}
	for ci in COLORS.size():
		buckets[ci] = []

	var total_placed = 0
	for _i in count * 5:
		if total_placed >= count:
			break
		var x = rng.randf_range(-area_size.x * 0.5, area_size.x * 0.5)
		var z = rng.randf_range(-area_size.y * 0.5, area_size.y * 0.5)
		if Vector2(x, z).length() < avoid_center_radius:
			continue
		if abs(x) > area_size.x * 0.5 or abs(z) > area_size.y * 0.5:
			continue
		if avoid_path_width > 0 and abs(x) < avoid_path_width:
			continue
		var sv = rng.randf_range(0.7, 1.6)
		var ry = rng.randf_range(0.0, TAU)
		var t = Transform3D(Basis.IDENTITY.scaled(Vector3(sv, sv, sv)).rotated(Vector3.UP, ry), Vector3(x, 0.0, z))
		var ci = rng.randi() % COLORS.size()
		buckets[ci].append(t)
		total_placed += 1

	for ci in COLORS.size():
		var transforms: Array = buckets[ci]
		if transforms.is_empty():
			continue
		var mmi = MultiMeshInstance3D.new()
		var mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.instance_count = transforms.size()
		mm.mesh = _make_grass_mesh(COLORS[ci])
		for i in transforms.size():
			mm.set_instance_transform(i, transforms[i])
		mmi.multimesh = mm
		# Grass is tiny — cull past 28 m; use FADE_SELF for graceful near-distance pop
		mmi.visibility_range_end        = 28.0
		mmi.visibility_range_end_margin = 4.0
		mmi.visibility_range_fade_mode  = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)

func _make_grass_mesh(col: Color) -> Mesh:
	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h  = 0.21
	var hw = 0.20
	# Cross of two planes, both sides
	_add_grass_quad(st, Vector3(-hw, 0, 0), Vector3(hw, 0, 0), Vector3(hw, h, 0), Vector3(-hw, h, 0),  Vector3(0, 0, 1))
	_add_grass_quad(st, Vector3(-hw, 0, 0), Vector3(hw, 0, 0), Vector3(hw, h, 0), Vector3(-hw, h, 0), -Vector3(0, 0, 1))
	_add_grass_quad(st, Vector3(0, 0, -hw), Vector3(0, 0, hw), Vector3(0, h, hw), Vector3(0, h, -hw),  Vector3(1, 0, 0))
	_add_grass_quad(st, Vector3(0, 0, -hw), Vector3(0, 0, hw), Vector3(0, h, hw), Vector3(0, h, -hw), -Vector3(1, 0, 0))
	var mesh = st.commit()
	var mat = StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 1.0; mat.metallic = 0.0; mat.metallic_specular = 0.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, mat)
	return mesh

func _add_grass_quad(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3, n: Vector3) -> void:
	st.set_normal(n)
	st.add_vertex(v0); st.add_vertex(v1); st.add_vertex(v2)
	st.add_vertex(v0); st.add_vertex(v2); st.add_vertex(v3)
