# Godot 4.7.2 / GDScript
# res://scripts/ui/result_screen.gd
#
# 勝利／敗北の画面とリトライ（U-03）
#  ・main.gd が勝ち負けを判定して show_result() を呼ぶ（そのときゲームは一時停止する）
#  ・この画面だけは一時停止中も動く（process_mode = ALWAYS）
#  ・リトライ：Rキー／パッドの×／画面の「リトライ」ボタン → retry_requested を出す
#  ・ノードはすべてコードで組み立てる
class_name ResultScreen
extends CanvasLayer

signal retry_requested

# ---- 見た目の数値 ----
const LAYER_ORDER := 10                         # ほかのHUDより手前に出す
const TITLE_FONT_SIZE := 64
const HINT_FONT_SIZE := 20
const BUTTON_SIZE := Vector2(220, 52)
const COLOR_DIM := Color(0, 0, 0, 0.55)        # 後ろの画面を暗くする
const COLOR_VICTORY := Color(1.0, 0.85, 0.3)
const COLOR_DEFEAT := Color(0.9, 0.25, 0.25)
const TEXT_VICTORY := "勝利！"
const TEXT_DEFEAT := "敗北…"

var is_victory := false
var _title: Label
var _button: Button
var _requested := false  # リトライを2回送らないため


func _ready() -> void:
	layer = LAYER_ORDER
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false


func _process(_delta: float) -> void:
	if visible and Input.is_action_just_pressed("retry"):
		_request_retry()


func show_result(victory: bool) -> void:
	is_victory = victory
	_title.text = TEXT_VICTORY if victory else TEXT_DEFEAT
	_title.add_theme_color_override("font_color", COLOR_VICTORY if victory else COLOR_DEFEAT)
	visible = true
	# マウスでボタンを押せるようにカーソルを出す
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _request_retry() -> void:
	if _requested:
		return
	_requested = true
	retry_requested.emit()


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
	box.add_theme_constant_override("separation", 18)
	center.add_child(box)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	_title.add_theme_color_override("font_outline_color", Color.BLACK)
	_title.add_theme_constant_override("outline_size", 10)
	box.add_child(_title)

	_button = Button.new()
	_button.text = "リトライ"
	_button.custom_minimum_size = BUTTON_SIZE
	_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_button.focus_mode = Control.FOCUS_NONE  # ×ボタンは "retry" で受けるので、フォーカスでの二重反応を防ぐ
	_button.pressed.connect(_request_retry)
	box.add_child(_button)

	var hint := Label.new()
	hint.text = "[R] / パッドの × でもリトライ"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", HINT_FONT_SIZE)
	hint.add_theme_color_override("font_outline_color", Color.BLACK)
	hint.add_theme_constant_override("outline_size", 5)
	box.add_child(hint)
