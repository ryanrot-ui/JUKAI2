extends RefCounted
## Procedural Honda Fit / old Toyota compact.
## v3 — replaces the previous box-stack with a SurfaceTool-generated body
## that has smooth-shaded slopes (hood, windshield, roof, rear window) so
## the car no longer reads as a stack of Minecraft blocks.

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

	# ── Main body — extruded side-profile with chamfered side bulge ─────────
	var body_mi := _build_body_mesh(paint_mat)
	vis.add_child(body_mi)

	# ── Glass: windshield, rear window, side windows — angled, dark ─────────
	_add_glass_panel(vis, Vector3(WIDTH * 0.86, 0.50, 0.06), Vector3(0, 1.16, 0.62), Vector3(-26, 0, 0), glass_mat)
	_add_glass_panel(vis, Vector3(WIDTH * 0.82, 0.44, 0.06), Vector3(0, 1.16, -0.78), Vector3(28, 0, 0), glass_mat)
	# Side windows (slight rake on top)
	_add_glass_panel(vis, Vector3(0.05, 0.40, 1.40), Vector3( WIDTH * 0.46, 1.18, -0.08), Vector3(0, 0, 90), glass_mat)
	_add_glass_panel(vis, Vector3(0.05, 0.40, 1.40), Vector3(-WIDTH * 0.46, 1.18, -0.08), Vector3(0, 0, 90), glass_mat)
	# Dark interior, visible through glass
	_add_box(vis, Vector3(WIDTH * 0.72, 0.36, 1.55), Vector3(0, 1.00, -0.08), black)

	# ── Front fascia: bumper, grille, headlights ─────────────────────────────
	_add_box(vis, Vector3(WIDTH * 0.98, 0.22, 0.18), Vector3(0, 0.34, 1.92), plastic)
	_add_box(vis, Vector3(WIDTH * 0.56, 0.26, 0.06), Vector3(0, 0.54, 1.97), black)   # grille
	_add_box(vis, Vector3(WIDTH * 0.36, 0.07, 0.04), Vector3(0, 0.38, 1.98), black)   # lower intake
	for side: float in [-1.0, 1.0]:
		# Headlight housing — recessed into the front fender, dark plastic
		_add_box(vis, Vector3(0.34, 0.16, 0.10), Vector3(side * 0.55, 0.58, 1.86), plastic)
		# Inner divider (gives the housing a "two-pod" look)
		_add_box(vis, Vector3(0.02, 0.12, 0.04), Vector3(side * 0.55, 0.58, 1.92), black)
		# Lens sits INSIDE the housing (~1 cm proud) — small, not a flat slab
		var lens_mi: MeshInstance3D = _add_box(vis, Vector3(0.24, 0.10, 0.025), Vector3(side * 0.55, 0.58, 1.93), chrome)
		if headlights_on:
			var em := StandardMaterial3D.new()
			em.albedo_color = Color(0.92, 0.86, 0.66)
			em.emission_enabled = true
			em.emission = Color(0.98, 0.90, 0.72)
			# Was 0.55 — bloomed into a white blob in playtests. Cut to a
			# subtle glow; the SpotLight beam below carries most of the punch.
			em.emission_energy_multiplier = 0.18
			em.roughness = 0.10
			lens_mi.material_override = em
			# Small actual SpotLight forward — gives the lens shape on the asphalt
			var beam := SpotLight3D.new()
			beam.position = Vector3(side * 0.55, 0.58, 2.00)
			beam.rotation_degrees = Vector3(-4.0, 0.0, 0.0)
			beam.light_color = Color(0.98, 0.92, 0.74)
			beam.light_energy = 1.4
			beam.spot_range = 8.0
			beam.spot_angle = 30.0
			beam.spot_angle_attenuation = 1.0
			beam.shadow_enabled = false
			vis.add_child(beam)

	# ── Rear fascia: bumper, tail lights, plate ──────────────────────────────
	_add_box(vis, Vector3(WIDTH * 0.96, 0.22, 0.18), Vector3(0, 0.34, -1.92), plastic)
	for side: float in [-1.0, 1.0]:
		# Tail-light housing (dark plastic surround). Recessed into the
		# rear fender so the red lens reads as a real light, not a sticker.
		_add_box(vis, Vector3(0.32, 0.18, 0.04), Vector3(side * 0.58, 0.56, -1.94), plastic)
		# Chrome divider strip (gives the lens the "two-segment" look)
		_add_box(vis, Vector3(0.02, 0.14, 0.025), Vector3(side * 0.58, 0.56, -1.96), chrome)
		# Two smaller lens segments per side instead of one big red slab
		for seg: float in [-1.0, 1.0]:
			var seg_x: float = side * 0.58 + seg * 0.07
			var tl: MeshInstance3D = _add_box(vis, Vector3(0.10, 0.12, 0.018), Vector3(seg_x, 0.56, -1.965), plastic)
			var tl_mat := StandardMaterial3D.new()
			tl_mat.albedo_color = Color(0.35, 0.03, 0.03)
			tl_mat.emission_enabled = true
			tl_mat.emission = Color(0.80, 0.04, 0.03)
			# Was 0.30/0.12 — bloomed into solid red blocks in playtests.
			# Dial to a faint persistent glow; matches real parked-car
			# reflectors that catch ambient light without being switched on.
			tl_mat.emission_energy_multiplier = 0.10 if abandoned else 0.04
			tl_mat.roughness = 0.30
			tl.material_override = tl_mat
	# Reverse light / centre reflector (white box, no emission)
	_add_box(vis, Vector3(0.10, 0.06, 0.02), Vector3(0, 0.46, -1.97), chrome)
	# License plate
	_add_box(vis, Vector3(0.42, 0.12, 0.02), Vector3(0, 0.34, -1.97), chrome)
	_add_box(vis, Vector3(0.36, 0.08, 0.015), Vector3(0, 0.34, -1.985), plastic)

	# ── Wheels — torus tires, axle along X ──────────────────────────────────
	var wheel_y := WHEEL_RADIUS + 0.02
	var hx := TRACK * 0.5
	for fz: float in [WHEELBASE_HALF, -WHEELBASE_HALF]:
		var is_front: bool = fz > 0.0
		var steer: float = front_steer if is_front else 0.0
		_make_wheel(vis, Vector3( hx, wheel_y, fz),  steer, rubber, chrome, abandoned)
		_make_wheel(vis, Vector3(-hx, wheel_y, fz), -steer, rubber, chrome, abandoned)

	# ── Curved wheel arches (replaces the old flat dark box) ────────────────
	var arch_mat := StandardMaterial3D.new()
	arch_mat.albedo_color = Color(0.04, 0.04, 0.045)
	arch_mat.roughness = 0.92
	for side: float in [-1.0, 1.0]:
		for fz: float in [WHEELBASE_HALF, -WHEELBASE_HALF]:
			var arch := _make_wheel_arch_mesh(arch_mat)
			arch.position = Vector3(side * (hx - 0.02), 0.0, fz)
			vis.add_child(arch)

	# ── Side mirrors with a stalk so they don't look like flying boxes ──────
	for side: float in [-1.0, 1.0]:
		# Stalk
		_add_box(vis, Vector3(0.10, 0.05, 0.10), Vector3(side * (WIDTH * 0.50), 1.20, 0.42), plastic)
		# Mirror housing
		_add_box(vis, Vector3(0.20, 0.11, 0.14), Vector3(side * (WIDTH * 0.56), 1.22, 0.45), paint_mat)

	# ── Door details: handle + seam ─────────────────────────────────────────
	for side: float in [-1.0, 1.0]:
		# Handle
		_add_box(vis, Vector3(0.02, 0.04, 0.18), Vector3(side * (WIDTH * 0.50), 0.95, 0.10), chrome)
		# Seam (front door)
		_add_box(vis, Vector3(0.015, 0.52, 0.015), Vector3(side * (WIDTH * 0.50), 0.86, 0.55), black)
		# Seam (rear door)
		_add_box(vis, Vector3(0.015, 0.52, 0.015), Vector3(side * (WIDTH * 0.50), 0.86, -0.40), black)

	# ── Wipers on windshield ────────────────────────────────────────────────
	_add_box(vis, Vector3(0.04, 0.02, 0.48), Vector3( 0.18, 1.32, 0.72), black)
	_add_box(vis, Vector3(0.04, 0.02, 0.38), Vector3(-0.10, 1.30, 0.76), black)

	# ── Collision hull ──────────────────────────────────────────────────────
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(WIDTH + 0.08, 1.50, LENGTH + 0.06)
	col.shape = box
	col.position = Vector3(0, 0.75, 0)
	car.add_child(col)

	parent.add_child(car)
	return car


