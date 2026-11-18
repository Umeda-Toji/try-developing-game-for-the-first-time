# Godot 4.7.2 / GDScript
# res://scripts/ui/credits_panel.gd
#
# クレジットの画面（U-05）。ポーズメニューとタイトル画面の両方で使う
#  ・文章は Credits.build_text()（素材の表記・Godot のライセンス文）
#  ・上下でスクロール、「戻る」ボタン → back_pressed を出す（Esc／○で戻る処理は使う側が行う）
#  ・ノードはすべてコードで組み立てる
class_name CreditsPanel
extends MarginContainer

signal back_pressed

const MARGIN := 48               # 枠と画面の端の間
const FONT_SIZE := 14
const TITLE_FONT_SIZE := 28
const BUTTON_SIZE := Vector2(240, 52)
const COLOR_BG := Color(0.1, 0.1, 0.13, 0.98)  # 後ろの画面が透けないように、ほぼ不透明

var text_label: RichTextLabel
var back_button: Button


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		add_theme_constant_override("margin_" + side, MARGIN)

	var panel := PanelContainer.new()
	var bg := StyleBoxFlat.new()
	bg.bg_color = COLOR_BG
	bg.set_corner_radius_all(6)
	bg.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", bg)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	var title := Label.new()
	title.text = "クレジット"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	box.add_child(title)

	text_label = RichTextLabel.new()
	text_label.bbcode_enabled = false
	text_label.scroll_active = true
	text_label.focus_mode = Control.FOCUS_ALL
	text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	text_label.add_theme_font_size_override("normal_font_size", FONT_SIZE)
	box.add_child(text_label)

	back_button = Button.new()
	back_button.text = "戻る（Esc ／ ○）"
	back_button.custom_minimum_size = BUTTON_SIZE
	back_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_button.pressed.connect(func() -> void: back_pressed.emit())
	box.add_child(back_button)
	visible = false


# 開く（長い文章なので、初めて開いたときに作る）
func open() -> void:
	if text_label.text == "":
		text_label.text = Credits.build_text()
	visible = true
	text_label.scroll_to_line(0)
	text_label.grab_focus()  # パッドの上下でスクロールできるように


func close() -> void:
	visible = false
