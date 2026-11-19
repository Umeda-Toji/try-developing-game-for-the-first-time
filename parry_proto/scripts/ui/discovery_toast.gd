# Godot 4.7.2 / GDScript
# res://scripts/ui/discovery_toast.gd
#
# 見つけたときの短いお知らせ（W-15）
#  ・画面の上の真ん中に、「記録の断片 3 / 10」などを出し、SHOW_FRAMES たったら消える
#  ・Discoveries.discovered を受け取る
class_name DiscoveryToast
extends Control

const SHOW_FRAMES := 180     # 出しておく長さ（フレーム）
const FADE_FRAMES := 30      # 出る・消えるのにかける長さ（フレーム）

var label: Label
var frames_left := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS  # 止まっている間も、隠すために動く  # 画面いっぱい（位置と大きさも合わせる）
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	label = Label.new()
	label.name = "Text"
	# 画面の上の真ん中（横は画面いっぱい、文字は真ん中寄せ）
	label.anchor_left = 0.0
	label.anchor_right = 1.0
	label.anchor_top = 0.0
	label.anchor_bottom = 0.0
	label.offset_top = 90
	label.offset_bottom = 130
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", Color(0.95, 0.93, 0.86))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 8)
	label.modulate.a = 0.0
	add_child(label)
	Discoveries.discovered.connect(show_message)


func show_message(text: String) -> void:
	label.text = text
	frames_left = SHOW_FRAMES


func _physics_process(_delta: float) -> void:
	# ポーズ・タイトル・眺めの間は隠して、時間も進めない（ポーズメニューの文字と重ならないように）
	visible = not get_tree().paused
	if not visible:
		return
	if frames_left > 0:
		frames_left -= 1
	var shown := SHOW_FRAMES - frames_left
	if frames_left <= 0:
		label.modulate.a = 0.0
	else:
		label.modulate.a = minf(1.0, minf(float(shown) / FADE_FRAMES, float(frames_left) / FADE_FRAMES))
