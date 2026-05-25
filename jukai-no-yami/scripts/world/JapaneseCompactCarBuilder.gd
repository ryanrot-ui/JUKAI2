extends RefCounted
## Procedural Honda Fit / old Toyota compact — correct wheel axes, wet J-horror materials.

const _PAINT_SHADER := preload("res://shaders/car_paint_wet.gdshader")
const _GLASS_SHADER := preload("res://shaders/car_glass_rain.gdshader")

# Compact JDM sedan proportions (metres). Forward = +Z, right = +X.
const LENGTH := 3.92
const WIDTH := 1.68
const WHEEL_RADIUS := 0.315
const WHEEL_WIDTH := 0.205
const TRACK := 1.52
const WHEELBASE_HALF := 1.26

static func build(
		parent: Node3D,
		world_pos: Vector3,
		paint: Color = Color(0.11, 0.13, 0.17),
		yaw_deg: float = 0.0,
		opts: Dictionary = {}
) -> StaticBody3D:
	var abandoned: bool = opts.get("abandoned", false)
	var headlights_on: bool = opts.get("headlights_on", not abandoned)
	var dirt: float = opts.get("dirt", 0.42 if abandoned else 0.22)
	var rust: float = opts.get("rust", 0.18 if abandoned else 0.06)
	var front_steer: float = opts.get("front_steer_deg", 6.0 if abandoned else 0.0)

	var car := StaticBody3D.new()
	car.name = opts.get("name", "ParkedCar")
	car.position = world_pos
	car.rotation_degrees.y = yaw_deg

	var vis := Node3D.new()
	vis.name = "Visual"
	car.add_child(vis)

	var paint_mat := _make_paint_mat(paint, dirt, rust)
	var glass_mat := _make_glass_mat()
	var rubber := _make_rubber_mat()
	var plastic := _make_plastic_mat()
	var chrome := _make_chrome_mat()
	var black := _make_black_mat()

	# ── Lower hull & rockers (tapered silhouette, not one Minecraft box) ────────
	_add_box(vis, Vector3(WIDTH, 0.52, LENGTH * 0.88), Vector3(0, 0.38, -0.04), paint_mat)
	_add_box(vis, Vector3(WIDTH * 0.94, 0.18, LENGTH * 0.72), Vector3(0, 0.62, -0.02), paint_mat)
	# Belt line / shoulder
	_add_box(vis, Vector3(WIDTH * 0.98, 0.14, LENGTH * 0.55), Vector3(0, 0.74, -0.18), paint_mat)

	# Hood — long, slightly domed stack
	_add_box(vis, Vector3(WIDTH * 0.96, 0.14, 1.22), Vector3(0, 0.78, 1.02), paint_mat)
	_add_box(vis, Vector3(WIDTH * 0.88, 0.10, 0.95), Vector3(0, 0.86, 1.18), paint_mat)

	# Cabin / greenhouse
	_add_box(vis, Vector3(WIDTH * 0.92, 0.62, 1.95), Vector3(0, 1.12, -0.12), paint_mat)
	_add_box(vis, Vector3(WIDTH * 0.86, 0.12, 1.72), Vector3(0, 1.48, -0.14), paint_mat)

	# Trunk deck
	_add_box(vis, Vector3(WIDTH * 0.90, 0.22, 0.88), Vector3(0, 0.82, -1.38), paint_mat)
	_add_box(vis, Vector3(WIDTH * 0.82, 0.08, 0.42), Vector3(0, 0.94, -1.72), paint_mat)

	# Front / rear fascias (plastic)
	_add_box(vis, Vector3(WIDTH * 0.98, 0.26, 0.22), Vector3(0, 0.42, 1.92), plastic)
	_add_box(vis, Vector3(WIDTH * 0.96, 0.24, 0.20), Vector3(0, 0.44, -1.94), plastic)

	# Grille & lower intake
	_add_box(vis, Vector3(WIDTH * 0.55, 0.28, 0.06), Vector3(0, 0.52, 1.96), black)
	_add_box(vis, Vector3(WIDTH * 0.38, 0.08, 0.04), Vector3(0, 0.38, 1.97), black)

	# Windshield & rear glass (angled)
	_add_glass_panel(vis, Vector3(WIDTH * 0.86, 0.52, 0.06), Vector3(0, 1.18, 0.72), Vector3(-22, 0, 0), glass_mat)
	_add_glass_panel(vis, Vector3(WIDTH * 0.82, 0.44, 0.06), Vector3(0, 1.16, -0.82), Vector3(24, 0, 0), glass_mat)
	# Side windows
	_add_glass_panel(vis, Vector3(0.05, 0.42, 1.55), Vector3(WIDTH * 0.46, 1.14, -0.05), Vector3(0, 0, 90), glass_mat)
	_add_glass_panel(vis, Vector3(0.05, 0.42, 1.55), Vector3(-WIDTH * 0.46, 1.14, -0.05), Vector3(0, 0, 90), glass_mat)
	# Dark interior read through glass
	_add_box(vis, Vector3(WIDTH * 0.72, 0.38, 1.65), Vector3(0, 1.02, -0.1), black)

	# Door seams
	for z in [-0.35, 0.45]:
		_add_box(vis, Vector3(0.02, 0.52, 0.02), Vector3(WIDTH * 0.48, 0.88, z), black)
		_add_box(vis, Vector3(0.02, 0.52, 0.02), Vector3(-WIDTH * 0.48, 0.88, z), black)

	# Mirrors
	for side in [-1.0, 1.0]:
		_add_box(vis, Vector3(0.14, 0.08, 0.18), Vector3(side * (WIDTH * 0.52), 1.22, 0.55), plastic)
		_add_box(vis, Vector3(0.22, 0.12, 0.10), Vector3(side * (WIDTH * 0.58), 1.28, 0.58), paint_mat)

	# Headlights (housing + lens)
	for side in [-1.0, 1.0]:
		_add_box(vis, Vector3(0.32, 0.16, 0.10), Vector3(side * 0.58, 0.58, 1.88), plastic)
		var lens := _add_box(vis, Vector3(0.26, 0.12, 0.06), Vector3(side * 0.58, 0.58, 1.92), chrome)
		if headlights_on and lens is MeshInstance3D:
			var em := StandardMaterial3D.new()
			em.albedo_color = Color(0.92, 0.88, 0.72)
			em.emission_enabled = true
			em.emission = Color(1.0, 0.94, 0.75)
			em.emission_energy_multiplier = 0.35
			em.roughness = 0.12
			lens.material_override = em

	# Tail lights
	for side in [-1.0, 1.0]:
		var tl := _add_box(vis, Vector3(0.28, 0.14, 0.05), Vector3(side * 0.62, 0.56, -1.90), plastic)
		var tl_mat := StandardMaterial3D.new()
		tl_mat.albedo_color = Color(0.55, 0.04, 0.04)
		tl_mat.emission_enabled = true
		tl_mat.emission = Color(0.9, 0.05, 0.04)
		tl_mat.emission_energy_multiplier = 0.22 if abandoned else 0.08
		tl_mat.roughness = 0.25
		if tl is MeshInstance3D:
			tl.material_override = tl_mat

	# License plate (rear)
	_add_box(vis, Vector3(0.42, 0.12, 0.02), Vector3(0, 0.52, -1.93), chrome)
	_add_box(vis, Vector3(0.36, 0.08, 0.015), Vector3(0, 0.52, -1.945), plastic)

	# Wipers on windshield
	_add_box(vis, Vector3(0.04, 0.02, 0.52), Vector3(0.12, 1.38, 0.78), black)
	_add_box(vis, Vector3(0.04, 0.02, 0.42), Vector3(-0.08, 1.36, 0.82), black)

	# Bumpers
	_add_box(vis, Vector3(WIDTH * 0.94, 0.14, 0.16), Vector3(0, 0.34, 1.98), plastic)
	_add_box(vis, Vector3(WIDTH * 0.92, 0.14, 0.16), Vector3(0, 0.34, -1.98), plastic)

	# Wheels — torus tires, axle along X (correct ground alignment)
	var wheel_y := WHEEL_RADIUS + 0.02
	var hx := TRACK * 0.5
	for fz in [WHEELBASE_HALF, -WHEELBASE_HALF]:
		var is_front := fz > 0.0
		var steer := front_steer if is_front else 0.0
		_make_wheel(vis, Vector3(hx, wheel_y, fz), steer, rubber, chrome, abandoned)
		_make_wheel(vis, Vector3(-hx, wheel_y, fz), -steer, rubber, chrome, abandoned)

	# Wheel arch hints (dark shadow strip)
	for side in [-1.0, 1.0]:
		for fz in [WHEELBASE_HALF, -WHEELBASE_HALF]:
			_add_box(vis, Vector3(0.18, 0.06, 0.38), Vector3(side * (hx + 0.08), 0.58, fz), black)

	# Collision hull
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(WIDTH + 0.08, 1.42, LENGTH + 0.06)
	col.shape = box
	col.position = Vector3(0, 0.72, 0)
	car.add_child(col)

	parent.add_child(car)
	return car