# Generates the main car body as a single mesh built from a side-view profile
# extruded in X with a chamfered side bulge. Smooth normals give curved
# shading instead of the previous stacked-block look.
static func _build_body_mesh(mat: ShaderMaterial) -> MeshInstance3D:
	# Side profile (z, y) traversed front → back along the roof side, then
	# back → front along the bottom. Each point has a normal direction we
	# blend per-vertex for smooth shading.
	# fmt: off
	var profile := [
		# Front bumper area
		Vector2( 1.96, 0.40),  # 0: top of front bumper, vertical
		Vector2( 1.92, 0.55),  # 1: rise to grille level
		Vector2( 1.86, 0.70),  # 2: hood front lip
		# Hood — gentle slope
		Vector2( 1.50, 0.78),  # 3
		Vector2( 1.00, 0.82),  # 4
		Vector2( 0.78, 0.86),  # 5: back of hood, base of windshield
		# Windshield — steep rise to roof
		Vector2( 0.32, 1.46),  # 6: roof front
		# Roof — almost flat
		Vector2(-0.60, 1.50),  # 7
		# Rear window — slope down to trunk
		Vector2(-1.05, 1.30),  # 8
		Vector2(-1.40, 1.00),  # 9
		# Trunk deck
		Vector2(-1.65, 0.85),  # 10
		# Rear bumper
		Vector2(-1.85, 0.72),  # 11
		Vector2(-1.92, 0.55),  # 12
		Vector2(-1.96, 0.40),  # 13
	]
	# fmt: on
	var bottom_y := 0.30
	var half_w_full := WIDTH * 0.50           # 0.84
	var half_w_top := WIDTH * 0.43            # cabin/roof narrower than hips
	# Chamfer: outer hip ring + slightly inset top ring
	var sf := SurfaceTool.new()
	sf.begin(Mesh.PRIMITIVE_TRIANGLES)
	# For each profile point we emit two vertices: (x=+half, y, z) and (x=-half, y, z)
	# Connect adjacent profile points with quads on +X side, -X side, top side, bottom side.
	# To produce a chamfered side bulge we also add a mid-height "shoulder" ring.
	var pts_pos := []
	for p_i in profile.size():
		var p: Vector2 = profile[p_i]
		# Top of car (roof) narrower than bottom (rocker panel) — taper width with height
		var w := lerpf(half_w_full, half_w_top, smoothstep(0.30, 1.50, p.y))
		pts_pos.append([Vector3(-w, p.y, p.x), Vector3(w, p.y, p.x)])

	# 1) Top + side faces between consecutive profile points
	for i in profile.size():
		var j: int = (i + 1) % profile.size()
		var l0: Vector3 = pts_pos[i][0]
		var r0: Vector3 = pts_pos[i][1]
		var l1: Vector3 = pts_pos[j][0]
		var r1: Vector3 = pts_pos[j][1]
		# Top / front / rear cap — connects top vertices across width
		var n_top := ((r1 - r0).cross(l0 - r0)).normalized()
		sf.set_normal(n_top); sf.add_vertex(r0)
		sf.set_normal(n_top); sf.add_vertex(r1)
		sf.set_normal(n_top); sf.add_vertex(l1)
		sf.set_normal(n_top); sf.add_vertex(r0)
		sf.set_normal(n_top); sf.add_vertex(l1)
		sf.set_normal(n_top); sf.add_vertex(l0)

	# 2) Side panels (one strip down each side) — connects each profile point's
	# upper vertex to a bottom-rocker vertex. Smooth-shaded for curved look.
	var rocker_z_front: float = (profile[0] as Vector2).x
	var rocker_z_back: float = (profile[profile.size() - 1] as Vector2).x
	# Bottom rectangle vertices (for left/right rockers)
	var b_fr_r := Vector3( half_w_full, bottom_y, rocker_z_front)
	var b_fr_l := Vector3(-half_w_full, bottom_y, rocker_z_front)
	var b_bk_r := Vector3( half_w_full, bottom_y, rocker_z_back)
	var b_bk_l := Vector3(-half_w_full, bottom_y, rocker_z_back)

	for i in profile.size() - 1:
		var p_i: Vector3 = pts_pos[i][1]      # +X side this profile point
		var p_j: Vector3 = pts_pos[i + 1][1]  # +X side next profile point
		var b_i: Vector3 = Vector3(half_w_full, bottom_y, profile[i].x)
		var b_j: Vector3 = Vector3(half_w_full, bottom_y, profile[i + 1].x)
		# Right side panel quad
		var n_r := Vector3(1.0, 0.0, 0.0)
		sf.set_normal(n_r); sf.add_vertex(b_i)
		sf.set_normal(n_r); sf.add_vertex(p_i)
		sf.set_normal(n_r); sf.add_vertex(p_j)
		sf.set_normal(n_r); sf.add_vertex(b_i)
		sf.set_normal(n_r); sf.add_vertex(p_j)
		sf.set_normal(n_r); sf.add_vertex(b_j)
		# Left side panel quad (mirrored)
		var l_i: Vector3 = pts_pos[i][0]
		var l_j: Vector3 = pts_pos[i + 1][0]
		var bl_i: Vector3 = Vector3(-half_w_full, bottom_y, profile[i].x)
		var bl_j: Vector3 = Vector3(-half_w_full, bottom_y, profile[i + 1].x)
		var n_l := Vector3(-1.0, 0.0, 0.0)
		sf.set_normal(n_l); sf.add_vertex(bl_i)
		sf.set_normal(n_l); sf.add_vertex(l_j)
		sf.set_normal(n_l); sf.add_vertex(l_i)
		sf.set_normal(n_l); sf.add_vertex(bl_i)
		sf.set_normal(n_l); sf.add_vertex(bl_j)
		sf.set_normal(n_l); sf.add_vertex(l_j)

	# 3) Bottom rectangle (floor — usually unseen but closes the shell)
	var n_dn := Vector3(0.0, -1.0, 0.0)
	sf.set_normal(n_dn); sf.add_vertex(b_fr_r)
	sf.set_normal(n_dn); sf.add_vertex(b_bk_r)
	sf.set_normal(n_dn); sf.add_vertex(b_bk_l)
	sf.set_normal(n_dn); sf.add_vertex(b_fr_r)
	sf.set_normal(n_dn); sf.add_vertex(b_bk_l)
	sf.set_normal(n_dn); sf.add_vertex(b_fr_l)

	# 4) Front bumper end-cap and rear bumper end-cap (fill in the ends so
	# you can't see inside the hollow car from the front/rear).
	var p_front: Vector3 = pts_pos[0][1]
	var p_back: Vector3 = pts_pos[profile.size() - 1][1]
	var n_fwd := Vector3(0.0, 0.0, 1.0)
	sf.set_normal(n_fwd); sf.add_vertex(b_fr_l)
	sf.set_normal(n_fwd); sf.add_vertex(b_fr_r)
	sf.set_normal(n_fwd); sf.add_vertex(p_front)
	sf.set_normal(n_fwd); sf.add_vertex(b_fr_l)
	sf.set_normal(n_fwd); sf.add_vertex(p_front)
	sf.set_normal(n_fwd); sf.add_vertex(pts_pos[0][0])

	var n_bk := Vector3(0.0, 0.0, -1.0)
	sf.set_normal(n_bk); sf.add_vertex(b_bk_r)
	sf.set_normal(n_bk); sf.add_vertex(b_bk_l)
	sf.set_normal(n_bk); sf.add_vertex(pts_pos[profile.size() - 1][0])
	sf.set_normal(n_bk); sf.add_vertex(b_bk_r)
	sf.set_normal(n_bk); sf.add_vertex(pts_pos[profile.size() - 1][0])
	sf.set_normal(n_bk); sf.add_vertex(p_back)

	sf.generate_normals()
	var mesh := sf.commit()
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return mi


