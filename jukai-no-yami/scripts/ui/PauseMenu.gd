extends Control

# ─── Pause Menu ───────────────────────────────────────────────────────────────

@onready var resume_btn:   Button = $VBox/ResumeButton
@onready var settings_btn: Button = $VBox/SettingsButton
@onready var menu_btn:     Button = $VBox/MainMenuButton
@onready var settings_sub: VBoxContainer = $VBox/SettingsSubPanel
@onready var perf_toggle:  CheckButton = $VBox/SettingsSubPanel/PerfToggle
@onready var master_slider: HSlider = $VBox/SettingsSubPanel/MasterSlider

func _ready() -> void:
	settings_sub.visible = false
	resume_btn.pressed.connect(GameManager.resume_game)
	settings_btn.pressed.connect(_on_settings)
	menu_btn.pressed.connect(_on_main_menu)
	perf_toggle.toggled.connect(GameManager.set_performance_mode)
	master_slider.value_changed.connect(_on_master_volume)
	perf_toggle.button_pressed = GameManager.performance_mode

func _on_settings() -> void:
	settings_sub.visible = !settings_sub.visible

func _on_main_menu() -> void:
	get_tree().paused = false
	GameManager.state = GameManager.GameState.MENU
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file("res://scenes/main/MainMenu.tscn")

func _on_master_volume(value: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), value - 20.0)
