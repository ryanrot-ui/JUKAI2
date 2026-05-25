extends Control

# ─── Main Menu — Chillas Art aesthetic ────────────────────────────────────────
# Full-screen, center-anchored. Dark background + gold title + minimal buttons.

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	GameManager.state = GameManager.GameState.MENU
	GameManager.ensure_post_process()

	# Ensure we fill the full viewport (belt + suspenders for any scene tree timing)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# ── Dark background ──────────────────────────────────────────────────────
	var bg = ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.016, 0.012, 0.010)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Subtle vignette overlay to add depth
	var vg = ColorRect.new()
	vg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vg_mat = ShaderMaterial.new()
	var vg_shader = Shader.new()
	vg_shader.code = _vignette_shader()
	vg_mat.shader = vg_shader
	vg.material = vg_mat
	add_child(vg)

	# ── Centre column ────────────────────────────────────────────────────────
	var center = CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(center)

	var vbox = VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(300, 0)
	vbox.add_theme_constant_override("separation", 6)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = "樹海の闇"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 58)
	title.add_theme_color_override("font_color", Color(0.76, 0.56, 0.20))
	title.modulate.a = 0.0
	vbox.add_child(title)

	var subtitle = Label.new()
	subtitle.text = "JUKAI NO YAMI  ·  Sea of Trees"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 12)
	subtitle.add_theme_color_override("font_color", Color(0.55, 0.48, 0.38))
	subtitle.modulate.a = 0.0
	vbox.add_child(subtitle)

	var tagline = Label.new()
	tagline.text = "Aokigahara — collect four keepsakes. Survive the Yurei."
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tagline.custom_minimum_size = Vector2(340, 0)
	tagline.add_theme_font_size_override("font_size", 10)
	tagline.add_theme_color_override("font_color", Color(0.48, 0.44, 0.38))
	tagline.modulate.a = 0.0
	vbox.add_child(tagline)

	var warning = Label.new()
	warning.text = "Content warning: suicide themes, horror violence"
	warning.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warning.add_theme_font_size_override("font_size", 9)
	warning.add_theme_color_override("font_color", Color(0.55, 0.32, 0.28))
	warning.modulate.a = 0.0
	vbox.add_child(warning)

	# Thin gold divider
	var div = ColorRect.new()
	div.custom_minimum_size = Vector2(260, 1)
	div.color = Color(0.55, 0.40, 0.12, 0.60)
	div.modulate.a = 0.0
	var div_ctr = CenterContainer.new()
	div_ctr.add_child(div)
	var spacer1 = Control.new(); spacer1.custom_minimum_size = Vector2(0, 22)
	vbox.add_child(spacer1)
	vbox.add_child(div_ctr)
	var spacer2 = Control.new(); spacer2.custom_minimum_size = Vector2(0, 18)
	vbox.add_child(spacer2)

	# Buttons
	var start_btn = _make_btn("ゲームを始める  /  Start Game")
	start_btn.pressed.connect(_on_start)
	vbox.add_child(start_btn)

	var controls_btn = _make_btn("操作方法  /  Controls")
	vbox.add_child(controls_btn)

	var settings_btn = _make_btn("設定  /  Settings")
	vbox.add_child(settings_btn)

	var quit_btn = _make_btn("終了  /  Quit")
	quit_btn.pressed.connect(_on_quit)
	vbox.add_child(quit_btn)

	# ── Both panels created BEFORE connecting buttons (fixes scope error) ────
	var controls_panel = _make_controls_panel()
	controls_panel.visible = false
	vbox.add_child(controls_panel)

	var settings_panel = VBoxContainer.new()
	settings_panel.add_theme_constant_override("separation", 6)
	settings_panel.visible = false
	vbox.add_child(settings_panel)

	var vol_lbl = Label.new()
	vol_lbl.text = "マスター音量  /  Volume"
	vol_lbl.add_theme_font_size_override("font_size", 11)
	vol_lbl.add_theme_color_override("font_color", Color(0.58, 0.52, 0.42))
	vol_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_panel.add_child(vol_lbl)

	var saved_vol: float = GameManager._config.get_value("settings", "master_volume", 0.0) if GameManager._config else 0.0
	var master_slider = HSlider.new()
	master_slider.custom_minimum_size = Vector2(220, 22)
	master_slider.min_value = -20.0; master_slider.max_value = 20.0
	master_slider.value = saved_vol
	master_slider.value_changed.connect(func(v):
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), v)
		GameManager.save_setting("master_volume", v))
	settings_panel.add_child(master_slider)

	# Fullscreen toggle
	var is_full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	var fs_label: String = "フルスクリーン ON  /  Fullscreen: ON" if is_full else "フルスクリーン  /  Fullscreen: OFF"
	var fs_btn = _make_btn(fs_label)
	fs_btn.pressed.connect(func():
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		if full:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			fs_btn.text = "フルスクリーン  /  Fullscreen: OFF"
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			fs_btn.text = "フルスクリーン ON  /  Fullscreen: ON"
		GameManager.save_setting("fullscreen", not full))
	settings_panel.add_child(fs_btn)

	# Performance mode toggle
	var pm_label: String = "パフォーマンスモード ON" if GameManager.performance_mode else "パフォーマンスモード  /  Performance Mode"
	var pm_btn = _make_btn(pm_label)
	pm_btn.pressed.connect(func():
		GameManager.set_performance_mode(not GameManager.performance_mode)
		pm_btn.text = "パフォーマンスモード ON" if GameManager.performance_mode else "パフォーマンスモード  /  Performance Mode")
	settings_panel.add_child(pm_btn)

	var gfx_lbl = Label.new()
	gfx_lbl.text = "画質  /  Graphics Quality"
	gfx_lbl.add_theme_font_size_override("font_size", 11)
	gfx_lbl.add_theme_color_override("font_color", Color(0.58, 0.52, 0.42))
	gfx_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_panel.add_child(gfx_lbl)

	var gfx_opt = OptionButton.new()
	gfx_opt.add_item("低 / Low", GameManager.GraphicsQuality.LOW)
	gfx_opt.add_item("中 / Medium", GameManager.GraphicsQuality.MEDIUM)
	gfx_opt.add_item("高 / High", GameManager.GraphicsQuality.HIGH)
	gfx_opt.selected = GameManager.graphics_quality
	gfx_opt.item_selected.connect(func(idx): GameManager.set_graphics_quality(idx))
	settings_panel.add_child(gfx_opt)

	var sens_lbl = Label.new()
	sens_lbl.text = "マウス感度  /  Mouse Sensitivity"
	sens_lbl.add_theme_font_size_override("font_size", 11)
	sens_lbl.add_theme_color_override("font_color", Color(0.58, 0.52, 0.42))
	sens_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	settings_panel.add_child(sens_lbl)

	var sens_slider = HSlider.new()
	sens_slider.custom_minimum_size = Vector2(220, 22)
	sens_slider.min_value = 0.001
	sens_slider.max_value = 0.006
	sens_slider.step = 0.0002
	sens_slider.value = GameManager.mouse_sensitivity
	sens_slider.value_changed.connect(func(v):
		GameManager.mouse_sensitivity = v
		GameManager.save_setting("mouse_sensitivity", v))
	settings_panel.add_child(sens_slider)

	# Wire buttons now that both panels exist
	controls_btn.pressed.connect(func():
		controls_panel.visible = !controls_panel.visible
		settings_panel.visible = false)

	settings_btn.pressed.connect(func():
		settings_panel.visible = !settings_panel.visible
		controls_panel.visible = false)

	# Fade-in animation
	var tw = create_tween().set_parallel()
	tw.tween_property(title,    "modulate:a", 1.0, 2.2)
	tw.tween_property(subtitle, "modulate:a", 1.0, 3.4)
	tw.tween_property(tagline,  "modulate:a", 0.9, 4.0)
	tw.tween_property(warning,  "modulate:a", 0.85, 4.6)
	tw.tween_property(div,      "modulate:a", 1.0, 3.8)