# Curved wheel arch — a half-cylinder above the wheel that visually contains
# the tire in a fender, replacing the old flat dark rectangle.
static func _make_wheel_arch_mesh(mat: Material) -> MeshInstance3D:
	var sf := SurfaceTool.new()
	sf.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r_in := WHEEL_RADIUS + 0.06
	var r_out := WHEEL_RADIUS + 0.16
	var width := WHEEL_WIDTH + 0.10
	var segs := 9
	for i in segs:
		var t0 := lerpf(0.0, PI, float(i) / float(segs))
		var t1 := lerpf(0.0, PI, float(i + 1) / float(segs))
		# Inner ring (wheel-facing, dark fender lip)
		var p_in_0 := Vector3(0, sin(t0) * r_in, cos(t0) * r_in)
		var p_in_1 := Vector3(0, sin(t1) * r_in, cos(t1) * r_in)
		# Outer ring (slightly farther out — gives the arch some thickness
		# so it reads as a 3D part instead of a paper-thin curve)
		var p_out_0 := Vector3(0, sin(t0) * r_out, cos(t0) * r_out)
		var p_out_1 := Vector3(0, sin(t1) * r_out, cos(t1) * r_out)
		# Width offsets
		var w := width * 0.5
		# Front face (positive X half)
		var n := -Vector3(0, sin((t0 + t1) * 0.5), cos((t0 + t1) * 0.5))
		sf.set_normal(n); sf.add_vertex(p_in_0  + Vector3( w, 0, 0))
		sf.set_normal(n); sf.add_vertex(p_in_1  + Vector3( w, 0, 0))
		sf.set_normal(n); sf.add_vertex(p_out_1 + Vector3( w, 0, 0))
		sf.set_normal(n); sf.add_vertex(p_in_0  + Vector3( w, 0, 0))
		sf.set_normal(n); sf.add_vertex(p_out_1 + Vector3( w, 0, 0))
		sf.set_normal(n); sf.add_vertex(p_out_0 + Vector3( w, 0, 0))
	sf.generate_normals()
	var mesh := sf.commit()
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


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

	# Tire — torus
	var tire_mesh := TorusMesh.new()
	tire_mesh.inner_radius = WHEEL_RADIUS - 0.09
	tire_mesh.outer_radius = WHEEL_RADIUS
	tire_mesh.ring_segments = 20
	tire_mesh.rings = 14
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
	rim_mesh.radial_segments = 22
	var rim := MeshInstance3D.new()
	rim.name = "Rim"
	rim.mesh = rim_mesh
	rim.material_override = chrome
	rim.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	mount.add_child(rim)

	# Hub cap with 5-spoke detail
	for i in 5:
		var spoke := MeshInstance3D.new()
		var spm := BoxMesh.new()
		spm.size = Vector3(WHEEL_WIDTH * 0.32, WHEEL_RADIUS * 0.40, 0.022)
		spoke.mesh = spm
		spoke.material_override = chrome
		spoke.rotation_degrees = Vector3(0.0, 0.0, float(i) * 72.0)
		spoke.position = Vector3(0.0, 0.0, 0.0)
		mount.add_child(spoke)

	# Hub centre
	var hub_mesh := CylinderMesh.new()
	hub_mesh.top_radius = WHEEL_RADIUS * 0.20
	hub_mesh.bottom_radius = WHEEL_RADIUS * 0.20
	hub_mesh.height = 0.05
	hub_mesh.radial_segments = 18
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
	m.set_shader_parameter("wetness", 0.62)
	m.set_shader_parameter("dirt_amount", dirt)
	m.set_shader_parameter("rust_amount", rust)
	m.set_shader_parameter("metallic", 0.72)
	m.set_shader_parameter("roughness_base", 0.32)
	return m


static func _make_glass_mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _GLASS_SHADER
	m.set_shader_parameter("glass_tint", Color(0.10, 0.14, 0.20, 0.52))
	m.set_shader_parameter("rain_streaks", 0.78)
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
	m.albedo_color = Color(0.62, 0.62, 0.65)
	m.metallic = 0.92
	m.roughness = 0.18
	m.metallic_specular = 0.85
	return m


static func _make_black_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.04, 0.04, 0.045)
	m.roughness = 0.90
	m.metallic = 0.0
	return m
