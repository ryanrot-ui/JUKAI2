extends Node3D
## Guided trail: emissive path mesh, path markers, breadcrumb lights.

const _PATH_MARKERS := preload("res://scripts/world/PathMarkerSpawner.gd")

@export var path_center_z: float = -40.0
@export var path_length: float = 80.0
@export var path_half_width: float = 2.6
@export var path_center: Vector3 = Vector3.ZERO
@export var stake_spacing: float = 7.0
@export var lantern_every: int = 2
@export var light_spacing: float = 14.0
@export var rand_seed: int = 4242


func _ready() -> void:
	build()


func build() -> void:
	if has_meta("_trail_built"):
		return
	set_meta("_trail_built", true)

	var center := path_center
	if center == Vector3.ZERO:
		center = Vector3(0, 0.03, path_center_z)

	var level_root := get_parent() as Node3D
	if not level_root:
		return

	_make_path_mesh(level_root, center, path_length, path_half_width * 2.0)
	_spawn_path_markers(level_root, center)
	_spawn_breadcrumb_lights(level_root, center, path_length, path_half_width)


func _spawn_path_markers(level_root: Node3D, center: Vector3) -> void:
	var pm := Node3D.new()
	pm.name = "PathMarkers"
	pm.set_script(_PATH_MARKERS)
	pm.path_center_z = center.z
	pm.path_length = path_length
	pm.path_hw = path_half_width
	pm.rand_seed = rand_seed
	pm.stake_spacing = stake_spacing
	pm.lantern_every = lantern_every
	level_root.add_child(pm)


func _make_path_mesh(parent: Node3D, center: Vector3, length: float, width: float) -> void:
	var body := StaticBody3D.new()
	body.name = "GuidedTrailPath"
	body.position = center
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, 0.08, length)
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	var bm := BoxMesh.new()
	bm.size = Vector3(width, 0.08, length)
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.38, 0.32, 0.22)
	mat.roughness = 0.96
	mat.emission_enabled = true
	mat.emission = Color(0.12, 0.10, 0.06)
	mat.emission_energy_multiplier = 0.35
	mi.material_override = mat
	body.add_child(mi)
	parent.add_child(body)


func _spawn_breadcrumb_lights(level_root: Node3D, center: Vector3, length: float, hw: float) -> void:
	var holder := Node3D.new()
	holder.name = "TrailBreadcrumbs"
	level_root.add_child(holder)
	var z_near := center.z + length * 0.5 - 3.0
	var z_far := center.z - length * 0.5 + 6.0
	var z := z_near
	var n := 0
	while z >= z_far:
		if n % 2 == 0:
			var side: int = 1 if (n % 4 < 2) else -1
			var gl := OmniLight3D.new()
			gl.position = Vector3(side * (hw * 0.35), 0.35, z)
			gl.light_color = Color(0.82, 0.72, 0.48)
			gl.light_energy = 0.55
			gl.omni_range = 8.0
			gl.shadow_enabled = false
			holder.add_child(gl)
		z -= light_spacing
		n += 1