static func _make_wheel(
		parent: Node3D,
		local_pos: Vector3,
		steer_deg: float,
		rubber: Material,
		chrome: Material,
		abandoned: bool
) -> void:
	var mount := Node3D.new()
	mount.name = "Wheel"
	mount.position = local_pos
	mount.rotation_degrees.y = steer_deg
	parent.add_child(mount)

	# Tire — torus lies in YZ by default; rotate so hole (axle) runs along X
	var tire_mesh := TorusMesh.new()
	tire_mesh.inner_radius = WHEEL_RADIUS - 0.09
	tire_mesh.outer_radius = WHEEL_RADIUS
	tire_mesh.ring_segments = 18
	tire_mesh.radial_segments = 12
	var tire := MeshInstance3D.new()
	tire.name = "Tire"
	tire.mesh = tire_mesh
	tire.material_override = rubber
	tire.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	mount.add_child(tire)

	# Rim barrel
	var rim_mesh := CylinderMesh.new()
	rim_mesh.top_radius = WHEEL_RADIUS * 0.62
	rim_mesh.bottom_radius = WHEEL_RADIUS * 0.62
	rim_mesh.height = WHEEL_WIDTH * 0.55
	rim_mesh.radial_segments = 20
	var rim := MeshInstance3D.new()
	rim.name = "Rim"
	rim.mesh = rim_mesh
	rim.material_override = chrome
	rim.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	mount.add_child(rim)

	# Hub cap
	var hub_mesh := CylinderMesh.new()
	hub_mesh.top_radius = WHEEL_RADIUS * 0.22
	hub_mesh.bottom_radius = WHEEL_RADIUS * 0.22
	hub_mesh.height = 0.04
	hub_mesh.radial_segments = 16
	var hub := MeshInstance3D.new()
	hub.name = "Hub"
	hub.mesh = hub_mesh
	hub.material_override = chrome
	hub.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	mount.add_child(hub)

	if abandoned:
		var sag := fmod(absf(local_pos.x) + local_pos.z * 3.17, 1.0)
		if sag > 0.45:
			mount.position.y -= 0.016


