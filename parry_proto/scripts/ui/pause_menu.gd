# Godot 4.7.2 / GDScript
# res://scripts/ui/pause_menu.gd
#
# ポーズメニュー（U-04）
#  ・Esc ／ パッドの OPTIONS で開く・閉じる（"pause" アクション）
#  ・開いている間はゲームを一時停止する。このメニューだけは一時停止中も動く（process_mode = ALWAYS）
#  ・ボタン：再開／リトライ／画質／クレジット／終了。マウスでも、パッドの上下＋×でも選べる
#  ・クレジット（U-05）：Godot のライセンス表記など。上下でスクロール、Esc／○／「戻る」でメニューに戻る
#  ・勝敗の画面が出ているときや、終了の途中では開かない（main.gd の can_pause() で判断）
#  ・ノードはすべてコードで組み立てる
class_name PauseMenu
extends CanvasLayer

signal resume_requested
signal retry_requested
signal quit_requested
signal graphics_toggled   # 画質（U-09）を切り替える

# ---- 見た目の数値 ----
const LAYER_ORDER := 20                    # 結果画面（10）より手前
const TITLE_FONT_SIZE := 48
const BUTTON_SIZE := Vector2(240, 52)
const COLOR_DIM := Color(0, 0, 0, 0.6)

var is_open := false
var credits_open := false
var can_open: Callable  # main.gd が渡す（今開いてよいか）

var resume_button: Button
var retry_button: Button
var quit_button: Button
var credits_button: Button
var graphics_button: Button
var credits_text: RichTextLabel  # クレジットの文章（テスト用。中身は CreditsPanel）

var _menu_box: Control
var _credits_panel: CreditsPanel


func _ready() -> void:
	layer = LAYER_ORDER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false


func _process(_delta: float) -> void:
	if credits_open:
		if Input.is_action_just_pressed("pause") or Input.is_action_just_pressed("ui_cancel"):
			close_credits()
		return
	if Input.is_action_just_pressed("pause"):
		if is_open:
			resume_requested.emit()
		elif not can_open.is_valid() or can_open.call():
			open()


func open() -> void:
	is_open = true
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	resume_button.grab_focus()  # パッドの上下で選べるように、最初は「再開」を選んでおく


func open_credits() -> void:
	credits_open = true
	_menu_box.visible = false
	_credits_panel.open()


func close_credits() -> void:
	credits_open = false
	_credits_panel.close()
	_menu_box.visible = true
	credits_button.grab_focus()


func close() -> void:
	if credits_open:
		close_credits()
	is_open = false
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# =========================================================
# 組み立て
# =========================================================
func _build() -> void:
	var dim := ColorRect.new()
	dim.color = COLOR_DIM
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	_menu_box = center

	var title := Label.new()
	title.text = "ポーズ"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	title.add_theme_color_override("font_outline_color", Color.BLACK)
	title.add_theme_constant_override("outline_size", 8)
	box.add_child(title)

	resume_button = _make_button("再開", resume_requested)
	retry_button = _make_button("リトライ", retry_requested)
	credits_button = Button.new()
	credits_button.text = "クレジット"
	credits_button.custom_minimum_size = BUTTON_SIZE
	credits_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	credits_button.pressed.connect(open_credits)
	quit_button = _make_button("終了", quit_requested)
	# 画質（U-09）：押すたびに「高画質」⇔「軽い」。すぐ反映される
	graphics_button = Button.new()
	graphics_button.custom_minimum_size = BUTTON_SIZE
	graphics_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	graphics_button.pressed.connect(func() -> void:
		graphics_toggled.emit()
		_update_graphics_label())
	_update_graphics_label()
	for b in [resume_button, retry_button, graphics_button, credits_button, quit_button]:
		box.add_child(b)
	_build_credits()


func _update_graphics_label() -> void:
	GraphicsSettings.load_saved()
	graphics_button.text = "画質：" + GraphicsSettings.label()


# クレジットの画面（タイトル画面と同じもの。scripts/ui/credits_panel.gd）
func _build_credits() -> void:
	_credits_panel = CreditsPanel.new()
	_credits_panel.back_pressed.connect(close_credits)
	add_child(_credits_panel)
	credits_text = _credits_panel.text_label


func _make_button(text: String, sig: Signal) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = BUTTON_SIZE
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func() -> void: sig.emit())
	return b
