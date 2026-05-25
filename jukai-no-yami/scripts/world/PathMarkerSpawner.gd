extends Node3D
## Trail stakes + lanterns along the forest path.

@export var path_center_z: float = -35.0
@export var path_length: float = 90.0
@export var path_hw: float = 2.8
@export var rand_seed: int = 5551234
@export var stake_spacing: float = 9.0
@export var lantern_every: int = 4


func _ready() -> void:
	build()


func build() -> void:
	if get_child_count() > 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = rand_seed

	var stake_mat := _wood_mat(Color(0.18, 0.12, 0.07))
	var sx := path_hw + 0.45

	var z_near := path_center_z + path_length * 0.5 - 4.0
	var z_far := path_center_z - path_length * 0.5 + 8.0
	var z := z_near
	var n := 0
	while z >= z_far:
		_place_stake(Vector3(sx, 0, z), rng, stake_mat)
		if n % 2 == 0:
			_place_stake(Vector3(-sx, 0, z), rng, stake_mat)
		if lantern_every > 0 and n % lantern_every == 0:
			var stake_idx: int = int(n / lantern_every)
			var lan_side: int = 1 if (stake_idx % 2 == 0) else -1
			_place_lantern(Vector3(lan_side * (path_hw - 0.3), 0, z), rng)
		z -= stake_spacing
		n += 1


func _place_stake(pos: Vector3, rng: RandomNumberGenerator, stake_mat: StandardMaterial3D) -> void:
	var root := StaticBody3D.new()
	root.position = pos
	root.rotation_degrees.y = rng.randf_range(0.0, 360.0)
	root.rotation_degrees.z = rng.randf_range(-5.5, 5.5)

	var h := rng.randf_range(1.10, 1.55)
	var post_mesh := CylinderMesh.new()
	post_mesh.height = h
	post_mesh.top_radius = 0.022
	post_mesh.bottom_radius = 0.032
	post_mesh.radial_segments = 6
	var post_mi := MeshInstance3D.new()
	post_mi.mesh = post_mesh
	post_mi.material_override = stake_mat
	post_mi.position = Vector3(0, h * 0.5, 0)
	post_mi.visibility_range_end = 32.0
	post_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(post_mi)

	var palette := [
		Color(0.86, 0.84, 0.80, 0.55),
		Color(0.78, 0.13, 0.11, 0.50),
		Color(0.68, 0.62, 0.46, 0.45),
	]
	for ri in rng.randi_range(2, 3):
		var col: Color = palette[ri % palette.size()]
		var rbm := BoxMesh.new()
		rbm.size = Vector3(0.020, rng.randf_range(0.28, 0.48), 0.004)
		var rmi := MeshInstance3D.new()
		rmi.mesh = rbm
		var rmat := StandardMaterial3D.new()
		rmat.albedo_color = col
		rmat.roughness = 1.0
		rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		rmi.material_override = rmat
		rmi.position = Vector3(
			rng.randf_range(-0.022, 0.022),
			h + rbm.size.y * 0.5,
			rng.randf_range(-0.008, 0.008))
		rmi.rotation_degrees.y = rng.randf_range(0.0, 180.0)
		rmi.visibility_range_end = 26.0
		rmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(rmi)

	var cs := CylinderShape3D.new()
	cs.height = h
	cs.radius = 0.032
	var col_shape := CollisionShape3D.new()
	col_shape.shape = cs
	col_shape.position = Vector3(0, h * 0.5, 0)
	root.add_child(col_shape)
	add_child(root)


func _place_lantern(pos: Vector3, rng: RandomNumberGenerator) -> void:
	var root := StaticBody3D.new()
	root.position = pos
	var stake_h := 1.55
	var mat_wood := _wood_mat(Color(0.16, 0.10, 0.06))

	var post_mesh := CylinderMesh.new()
	post_mesh.height = stake_h
	post_mesh.top_radius = 0.018
	post_mesh.bottom_radius = 0.028
	var post_mi := MeshInstance3D.new()
	post_mi.mesh = post_mesh
	post_mi.material_override = mat_wood
	post_mi.position = Vector3(0, stake_h * 0.5, 0)
	post_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(post_mi)

	var lbm := BoxMesh.new()
	lbm.size = Vector3(0.17, 0.22, 0.17)
	var lmi := MeshInstance3D.new()
	lmi.mesh = lbm
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color(0.72, 0.66, 0.50, 0.75)
	lmat.roughness = 0.95
	lmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lmat.emission_enabled = true
	lmat.emission = Color(0.45, 0.32, 0.12)
	lmat.emission_energy_multiplier = 0.18
	lmi.material_override = lmat
	lmi.position = Vector3(0, stake_h + 0.11, 0)
	lmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(lmi)

	var light := OmniLight3D.new()
	light.light_color = Color(0.85, 0.55, 0.22)
	light.light_energy = rng.randf_range(1.4, 2.0)
	light.omni_range = 11.0
	light.shadow_enabled = false
	light.position = Vector3(0, stake_h + 0.11, 0)
	root.add_child(light)

	var cs := CylinderShape3D.new()
	cs.height = stake_h
	cs.radius = 0.028
	var col_shape := CollisionShape3D.new()
	col_shape.shape = cs
	col_shape.position = Vector3(0, stake_h * 0.5, 0)
	root.add_child(col_shape)
	add_child(root)


func _wood_mat(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.98
	m.metallic = 0.0
	return m