static func _add_box(
		parent: Node3D,
		size: Vector3,
		pos: Vector3,
		mat: Material,
		rot_deg: Vector3 = Vector3.ZERO
) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	parent.add_child(mi)
	return mi


static func _add_glass_panel(
		parent: Node3D,
		size: Vector3,
		pos: Vector3,
		rot_deg: Vector3,
		mat: Material
) -> void:
	var mi := _add_box(parent, size, pos, mat, rot_deg)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


static func _make_paint_mat(color: Color, dirt: float, rust: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _PAINT_SHADER
	m.set_shader_parameter("paint_color", color)
	m.set_shader_parameter("wetness", 0.58)
	m.set_shader_parameter("dirt_amount", dirt)
	m.set_shader_parameter("rust_amount", rust)
	m.set_shader_parameter("metallic", 0.68)
	m.set_shader_parameter("roughness_base", 0.36)
	return m


static func _make_glass_mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _GLASS_SHADER
	m.set_shader_parameter("glass_tint", Color(0.12, 0.16, 0.22, 0.48))
	m.set_shader_parameter("rain_streaks", 0.72)
	return m


static func _make_rubber_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.05, 0.05, 0.05)
	m.roughness = 0.96
	m.metallic = 0.0
	m.metallic_specular = 0.02
	return m


static func _make_plastic_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.09, 0.09, 0.10)
	m.roughness = 0.82
	m.metallic = 0.05
	return m


static func _make_chrome_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.55, 0.56, 0.58)
	m.metallic = 0.85
	m.roughness = 0.28
	m.metallic_specular = 0.7
	return m


static func _make_black_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.04, 0.04, 0.045)
	m.roughness = 0.9
	m.metallic = 0.0
	return m
