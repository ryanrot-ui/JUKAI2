extends Node3D
## A real hanging corpse — not the existing ghost-shader HangingSpirit. A man
## who killed himself in the forest, suspended by a rope around his neck from
## a tree branch overhead. A suicide note rests on the ground in front of him.
##
## Encounter flow:
##   1. Player approaches → unsettling whispers begin within 10 m.
##   2. Player interacts with the note → it can be read in the standard
##      note-reader UI.
##   3. The MOMENT the note is collected:
##        - An aggressive Yurei materializes RIGHT AT the corpse.
##        - The "走れ！" (RUN) subtitle fires.
##        - A heavy proximity-based sanity drain kicks in (up to 9 sanity/sec
##          at point-blank, scaling down past 18 m).
##   4. Player must put distance between themselves and the corpse. Once
##      they have stayed past SAFE_DISTANCE for ESCAPE_HOLD seconds the
##      encounter resolves: Yurei dissipates, drain stops.
##   5. Failure mode: sanity hits zero and Player.die() fires.

@export var corpse_id: int = 0
@export var hang_height: float = 4.2      # tree branch height above ground

const NOTE_DATA = {
	"title_jp": "遺書 — さゆり",
	"title_en": "Suicide Note — Sayuri",
	"text_jp": "「もう疲れました。\n誰も私の声を聞いてくれなかった。\n森が私を呼んでいる。\nここで終わらせます。」",
	"text_en": "'I am so tired.\nNo one would listen to me.\nThe forest has been calling.\nLet it end here.'",
}

const PROXIMITY_RANGE   := 18.0   # within this — heavy sanity drain
const POINT_BLANK_RANGE :=  4.0   # within this — maximum drain
const MAX_DRAIN_PER_SEC := 9.0
const SAFE_DISTANCE     := 28.0   # stay past this for ESCAPE_HOLD to win
const ESCAPE_HOLD       :=  3.0
const ENCOUNTER_TIMEOUT := 90.0   # absolute cap so the ghost doesn't haunt forever
const WHISPER_RANGE     := 14.0   # ambient whispers trigger inside this

const _YUREI_SCENE := preload("res://scenes/entities/YureiEntity.tscn")

var _note_collected: bool = false
var _encounter_active: bool = false
var _encounter_t: float = 0.0
var _escape_t: float = 0.0
var _whisper_t: float = 0.0
var _spawned_yurei: Node = null
var _prompt: Label3D
var _area: Area3D
var _note_collider: StaticBody3D
var _player_in_range: bool = false


func _ready() -> void:
	add_to_group("interactable")
	add_to_group("hanging_corpse")
	_build_corpse()
	_build_note_collider()
	_build_prompt()
	_build_area()
	_build_atmosphere()


# Cold moonlight column + drifting dust motes around the body. Makes the
# corpse visible at a distance through the trees and gives the area a
# distinct "wrong" feeling without needing a unique shader.
func _build_atmosphere() -> void:
	# Cold blue light from above — like a single moonlit shaft picking out
	# the body. Tightly ranged so it doesn't bleed into the surroundings.
	var moonlight := OmniLight3D.new()
	moonlight.position = Vector3(0, 3.6, 0)
	moonlight.light_color = Color(0.50, 0.62, 0.85)
	moonlight.light_energy = 1.85
	moonlight.omni_range = 5.2
	moonlight.shadow_enabled = false
	add_child(moonlight)

	# Drifting dust motes — sparse upward float, just visible in the moonlight
	var dust := CPUParticles3D.new()
	dust.amount = 22
	dust.lifetime = 6.5
	dust.emitting = true
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	dust.emission_box_extents = Vector3(1.4, 1.6, 1.4)
	dust.position = Vector3(0, 1.4, 0)
	dust.direction = Vector3(0, 1, 0)
	dust.spread = 18.0
	dust.initial_velocity_min = 0.04
	dust.initial_velocity_max = 0.10
	dust.gravity = Vector3(0, 0.0, 0)
	dust.scale_amount_min = 0.4
	dust.scale_amount_max = 1.1
	var dust_mat := StandardMaterial3D.new()
	dust_mat.albedo_color = Color(0.85, 0.90, 1.0, 0.28)
	dust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	var dust_mesh := QuadMesh.new()
	dust_mesh.size = Vector2(0.04, 0.04)
	dust_mesh.material = dust_mat
	dust.mesh = dust_mesh
	add_child(dust)


