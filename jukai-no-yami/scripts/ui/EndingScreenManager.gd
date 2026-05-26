extends CanvasLayer
## EndingScreenManager — drop-in pause/end menu controller.
##
## Recommended scene tree (build this in the editor):
##
##   CanvasLayer  (this script attached here, layer = 100)
##   └─ Control "Root"
##         anchors_preset = Control.PRESET_FULL_RECT
##         mouse_filter   = MOUSE_FILTER_STOP   (so dim overlay swallows clicks)
##         └─ ColorRect "Dim"
##              anchors_preset = Control.PRESET_FULL_RECT
##              color          = Color(0, 0, 0, 0.85)
##         └─ CenterContainer "Center"
##              anchors_preset = Control.PRESET_FULL_RECT
##              └─ VBoxContainer "Menu"
##                    custom_minimum_size = Vector2(360, 0)
##                    alignment           = ALIGNMENT_CENTER
##                    └─ Label "Title"
##                    └─ Label "Subtitle"
##                    └─ RichTextLabel "Body"      (custom_minimum_size 360×180)
##                    └─ HSeparator
##                    └─ Button "PlayAgainButton"  (custom_minimum_size 220×42)
##                    └─ Button "MainMenuButton"   (custom_minimum_size 220×42)
##
## Why this structure works:
##   • The Control root with PRESET_FULL_RECT fills the entire viewport on
##     any aspect ratio.
##   • CenterContainer with PRESET_FULL_RECT also fills the viewport, and
##     centres its single child (the VBoxContainer) horizontally + vertically.
##   • VBoxContainer.custom_minimum_size only sets a MINIMUM — narrow
##     viewports clamp it down, wide viewports leave it at its natural
##     width. Buttons stay centred regardless.
##
## Set this CanvasLayer's process_mode to PROCESS_MODE_ALWAYS in the
## Inspector (or rely on _ready() below, which sets it from code) so the
## UI keeps running when get_tree().paused = true.

# Optional NodePath overrides — set these in the Inspector ONLY if the
# button nodes don't have the default names below. Empty paths trigger
# auto-discovery via find_child().
@export var play_again_button_path: NodePath
@export var main_menu_button_path: NodePath
@export var main_menu_scene: String = "res://scenes/main/MainMenu.tscn"

var _play_again_btn: Button = null
var _main_menu_btn: Button = null


func _ready() -> void:
	# CRITICAL: PROCESS_MODE_ALWAYS keeps the UI script running even when
	# the SceneTree is paused (get_tree().paused = true). Without this,
	# Tween animations on the menu freeze and button input is rejected.
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Force the cursor visible the exact frame this UI opens. Player.gd
	# captures the cursor for FPS look — we have to un-capture it or the
	# player can't click any button.
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	# Find the buttons either via the explicit Inspector path or by name.
	_play_again_btn = _resolve_button(play_again_button_path, "PlayAgainButton")
	_main_menu_btn  = _resolve_button(main_menu_button_path,  "MainMenuButton")
	if _play_again_btn:
		if not _play_again_btn.pressed.is_connected(_on_PlayAgain_pressed):
			_play_again_btn.pressed.connect(_on_PlayAgain_pressed)
	else:
		push_warning("[EndingScreenManager] PlayAgainButton not found.")
	if _main_menu_btn:
		if not _main_menu_btn.pressed.is_connected(_on_MainMenu_pressed):
			_main_menu_btn.pressed.connect(_on_MainMenu_pressed)
	else:
		push_warning("[EndingScreenManager] MainMenuButton not found.")


# Reusable button resolver — explicit Inspector path takes priority,
# otherwise walks the children of this CanvasLayer looking for a Button
# with the given name.
func _resolve_button(explicit_path: NodePath, fallback_name: String) -> Button:
	if not explicit_path.is_empty():
		var n: Node = get_node_or_null(explicit_path)
		if n is Button:
			return n
	# Recursive search — find_child(name, recursive=true, owned=false).
	var found: Node = find_child(fallback_name, true, false)
	if found is Button:
		return found
	return null


# ── Public API ──────────────────────────────────────────────────────────

# Call this whenever the End menu (or a mid-game pause menu) is shown.
# It re-applies the always-process / visible-cursor settings in case the
# game state has reset them.
func show_menu() -> void:
	visible = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


# Hide the menu without unpausing or recapturing the cursor — the caller
# decides whether to resume gameplay or close the game.
func hide_menu() -> void:
	visible = false


# ── Button handlers ─────────────────────────────────────────────────────

# Pressing "Play Again" must:
#   1. Release the engine pause state.
#   2. Recapture the mouse (the new game expects FPS look).
#   3. Reset any global game-over state so the new run starts clean.
#   4. Trigger GameManager.start_game() if the autoload exists, otherwise
#      fall back to a plain scene reload.
func _on_PlayAgain_pressed() -> void:
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm and gm.has_method("start_game"):
		gm.start_game()
	else:
		# Defensive fallback — if the autoload isn't in this scene, just
		# reload the current scene cleanly.
		get_tree().reload_current_scene()


# Pressing "Main Menu" must:
#   1. Release the engine pause state.
#   2. Show the cursor (the main menu uses it for clicks too).
#   3. Set the game state to MENU if the autoload exists.
#   4. change_scene_to_file to the main menu path.
func _on_MainMenu_pressed() -> void:
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	var gm: Node = get_node_or_null("/root/GameManager")
	if gm and "state" in gm and "GameState" in gm:
		gm.state = gm.GameState.MENU
	get_tree().change_scene_to_file(main_menu_scene)
