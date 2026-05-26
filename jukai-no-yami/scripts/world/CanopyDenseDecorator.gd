extends Node3D
## CanopyDenseDecorator — drops dense overlapping canopy silhouettes along
## a path corridor so the sky stops reading as empty void above the trees.
##
## Drop this script onto a Node3D in your scene, set the @export tunables
## in the Inspector (path_center_z, path_length, side_offset, density),
## then play. _ready() runs a generation loop that for each step along
## the path spawns:
##
##   • a central dark CylinderMesh (trunk)
##   • 3 to 5 flattened, offset SphereMeshes + PrismMeshes overhead
##     forming a chunky overlapping canopy block
##
## Doesn't touch the existing TreeSpawner / path arrays. Pure decoration.

# Path geometry — match these to your level's _add_guided_trail() call.
@export var path_center_z: float = -40.0
@export var path_length: float = 100.0

# Distance from the path's centre line to start spawning canopies (so we
# don't put trees on the path itself). 4.0 = leaves a 4 m clearing on
# each side of the trail before trees start.
@export var side_offset: float = 4.0

# Width of the canopy strip on each side. 12.0 means the script populates
# from side_offset (4 m) to side_offset + canopy_band (16 m) on each side.
@export var canopy_band: float = 12.0

# Trees per linear metre along the path. 0.85 = roughly one tree every
# 1.2 m on each side. Higher = denser canopy, lower = sparser.
@export_range(0.20, 2.50, 0.05) var density: float = 0.85

# Seed for reproducible layouts. Change this to get a different forest.
@export var random_seed: int = 9117


func _ready() -> void:
	_build_canopy_strip()


func _build_canopy_strip() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed

	# Shared materials — dark cool greys so the canopy reads as silhouette
	# against the night sky. Built once, reused on every mesh.
	var trunk_mat := StandardMaterial3D.new()
	trunk_mat.albedo_color = Color(0.05, 0.04, 0.04)
	trunk_mat.roughness = 1.0
	trunk_mat.metallic = 0.0

	var canopy_mat := StandardMaterial3D.new()
	canopy_mat.albedo_color = Color(0.06, 0.07, 0.05)
	canopy_mat.roughness = 1.0
	canopy_mat.metallic = 0.0

	# Step along Z. spacing = inverse of density (one tree every 1/density
	# metres) but jittered per-step so the row doesn't read as a hedge.
	var spacing: float = 1.0 / density
	var z_start: float = path_center_z + path_length * 0.5
	var z_end: float = path_center_z - path_length * 0.5
	var z: float = z_start
	while z >= z_end:
		# Both sides of the path
		for side: float in [-1.0, 1.0]:
			# Random X offset in the canopy strip band
			var x: float = side * (side_offset + rng.randf_range(0.0, canopy_band))
			# Small jitter on Z so trees don't line up like fence posts
			var jz: float = rng.randf_range(-spacing * 0.4, spacing * 0.4)
			var pos: Vector3 = Vector3(x, 0.0, z + jz)
			_spawn_tree_with_canopy(pos, rng, trunk_mat, canopy_mat)
		# Advance one spacing step with small jitter so adjacent rows
		# aren't perfectly aligned across the path.
		z -= spacing + rng.randf_range(-spacing * 0.25, spacing * 0.25)


# Build a single tree: one trunk cylinder + 3 to 5 overlapping canopy
# primitives (mix of flattened spheres and tilted prisms) at the top.
func _spawn_tree_with_canopy(pos: Vector3, rng: RandomNumberGenerator,
		trunk_mat: Material, canopy_mat: Material) -> void:
	# Trunk — narrow tall dark cylinder. Random height/radius gives the
	# silhouette variety.
	var trunk_height: float = rng.randf_range(3.6, 5.6)
	var trunk_radius: float = rng.randf_range(0.10, 0.20)
	var trunk := MeshInstance3D.new()
	var tcm := CylinderMesh.new()
	tcm.top_radius = trunk_radius * 0.70
	tcm.bottom_radius = trunk_radius
	tcm.height = trunk_height
	tcm.radial_segments = 8
	trunk.mesh = tcm
	trunk.position = pos + Vector3(0.0, trunk_height * 0.5, 0.0)
	# Slight random lean so the column doesn't read as a flagpole
	trunk.rotation_degrees = Vector3(
		rng.randf_range(-2.5, 2.5),
		rng.randf_range(0.0, 360.0),
		rng.randf_range(-2.5, 2.5))
	trunk.material_override = trunk_mat
	trunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(trunk)

	# Canopy — 3..5 overlapping primitives at the top of the trunk
	var canopy_root: Vector3 = pos + Vector3(0.0, trunk_height + 0.10, 0.0)
	var blob_count: int = rng.randi_range(3, 5)
	for i in blob_count:
		# Alternate between flattened spheres and tilted prisms so the
		# silhouette has hard angled facets AND soft rounded clumps.
		var use_prism: bool = rng.randf() > 0.55
		var offset: Vector3 = Vector3(
			rng.randf_range(-0.85, 0.85),
			rng.randf_range(-0.30, 0.55),
			rng.randf_range(-0.85, 0.85))
		var mi := MeshInstance3D.new()
		mi.position = canopy_root + offset
		mi.material_override = canopy_mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if use_prism:
			var pm := PrismMesh.new()
			pm.size = Vector3(
				rng.randf_range(1.6, 2.4),
				rng.randf_range(1.0, 1.8),
				rng.randf_range(1.6, 2.4))
			pm.left_to_right = rng.randf_range(0.3, 0.7)
			mi.mesh = pm
			mi.rotation_degrees = Vector3(
				rng.randf_range(-25.0, 25.0),
				rng.randf_range(0.0, 360.0),
				rng.randf_range(-25.0, 25.0))
		else:
			var sm := SphereMesh.new()
			sm.radius = rng.randf_range(0.95, 1.45)
			sm.height = sm.radius * rng.randf_range(0.95, 1.55)
			sm.radial_segments = 10
			sm.rings = 6
			mi.mesh = sm
			# Flatten the sphere vertically to look like canopy mass,
			# not a hovering ball.
			mi.scale = Vector3(
				rng.randf_range(1.0, 1.4),
				rng.randf_range(0.55, 0.85),
				rng.randf_range(1.0, 1.4))
			mi.rotation_degrees.y = rng.randf_range(0.0, 360.0)
		add_child(mi)