func _process(delta: float) -> void:
	if GameManager.state != GameManager.GameState.PLAYING:
		return
	if not GameManager.player_ref:
		return

	# Ambient whispers when the player is in proximity (before pickup)
	if not _note_collected:
		var dist_pre := global_position.distance_to(GameManager.player_ref.global_position)
		if dist_pre <= WHISPER_RANGE:
			_whisper_t += delta
			if _whisper_t >= 8.0:
				_whisper_t = 0.0
				AudioManager.play_whisper()
		return

	# Encounter loop — only runs after the note has been collected.
	if not _encounter_active:
		return
	_encounter_t += delta
	var dist := global_position.distance_to(GameManager.player_ref.global_position)

	# Sanity drain — scales from MAX_DRAIN_PER_SEC at point-blank down to 0
	# at PROXIMITY_RANGE. Past PROXIMITY_RANGE, no drain (player is escaping).
	if dist <= PROXIMITY_RANGE and GameManager.sanity_ref:
		var t: float = 1.0 - smoothstep(POINT_BLANK_RANGE, PROXIMITY_RANGE, dist)
		var drain: float = MAX_DRAIN_PER_SEC * t
		GameManager.sanity_ref.drain(drain * delta)

	# Escape detection: stay past SAFE_DISTANCE for ESCAPE_HOLD seconds.
	if dist >= SAFE_DISTANCE:
		_escape_t += delta
		if _escape_t >= ESCAPE_HOLD:
			_resolve_encounter()
			return
	else:
		_escape_t = 0.0

	# Hard timeout — release the player even if they're huddled in range
	if _encounter_t >= ENCOUNTER_TIMEOUT:
		_resolve_encounter()


# Called by the player's interact ray on the note collider.
func interact(_player: CharacterBody3D) -> void:
	if _note_collected:
		return
	_note_collected = true
	_prompt.visible = false
	AudioManager.play_sfx("note_pickup")
	if GameManager.ui_ref and GameManager.ui_ref.has_method("show_note"):
		# show_note awaits — when it returns the player has dismissed the
		# note reader. THAT is the moment the encounter should start, so the
		# yurei doesn't materialize while the reader UI is on screen.
		await GameManager.ui_ref.show_note(NOTE_DATA)
	_start_encounter()


func _start_encounter() -> void:
	if _encounter_active:
		return
	_encounter_active = true
	_encounter_t = 0.0
	_escape_t = 0.0
	# Spawn the yurei right at the corpse position and force it into pursuit.
	_spawned_yurei = _YUREI_SCENE.instantiate()
	_spawned_yurei.name = "Yurei_FromCorpse_%d" % corpse_id
	_spawned_yurei.position = global_position
	get_parent().add_child(_spawned_yurei)
	# Make it visible + chase the player. activate() puts it in IDLE_DISTANT;
	# we then poke it into CRAWLING so it pursues immediately instead of
	# waiting for the player to wander within 6 m.
	if _spawned_yurei.has_method("activate"):
		_spawned_yurei.activate()
		_spawned_yurei.state = _spawned_yurei.State.CRAWLING
	AudioManager.play_ghost_sound("yurei_shriek")
	AudioManager.play_ghost_sound("hair_drag")
	JumpscareSystem.trigger(JumpscareSystem.Intensity.HARD)
	# UI alert — "RUN!"
	if GameManager.ui_ref and GameManager.ui_ref.has_method("show_subtitle"):
		GameManager.ui_ref.show_subtitle("走れ！ / RUN — DON'T LOOK BACK", 4.0)


func _resolve_encounter() -> void:
	_encounter_active = false
	# Dissipate the yurei — bleed it out instead of popping it
	if is_instance_valid(_spawned_yurei):
		if _spawned_yurei.has_method("_vanish"):
			_spawned_yurei._vanish()
		else:
			_spawned_yurei.queue_free()
	_spawned_yurei = null
	if GameManager.ui_ref and GameManager.ui_ref.has_method("show_subtitle"):
		GameManager.ui_ref.show_subtitle(
			"距離が離れた… 心が落ち着く / The presence fades.", 3.0)


