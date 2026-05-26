extends Control

const ENDINGS = {
	"bad": {
		"title":    "悪い結末",
		"subtitle": "Bad Ending",
		"body":     "あなたは形見を集めることができなかった。\n怨霊たちはこの森に安らぎを見つけられなかった。\n\nYou could not collect the keepsakes.\nThe vengeful spirits found no peace.",
		"color":    Color(0.5, 0.1, 0.1),
	},
	"good": {
		"title":    "良い結末",
		"subtitle": "Good Ending",
		"body":     "あなたはいくつかの形見を持って森を出た。\n一部の霊魂は解放されたが、まだ残りがいる。\n\nYou escaped with some keepsakes.\nSome spirits found release — others remain.",
		"color":    Color(0.2, 0.35, 0.5),
	},
	"true": {
		"title":    "真の結末",
		"subtitle": "True Ending — 解放",
		"body":     "すべての形見が集められた。花子は、ついに安らぎを得た。\n樹海の闇は晴れ、朝の光が差し込んでくる。\n\nAll belongings collected. Hanako is at peace.\nThe darkness lifts. Dawn reaches the Sea of Trees.",
		"color":    Color(0.4, 0.6, 0.3),
	},
}

var title_lbl: Label
var subtitle_lbl: Label
var body_lbl: RichTextLabel
var stats_lbl: Label
var bg: ColorRect
var retry_btn: Button
var menu_btn: Button

func _ready() -> void:
	# CRITICAL: PROCESS_MODE_ALWAYS keeps the script + Tween running even
	# if the SceneTree got paused before transitioning here. Without it
	# the fade-in animation freezes on a black screen.
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	modulate.a = 0.0
	# Belt + braces: set both anchors AND offsets so the Control fills
	# the entire viewport on any aspect ratio. PRESET_FULL_RECT with
	# keep_offsets=false resets offsets to zero, which is what we want.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Stretch grow flags so AUTO sizing pushes outward rather than
	# collapsing into the top-left corner if a parent forgot to size us.
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical   = Control.SIZE_EXPAND_FILL

	bg = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.02, 0.01, 0.01, 1.0)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Vignette overlay darkens screen edges for cinematic depth
	var vig = ColorRect.new()
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vig_shader = Shader.new()
	vig_shader.code = "shader_type canvas_item;\nvoid fragment() {\n\tvec2 d = UV - 0.5;\n\tfloat v = smoothstep(0.22, 0.72, length(d) * 1.55);\n\tCOLOR = vec4(0.0, 0.0, 0.0, v * 0.70);\n}"
	var vig_mat = ShaderMaterial.new()
	vig_mat.shader = vig_shader
	vig.material = vig_mat
	add_child(vig)

	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(center)

	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(520, 0)
	vbox.add_theme_constant_override("separation", 16)
	vbox.modulate.a = 0.0
	center.add_child(vbox)

	title_lbl = Label.new()
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 42)
	title_lbl.add_theme_color_override("font_color", Color(0.72, 0.54, 0.23))
	vbox.add_child(title_lbl)

	subtitle_lbl = Label.new()
	subtitle_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_lbl.add_theme_font_size_override("font_size", 18)
	subtitle_lbl.add_theme_color_override("font_color", Color(0.55, 0.50, 0.42))
	vbox.add_child(subtitle_lbl)

	vbox.add_child(HSeparator.new())

	body_lbl = RichTextLabel.new()
	body_lbl.custom_minimum_size = Vector2(500, 120)
	body_lbl.bbcode_enabled = true
	body_lbl.scroll_active = false
	body_lbl.fit_content = true
	body_lbl.add_theme_font_size_override("normal_font_size", 14)
	body_lbl.visible_ratio = 0.0
	vbox.add_child(body_lbl)

	stats_lbl = Label.new()
	stats_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats_lbl.add_theme_font_size_override("font_size", 12)
	stats_lbl.add_theme_color_override("font_color", Color(0.55, 0.50, 0.42))
	stats_lbl.modulate.a = 0.0
	vbox.add_child(stats_lbl)

	vbox.add_child(HSeparator.new())

	retry_btn = _make_btn("もう一度 / Play Again")
	retry_btn.pressed.connect(GameManager.start_game)
	retry_btn.modulate.a = 0.0
	vbox.add_child(retry_btn)

	menu_btn = _make_btn("メインメニュー / Main Menu")
	menu_btn.pressed.connect(_on_menu)
	menu_btn.modulate.a = 0.0
	vbox.add_child(menu_btn)

	var key = GameManager.determine_ending()
	var data = ENDINGS.get(key, ENDINGS["bad"])
	title_lbl.text = data["title"]
	subtitle_lbl.text = data["subtitle"]
	body_lbl.bbcode_text = data["body"]
	bg.color = data["color"]
	stats_lbl.text = "形見: %d/4  |  精神力: %.0f%%" % [
		GameManager.collected_notes.size(), GameManager.player_final_sanity]

	_add_soul_particles(data["color"])
	_animate_entrance(vbox)

func _animate_entrance(vbox: VBoxContainer) -> void:
	var tw = create_tween()
	tw.tween_property(self, "modulate:a", 1.0, 1.5)
	await tw.finished

	var tw2 = create_tween()
	tw2.tween_property(vbox, "modulate:a", 1.0, 0.9)
	await tw2.finished

	var tw3 = create_tween()
	tw3.tween_property(body_lbl, "visible_ratio", 1.0, 3.5)
	await tw3.finished

	var tw4 = create_tween()
	tw4.tween_property(stats_lbl, "modulate:a", 1.0, 0.4)
	tw4.tween_interval(0.1)
	tw4.tween_property(retry_btn, "modulate:a", 1.0, 0.4)
	tw4.tween_interval(0.1)
	tw4.tween_property(menu_btn, "modulate:a", 1.0, 0.4)

func _add_soul_particles(tint: Color) -> void:
	var p = CPUParticles2D.new()
	p.amount = 20
	p.lifetime = 7.0
	p.emitting = true
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	var vp_size = get_viewport_rect().size
	p.emission_rect_extents = vp_size * 0.5
	p.position = vp_size * 0.5
	p.direction = Vector2(0.0, -1.0)
	p.spread = 45.0
	p.initial_velocity_min = 8.0
	p.initial_velocity_max = 22.0
	p.gravity = Vector2(0.0, 0.0)
	p.scale_amount_min = 1.5
	p.scale_amount_max = 4.0
	p.color = Color(
		clamp(tint.r * 0.6 + 0.4, 0.0, 1.0),
		clamp(tint.g * 0.6 + 0.4, 0.0, 1.0),
		clamp(tint.b * 0.6 + 0.4, 0.0, 1.0),
		0.35)
	add_child(p)

func _make_btn(txt: String) -> Button:
	var b = Button.new()
	b.text = txt
	b.custom_minimum_size = Vector2(240, 40)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return b

func _on_menu() -> void:
	GameManager.state = GameManager.GameState.MENU
	get_tree().change_scene_to_file("res://scenes/main/MainMenu.tscn")
