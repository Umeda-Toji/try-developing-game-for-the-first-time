# Godot 4.7.2 / GDScript
# res://scripts/ui/hint_box.gd
#
# 操作のヒント（U-11。11/20）：画面の下の真ん中に、1・2行の短いヒントを出す
#  ・SHOW_FRAMES たつと消える（出る・消えるは FADE_FRAMES）。ゲームは止めない
#  ・いくつか続いたら、順番に出す
#  ・押すボタンは、最後に使った方（キーボード・マウス／パッド）の書き方にする
class_name HintBox
extends Control

const SHOW_FRAMES := 360
const FADE_FRAMES := 30
const BOTTOM_MARGIN := 120.0

var label: Label
var current_id := ""
var frames_left := 0
var using_pad := false       # 最後に使ったのがパッドか
var _queue: Array = []       # [id, キーボードの文, パッドの文]
var _panel: PanelContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = PanelContainer.new()
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.05, 0.06, 0.06, 0.7)
	bg.set_corner_radius_all(6)
	bg.set_content_margin_all(12)
	_panel.add_theme_stylebox_override("panel", bg)
	_panel.anchor_left = 0.5
	_panel.anchor_right = 0.5
	_panel.anchor_top = 1.0
	_panel.anchor_bottom = 1.0
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.offset_top = -BOTTOM_MARGIN
	_panel.offset_bottom = -BOTTOM_MARGIN
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	label = Label.new()
	label.name = "Text"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", Color(0.95, 0.93, 0.86))
	_panel.add_child(label)
	_panel.modulate.a = 0.0
	_panel.visible = false


# 最後に使った入力の種類を覚える（ヒントのボタンの書き方に使う）
func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.4):
		using_pad = true
	elif event is InputEventKey or event is InputEventMouseButton:
		using_pad = false


func show_hint(id: String, keyboard_text: String, pad_text: String) -> void:
	_queue.append([id, keyboard_text, pad_text])
	if current_id == "":
		_next()


func is_showing() -> bool:
	return current_id != ""


func _next() -> void:
	if _queue.is_empty():
		current_id = ""
		_panel.visible = false
		return
	var h: Array = _queue.pop_front()
	current_id = h[0]
	label.text = h[2] if using_pad else h[1]
	frames_left = SHOW_FRAMES
	_panel.visible = true


func _physics_process(_delta: float) -> void:
	if current_id == "" or get_tree().paused:
		_panel.visible = current_id != "" and not get_tree().paused
		return
	_panel.visible = true
	frames_left -= 1
	var shown := SHOW_FRAMES - frames_left
	_panel.modulate.a = clampf(minf(float(shown) / FADE_FRAMES, float(frames_left) / FADE_FRAMES), 0.0, 1.0)
	if frames_left <= 0:
		_next()