# ─── Corpse mesh ──────────────────────────────────────────────────────────────
# Hand-built humanoid out of primitives. Pale dead skin, head tilted, noose
# around the neck, rope running up to the hanging point. Distinct from the
# translucent ghost-shader HangingSpirit — this is a body.

func _build_corpse() -> void:
	# Female hanging victim — matches the existing Hanako / yurei narrative.
	# Pale dead skin, long flowing dark hair, long simple white kimono /
	# burial dress. Head tilted to the side from the broken neck. The yurei
	# she becomes when the note is read shares this silhouette deliberately:
	# "this corpse stood up and started walking".
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.74, 0.70, 0.66)   # death pallor
	skin.roughness = 0.92
	skin.metallic_specular = 0.05

	var kimono_mat := StandardMaterial3D.new()
	kimono_mat.albedo_color = Color(0.72, 0.70, 0.66)   # soiled white
	kimono_mat.roughness = 0.95

	var sash_mat := StandardMaterial3D.new()
	sash_mat.albedo_color = Color(0.42, 0.10, 0.10)     # dark red obi
	sash_mat.roughness = 0.88

	var rope_mat := StandardMaterial3D.new()
	rope_mat.albedo_color = Color(0.42, 0.32, 0.20)
	rope_mat.roughness = 1.0

	var dark_mat := StandardMaterial3D.new()
	dark_mat.albedo_color = Color(0.04, 0.04, 0.05)
	dark_mat.roughness = 0.95

	var hair_mat := StandardMaterial3D.new()
	hair_mat.albedo_color = Color(0.05, 0.03, 0.04)
	hair_mat.roughness = 0.94

	# Feet at y=0.65, head/neck at y=2.45, branch at y=hang_height
	var foot_y := 0.65
	var neck_y := 2.30
	var head_y := 2.50

	# Rope from branch down to noose
	var rope := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 0.022
	rm.bottom_radius = 0.022
	rm.height = hang_height - neck_y
	rope.mesh = rm
	rope.position = Vector3(0, (hang_height + neck_y) * 0.5, 0)
	rope.material_override = rope_mat
	add_child(rope)

	# Noose loop — torus around the throat
	var noose := MeshInstance3D.new()
	var nm := TorusMesh.new()
	nm.inner_radius = 0.10
	nm.outer_radius = 0.14
	nm.ring_segments = 12
	nm.rings = 16
	noose.mesh = nm
	noose.position = Vector3(0, neck_y + 0.05, 0)
	noose.material_override = rope_mat
	add_child(noose)

	# Neck — slim, slightly stretched from the hanging
	var neck := MeshInstance3D.new()
	var nkm := CylinderMesh.new()
	nkm.top_radius = 0.055
	nkm.bottom_radius = 0.075
	nkm.height = 0.22
	neck.mesh = nkm
	neck.position = Vector3(0, neck_y, 0)
	neck.material_override = skin
	add_child(neck)

	# Head — pale, tilted to the side
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.15
	hm.height = 0.30
	head.mesh = hm
	head.position = Vector3(0.06, head_y, 0.03)
	head.rotation_degrees = Vector3(6.0, 14.0, 24.0)
	head.material_override = skin
	add_child(head)

	# Long flowing dark hair — back of head, draping down to mid-back.
	# Built as two pieces: a cap above the head and a long curtain behind.
	var hair_top := MeshInstance3D.new()
	var hair_top_m := SphereMesh.new()
	hair_top_m.radius = 0.155
	hair_top_m.height = 0.24
	hair_top.mesh = hair_top_m
	hair_top.position = Vector3(0.06, head_y + 0.04, 0.0)
	hair_top.rotation_degrees = head.rotation_degrees
	hair_top.material_override = hair_mat
	add_child(hair_top)

	var hair_long := MeshInstance3D.new()
	var hair_long_m := CapsuleMesh.new()
	hair_long_m.radius = 0.17
	hair_long_m.height = 1.15
	hair_long.mesh = hair_long_m
	hair_long.position = Vector3(0.04, head_y - 0.55, -0.10)
	hair_long.rotation_degrees = Vector3(0, 0, 6.0)
	hair_long.material_override = hair_mat
	add_child(hair_long)

	# Hair front curtain — partially covers the face (classic yurei look)
	var hair_front := MeshInstance3D.new()
	var hfm := BoxMesh.new()
	hfm.size = Vector3(0.28, 0.34, 0.03)
	hair_front.mesh = hfm
	hair_front.position = Vector3(0.06, head_y - 0.04, 0.14)
	hair_front.rotation_degrees = head.rotation_degrees
	hair_front.material_override = hair_mat
	add_child(hair_front)

	# Slack open mouth — barely visible under the hair curtain
	var mouth := MeshInstance3D.new()
	var mm := BoxMesh.new()
	mm.size = Vector3(0.05, 0.04, 0.018)
	mouth.mesh = mm
	mouth.position = Vector3(0.065, head_y - 0.10, 0.16)
	mouth.rotation_degrees = head.rotation_degrees
	mouth.material_override = dark_mat
	add_child(mouth)

	# Torso — narrower than male, wearing the kimono top
	var torso := MeshInstance3D.new()
	var tm := CapsuleMesh.new()
	tm.radius = 0.20
	tm.height = 0.75
	torso.mesh = tm
	torso.position = Vector3(0, 1.78, 0)
	torso.material_override = kimono_mat
	add_child(torso)

	# Dark-red obi (sash) around the waist
	var obi := MeshInstance3D.new()
	var obim := CylinderMesh.new()
	obim.top_radius = 0.22
	obim.bottom_radius = 0.22
	obim.height = 0.16
	obi.mesh = obim
	obi.position = Vector3(0, 1.40, 0)
	obi.material_override = sash_mat
	add_child(obi)

	# Long kimono skirt — single flowing piece down to the feet
	var skirt := MeshInstance3D.new()
	var skm := CylinderMesh.new()
	skm.top_radius = 0.20
	skm.bottom_radius = 0.34
	skm.height = 0.92
	skm.radial_segments = 16
	skirt.mesh = skm
	skirt.position = Vector3(0, 0.88, 0)
	skirt.material_override = kimono_mat
	add_child(skirt)

	# Arms — slim, hanging at sides with sleeves
	for side: float in [-1.0, 1.0]:
		var shoulder_x := side * 0.18
		var arm_upper := MeshInstance3D.new()
		var aum := CapsuleMesh.new()
		aum.radius = 0.062
		aum.height = 0.46
		arm_upper.mesh = aum
		arm_upper.position = Vector3(shoulder_x, 1.78, 0)
		arm_upper.material_override = kimono_mat
		add_child(arm_upper)

		var arm_lower := MeshInstance3D.new()
		var alm := CapsuleMesh.new()
		alm.radius = 0.052
		alm.height = 0.44
		arm_lower.mesh = alm
		arm_lower.position = Vector3(shoulder_x, 1.30, 0.02)
		arm_lower.material_override = skin
		add_child(arm_lower)

		# Pale hand at the end of the sleeve — slightly curled
		var hand := MeshInstance3D.new()
		var hand_m := SphereMesh.new()
		hand_m.radius = 0.048
		hand_m.height = 0.096
		hand.mesh = hand_m
		hand.position = Vector3(shoulder_x, 1.07, 0.02)
		hand.material_override = skin
		add_child(hand)

	# Bare pale feet poking out under the kimono hem
	for side: float in [-1.0, 1.0]:
		var foot := MeshInstance3D.new()
		var fm := SphereMesh.new()
		fm.radius = 0.058
		fm.height = 0.10
		foot.mesh = fm
		foot.position = Vector3(side * 0.10, foot_y, 0.05)
		foot.material_override = skin
		add_child(foot)

	# Memorial pebbles at the foot of the body — visitors / mourners
	# scattered them. Small touch of in-world history.
	var pebble_mat := StandardMaterial3D.new()
	pebble_mat.albedo_color = Color(0.36, 0.36, 0.38)
	pebble_mat.roughness = 0.94
	for i in 5:
		var pebble := MeshInstance3D.new()
		var pem := SphereMesh.new()
		var r := 0.04 + (i % 3) * 0.012
		pem.radius = r
		pem.height = r * 2.0
		pebble.mesh = pem
		var angle := float(i) * 1.35
		pebble.position = Vector3(cos(angle) * 0.45, 0.05, sin(angle) * 0.45 - 0.6)
		pebble.material_override = pebble_mat
		add_child(pebble)

	_start_sway()


