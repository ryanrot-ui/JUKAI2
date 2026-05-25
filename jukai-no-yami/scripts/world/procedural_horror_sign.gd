extends Node3D
## Self-contained procedural horror warning sign.
##
## Usage:
##   1. Create a Node3D in your scene where the sign should go.
##   2. Attach this script.
##   3. Optionally set warning_text_jp / warning_text_en in the Inspector.
##   4. Done — _ready() builds the sign and snaps it to the ground.
##
## Construction:
##   • Post:  tall thin CylinderMesh, dark ash-grey
##   • Board: wide flat BoxMesh, slightly darker shade
##   • Text:  Label3D fixed to the board face. Off-white painted lettering
##            with a dark outline so it reads as physical paint, not UI.
##
## A downward PhysicsRayQueryParameters3D snaps the post bottom to the
## ground collision body so it never floats or buries.

@export var post_height: float = 2.2
@export var post_radius: float = 0.06
@export var board_size: Vector2 = Vector2(1.30, 0.70)
@export var board_thickness: float = 0.05
@export var board_height: float = 1.95   # centre Y of the board above the post base
@export var yaw_deg: float = 0.0

# Sign text. Default is the Aokigahara-style warning.
@export_multiline var warning_text_jp: String = "樹海への立入注意"
@export_multiline var warning_text_en: String = "Suicide Forest — Enter at your own risk"

# Material colours
@export var post_color: Color = Color(0.22, 0.20, 0.18)
@export var board_color: Color = Color(0.18, 0.13, 0.08)
@export var text_color: Color = Color(0.82, 0.76, 0.62)
@export var text_outline_color: Color = Color(0.02, 0.02, 0.02, 0.85)

var _root_body: StaticBody3D


func _ready() -> void:
	rotation_degrees.y = yaw_deg
	_build_assembly()
	call_deferred("_snap_to_ground")


func _build_assembly() -> void:
	# Single StaticBody3D parent for collision + visual. Layer 4 = same as
	# other interactable props.
	_root_body = StaticBody3D.new()
	_root_body.collision_layer = 4
	add_child(_root_body)

	# Materials — flat ash-grey post, slightly darker stained board.
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = post_color
	post_mat.roughness = 0.96
	post_mat.metallic = 0.0

	var board_mat := StandardMaterial3D.new()
	board_mat.albedo_color = board_color
	board_mat.roughness = 0.98
	board_mat.metallic_specular = 0.02

	# ── Post (vertical cylinder) ───────────────────────────────────────────
	var post := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.height = post_height
	pm.top_radius = post_radius * 0.85
	pm.bottom_radius = post_radius
	pm.radial_segments = 14
	post.mesh = pm
	post.material_override = post_mat
	post.position = Vector3(0, post_height * 0.5, 0)
	_root_body.add_child(post)

	# Post collision (thin cylinder so player can't walk through it)
	var post_col := CollisionShape3D.new()
	var pcs := CylinderShape3D.new()
	pcs.radius = post_radius
	pcs.height = post_height
	post_col.shape = pcs
	post_col.position = Vector3(0, post_height * 0.5, 0)
	_root_body.add_child(post_col)

	# ── Board (flat box at the top of the post) ────────────────────────────
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(board_size.x, board_size.y, board_thickness)
	board.mesh = bm
	board.material_override = board_mat
	board.position = Vector3(0, board_height, 0)
	board.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_root_body.add_child(board)

	# ── Text label on the front face ───────────────────────────────────────
	# Pixel size is tuned for the default board_size; text sits at z =
	# +half-thickness + 0.002 so it doesn't z-fight with the board face.
	var face_z := board_thickness * 0.5 + 0.002
	var label := Label3D.new()
	var text := warning_text_jp
	if not warning_text_en.is_empty():
		text = "%s\n%s" % [warning_text_jp, warning_text_en]
	label.text = text
	label.position = Vector3(0, 0, face_z)
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.font_size = 14
	label.pixel_size = 0.0028
	label.modulate = text_color
	label.outline_size = 4
	label.outline_modulate = text_outline_color
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Render after the board mesh so the outline isn't culled by the board
	# face. NO_DEPTH_TEST keeps the text crisp at oblique angles.
	label.no_depth_test = true
	label.fixed_size = false
	board.add_child(label)


# Cast straight down; snap so the bottom of the post sits on the hit.
func _snap_to_ground() -> void:
	if not is_inside_tree():
		return
	var space := get_world_3d().direct_space_state
	if not space:
		return
	var origin := global_position
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(origin.x, origin.y + 50.0, origin.z),
		Vector3(origin.x, origin.y - 50.0, origin.z))
	query.collision_mask = 1
	# Exclude our own collider so the ray doesn't immediately hit the post.
	if _root_body:
		query.exclude = [_root_body.get_rid()]
	var result := space.intersect_ray(query)
	if result and result.has("position"):
		var hit: Vector3 = result["position"]
		global_position = Vector3(origin.x, hit.y, origin.z)