func _make_btn(txt: String) -> Button:
	var b = Button.new()
	b.text = txt
	b.custom_minimum_size = Vector2(280, 42)
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color",           Color(0.88, 0.82, 0.68))
	b.add_theme_color_override("font_hover_color",     Color(0.98, 0.88, 0.58))
	b.add_theme_color_override("font_pressed_color",   Color(0.65, 0.55, 0.30))
	return b

func _on_start() -> void:
	var tw = create_tween()
	tw.tween_property(self, "modulate:a", 0.0, 0.9)
	await tw.finished
	GameManager.start_game()

func _on_quit() -> void:
	var dialog = ConfirmationDialog.new()
	dialog.title = "終了 / Quit"
	dialog.dialog_text = "ゲームを終了しますか？\nAre you sure you want to quit?"
	dialog.ok_button_text = "終了  /  Yes, Quit"
	dialog.cancel_button_text = "キャンセル  /  Cancel"
	dialog.confirmed.connect(func(): get_tree().quit())
	dialog.canceled.connect(func(): dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered()

func _make_controls_panel() -> Control:
	var BINDS: Array = [
		["W  A  S  D",        "移動  /  Move"],
		["Shift",             "走る  /  Sprint"],
		["Mouse",             "視点  /  Look Around"],
		["E",                 "調べる  /  Interact / Pick Up"],
		["F",                 "懐中電灯  /  Toggle Flashlight"],
		["Escape",            "一時停止  /  Pause"],
	]

	var panel = VBoxContainer.new()
	panel.add_theme_constant_override("separation", 0)

	# Header
	var spacer_top = Control.new()
	spacer_top.custom_minimum_size = Vector2(0, 10)
	panel.add_child(spacer_top)

	var header = Label.new()
	header.text = "─  操作方法  /  Controls  ─"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", Color(0.65, 0.55, 0.28))
	panel.add_child(header)

	var spacer_mid = Control.new()
	spacer_mid.custom_minimum_size = Vector2(0, 6)
	panel.add_child(spacer_mid)

	# Each row: [KEY]  description
	for bind in BINDS:
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		row.custom_minimum_size = Vector2(280, 26)

		var key_lbl = Label.new()
		key_lbl.text = bind[0]
		key_lbl.custom_minimum_size = Vector2(108, 0)
		key_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		key_lbl.add_theme_font_size_override("font_size", 13)
		key_lbl.add_theme_color_override("font_color", Color(0.92, 0.84, 0.52))
		row.add_child(key_lbl)

		var sep = Label.new()
		sep.text = "   —   "
		sep.add_theme_font_size_override("font_size", 11)
		sep.add_theme_color_override("font_color", Color(0.38, 0.34, 0.28))
		row.add_child(sep)

		var desc_lbl = Label.new()
		desc_lbl.text = bind[1]
		desc_lbl.add_theme_font_size_override("font_size", 12)
		desc_lbl.add_theme_color_override("font_color", Color(0.72, 0.66, 0.56))
		row.add_child(desc_lbl)

		var row_ctr = CenterContainer.new()
		row_ctr.add_child(row)
		panel.add_child(row_ctr)

	var spacer_bot = Control.new()
	spacer_bot.custom_minimum_size = Vector2(0, 6)
	panel.add_child(spacer_bot)

	return panel

func _vignette_shader() -> String:
	return """
shader_type canvas_item;
void fragment() {
	vec2 uv = SCREEN_UV - 0.5;
	float v = 1.0 - dot(uv, uv) * 2.8;
	v = clamp(pow(v, 0.55), 0.0, 1.0);
	COLOR = vec4(0.0, 0.0, 0.0, 1.0 - v * 0.78);
}
"""