func _start_sway() -> void:
	# Plays forever, paused with the tree. process_mode default is INHERIT so
	# it stops when the scene pauses.
	var tw := create_tween().set_loops()
	tw.tween_property(self, "rotation:z", deg_to_rad( 1.4), 3.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "rotation:z", deg_to_rad(-1.4), 3.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# ─── Note collider (so the InteractRay can hit the note) ─────────────────────

func _build_note_collider() -> void:
	# The note sits on the ground in front of the body so the player can
	# kneel/look down and press [E]. It uses ITS OWN StaticBody3D on collision
	# layer 4 (the interactable layer the player's ray casts against), but
	# delegates interact() to THIS HangingCorpse so we know when it's read.
	_note_collider = StaticBody3D.new()
	_note_collider.collision_layer = 4
	_note_collider.collision_mask = 0
	_note_collider.position = Vector3(0.6, 0.15, 0.5)
	# Box collider for the InteractRay
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.3, 0.3, 0.3)
	col.shape = box
	_note_collider.add_child(col)
	# Visible note — folded paper
	var paper := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.22, 0.006, 0.16)
	paper.mesh = pm
	var paper_mat := StandardMaterial3D.new()
	paper_mat.albedo_color = Color(0.78, 0.74, 0.62)
	paper_mat.roughness = 0.95
	paper_mat.emission_enabled = true
	paper_mat.emission = Color(0.45, 0.36, 0.20)
	paper_mat.emission_energy_multiplier = 0.18
	paper.material_override = paper_mat
	paper.rotation_degrees.x = -6.0
	_note_collider.add_child(paper)
	# Soft glow light so the note is visible in dark forest
	var light := OmniLight3D.new()
	light.position = Vector3(0, 0.3, 0)
	light.light_color = Color(0.92, 0.82, 0.55)
	light.light_energy = 0.45
	light.omni_range = 1.8
	light.shadow_enabled = false
	_note_collider.add_child(light)
	# Forward interact() to the corpse so we control the encounter sequence.
	_note_collider.set_script(_make_forwarder_script())
	_note_collider.set("_target", self)
	add_child(_note_collider)


