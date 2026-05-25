extends StaticBody3D

const NOTE_DATA = {
	0: {
		"title_jp": "山田花子の手紙", "title_en": "Hanako Yamada's Letter",
		"text_jp": "「もう帰れない。あなたに会いたかった。\nこの森が私を呼んでいる。待っていて。」\n\n— 花子",
		"text_en": "'I cannot go back. I wanted to see you one more time.\nThis forest keeps calling my name. Wait for me.'\n\n— Hanako",
	},
	1: {
		"title_jp": "壊れた小物", "title_en": "A Broken Keepsake",
		"text_jp": "ガラスの破片。裏に書かれた文字:\n「待っていて — 帰らないで」\n誰かの指紋がまだ残っている。",
		"text_en": "Shards of glass. Scratched on the back:\n'Wait for me — don't go home.'\nSomeone's fingerprints remain.",
	},
	2: {
		"title_jp": "錆びた鍵", "title_en": "A Rusted Key",
		"text_jp": "鍵は何も開かない。\nただ、誰かがここで最後の夜を過ごした形見として、\n土に半分埋まっている。",
		"text_en": "The key opens nothing.\nIt lies half-buried in the soil —\na memorial to someone's final night here.",
	},
	3: {
		"title_jp": "最後の写真", "title_en": "The Final Photograph",
		"text_jp": "家族の写真。全員の顔に×印。\n裏面: 「ごめんね」\nインクはまだ濡れている。",
		"text_en": "A family portrait. Every face crossed out.\nOn the back: 'I'm sorry.'\nThe ink is still wet.",
	},
}

@export var note_id: int = 0
@export var trigger_ghost_on_pickup: bool = true

var _prompt: Label3D
var _light: OmniLight3D
var _area: Area3D
var _collected: bool = false
var _base_y: float = 0.0
var _bob_t: float = 0.0

func _ready() -> void:
	add_to_group("interactable")
	collision_layer = 4

	var box = BoxShape3D.new()
	box.size = Vector3(0.22, 0.28, 0.04)
	var col = CollisionShape3D.new()
	col.shape = box
	add_child(col)

	_build_note_mesh()

	_light = OmniLight3D.new()
	_light.light_color = Color(0.92, 0.82, 0.55)
	_light.light_energy = 0.35
	_light.omni_range = 2.2
	_light.shadow_enabled = false
	add_child(_light)

	_prompt = Label3D.new()
	_prompt.position = Vector3(0, 0.42, 0)
	_prompt.pixel_size = 0.0035
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.text = "[E] 拾う"
	_prompt.font_size = 22
	_prompt.modulate = Color(0.95, 0.88, 0.65)
	_prompt.visible = false
	add_child(_prompt)

	var sphere = SphereShape3D.new()
	sphere.radius = 1.4
	_area = Area3D.new()
	_area.collision_layer = 0
	_area.collision_mask = 1
	var area_col = CollisionShape3D.new()
	area_col.shape = sphere
	_area.add_child(area_col)
	add_child(_area)
	_area.body_entered.connect(_on_body_entered)
	_area.body_exited.connect(_on_body_exited)

	_base_y = position.y

	if note_id in GameManager.collected_notes:
		_collected = true
		visible = false

func _build_note_mesh() -> void:
	var paper = MeshInstance3D.new()
	var bm = BoxMesh.new()
	bm.size = Vector3(0.20, 0.004, 0.26)
	paper.mesh = bm
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.68, 0.58)
	mat.roughness = 0.92
	mat.emission_enabled = true
	mat.emission = Color(0.35, 0.30, 0.18)
	mat.emission_energy_multiplier = 0.15
	paper.material_override = mat
	paper.position = Vector3(0, 0.18, 0)
	paper.rotation_degrees.x = -8.0
	add_child(paper)

	var fold = MeshInstance3D.new()
	var fm = BoxMesh.new()
	fm.size = Vector3(0.04, 0.004, 0.26)
	fold.mesh = fm
	fold.material_override = mat
	fold.position = Vector3(0.10, 0.19, 0)
	fold.rotation_degrees.y = 12.0
	add_child(fold)

func _process(delta: float) -> void:
	if _collected:
		return
	_bob_t += delta
	position.y = _base_y + sin(_bob_t * 1.2) * 0.04
	rotation.y += delta * 0.35
	var pulse = 0.28 + abs(sin(_bob_t * 2.0)) * 0.12
	_light.light_energy = pulse

func _on_body_entered(body: Node3D) -> void:
	if _collected or not body.is_in_group("player"):
		return
	var data = NOTE_DATA.get(note_id, {})
	_prompt.text = "[E] %s" % data.get("title_jp", "拾う")
	_prompt.visible = true

func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_prompt.visible = false

func interact(_player: CharacterBody3D) -> void:
	if _collected:
		return
	_collected = true
	GameManager.collect_note(note_id)
	_prompt.visible = false
	var data = NOTE_DATA.get(note_id, {})
	if GameManager.ui_ref and GameManager.ui_ref.has_method("show_note"):
		GameManager.ui_ref.show_note(data)
	if trigger_ghost_on_pickup:
		var ghost_names = {0: "Yurei_Edge", 1: "Yurei_Ambient", 2: "HangingSpirit_Scare4", 3: "Yurei_Final"}
		var ghost_name = ghost_names.get(note_id, "")
		if not ghost_name.is_empty():
			var ghost = get_tree().get_root().find_child(ghost_name, true, false)
			if ghost and ghost.has_method("activate"):
				ghost.activate()
	await get_tree().create_timer(0.8).timeout
	visible = false
