extends Node3D

@export var ribbon_count: int = 40
@export var area_size: Vector2 = Vector2(60.0, 60.0)
@export var ribbon_height_min: float = 1.2
@export var ribbon_height_max: float = 2.8
@export var random_seed: int = 1337

# Muted prayer-strip colors — subtle, not glowing billboards
const RIBBON_COLORS = [
	Color(0.72, 0.70, 0.68, 0.38),
	Color(0.68, 0.66, 0.64, 0.32),
	Color(0.62, 0.14, 0.12, 0.42),
	Color(0.58, 0.12, 0.10, 0.36),
	Color(0.55, 0.50, 0.44, 0.30),
	Color(0.70, 0.68, 0.66, 0.28),
]


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed

	var color_groups: Dictionary = {}
	for i in ribbon_count:
		var x := rng.randf_range(-area_size.x * 0.5, area_size.x * 0.5)
		var z := rng.randf_range(-area_size.y * 0.5, area_size.y * 0.5)
		var y := rng.randf_range(ribbon_height_min, ribbon_height_max)
		var rot := rng.randf_range(0.0, TAU)
		var t := Transform3D(Basis.IDENTITY.rotated(Vector3.UP, rot), Vector3(x, y, z))
		var palette_idx := rng.randi() % RIBBON_COLORS.size()
		var key := str(palette_idx)
		if not color_groups.has(key):
			color_groups[key] = {"col": RIBBON_COLORS[palette_idx], "transforms": []}
		color_groups[key]["transforms"].append(t)

	for key in color_groups:
		var group = color_groups[key]
		var col: Color = group["col"]
		var transforms: Array = group["transforms"]
		var mmi := MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.instance_count = transforms.size()
		mm.mesh = _make_ribbon_mesh(col)
		for i in transforms.size():
			mm.set_instance_transform(i, transforms[i])
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)


func _make_ribbon_mesh(col: Color) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_color(col)
	st.add_vertex(Vector3(-0.025, 0.0, 0.0))
	st.add_vertex(Vector3(0.025, 0.0, 0.0))
	st.add_vertex(Vector3(0.025, 0.82, 0.0))
	st.add_vertex(Vector3(-0.025, 0.0, 0.0))
	st.add_vertex(Vector3(0.025, 0.82, 0.0))
	st.add_vertex(Vector3(-0.025, 0.82, 0.0))
	st.add_vertex(Vector3(0.025, 0.0, 0.0))
	st.add_vertex(Vector3(-0.025, 0.0, 0.0))
	st.add_vertex(Vector3(-0.025, 0.82, 0.0))
	st.add_vertex(Vector3(0.025, 0.0, 0.0))
	st.add_vertex(Vector3(-0.025, 0.82, 0.0))
	st.add_vertex(Vector3(0.025, 0.82, 0.0))
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.emission_enabled = false
	mat.roughness = 0.95
	mesh.surface_set_material(0, mat)
	return mesh