# Generates a tiny inline script for the note's StaticBody3D that forwards
# the player's interact() call to this HangingCorpse.
func _make_forwarder_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = """
extends StaticBody3D
var _target: Node = null
func interact(player: CharacterBody3D) -> void:
	if _target and _target.has_method(\"interact\"):
		_target.interact(player)
"""
	script.reload()
	return script


# ─── Proximity prompt ────────────────────────────────────────────────────────

func _build_prompt() -> void:
	_prompt = Label3D.new()
	_prompt.position = Vector3(0.6, 0.55, 0.5)
	_prompt.pixel_size = 0.0035
	_prompt.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt.text = "[E] 遺書を拾う — Read note"
	_prompt.font_size = 22
	_prompt.modulate = Color(0.95, 0.88, 0.65)
	_prompt.visible = false
	add_child(_prompt)


func _build_area() -> void:
	# 2.2 m sphere — when the player is close enough to read the note,
	# show the prompt. Doesn't trigger anything itself.
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 1
	var sphere := SphereShape3D.new()
	sphere.radius = 2.2
	var col := CollisionShape3D.new()
	col.shape = sphere
	col.position = Vector3(0.6, 0.5, 0.5)
	area.add_child(col)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	add_child(area)
	_area = area


func _on_body_entered(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	_player_in_range = true
	if not _note_collected:
		_prompt.visible = true


func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_in_range = false
		_prompt.visible = false
