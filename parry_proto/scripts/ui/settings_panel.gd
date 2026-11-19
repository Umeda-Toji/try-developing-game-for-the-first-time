# Godot 4.7.2 / GDScript
# res://scripts/ui/settings_panel.gd
#
# 設定の画面（O-01）。ポーズメニューとタイトル画面の両方で使う
#  ・音量4つ・感度4つ（スライダー）、カメラの反転（上下・左右）・狙いの補助（オン／オフ）、画質
#  ・動かすとすぐ効いて、すぐ保存する（GameSettings）
#  ・「戻る」→ back_pressed（Esc／○で戻る処理は使う側が行う）。画質のボタン → graphics_toggled
#  ・パッドでも、上下で選び、左右でスライダーを動かせる
class_name SettingsPanel
extends MarginContainer

signal back_pressed
signal graphics_toggled

const MARGIN := 40
const FONT_SIZE := 18
const SLIDER_WIDTH := 300.0
const COLOR_BG := Color(0.1, 0.1, 0.13, 0.98)

var sliders := {}        # "master" などのキー → HSlider（音量は volume_*、感度は sens_*）
var checks := {}         # "invert_x" ／ "invert_y" ／ "aim_assist" → CheckButton
var graphics_button: Button
var back_button: Button
var _value_labels := {}


func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		add_theme_constant_override("margin_" + side, MARGIN)
	visible = false
	var panel := PanelContainer.new()
	var bg := StyleBoxFlat.new()
	bg.bg_color = COLOR_BG
	bg.set_corner_radius_all(6)
	bg.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", bg)
	add_child(panel)
	var center := CenterContainer.new()
	panel.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	center.add_child(box)

	var title := Label.new()
	title.text = "設定"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	box.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 6)
	box.add_child(grid)
	_section(grid, "音量")
	for k in GameSettings.VOLUME_KEYS:
		_add_slider(grid, "volume_" + k, GameSettings.VOLUME_LABELS[k], 0.0, 1.0, GameSettings.VOLUME_STEP,
			func(v: float) -> void: GameSettings.set_volume(k, v))
	_section(grid, "感度")
	for k in GameSettings.SENS_KEYS:
		_add_slider(grid, "sens_" + k, GameSettings.SENS_LABELS[k], GameSettings.SENS_MIN, GameSettings.SENS_MAX, GameSettings.SENS_STEP,
			func(v: float) -> void: GameSettings.set_sens(k, v))

	var flags := HBoxContainer.new()
	flags.add_theme_constant_override("separation", 24)
	flags.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(flags)
	for f in [["invert_y", "上下の反転"], ["invert_x", "左右の反転"], ["aim_assist", "狙いの補助（パッド）"]]:
		var c := CheckButton.new()
		c.text = f[1]
		c.add_theme_font_size_override("font_size", FONT_SIZE)
		var key: String = f[0]
		c.toggled.connect(func(on: bool) -> void: GameSettings.set_flag(key, on))
		flags.add_child(c)
		checks[key] = c

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 24)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(buttons)
	graphics_button = _button("画質")
	graphics_button.pressed.connect(func() -> void:
		graphics_toggled.emit()
		_update_graphics_label())
	buttons.add_child(graphics_button)
	back_button = _button("戻る（Esc ／ ○）")
	back_button.pressed.connect(func() -> void: back_pressed.emit())
	buttons.add_child(back_button)


# 今の設定を画面に出して、開く
func open() -> void:
	for k in GameSettings.VOLUME_KEYS:
		(sliders["volume_" + k] as HSlider).set_value_no_signal(GameSettings.volumes[k])
	for k in GameSettings.SENS_KEYS:
		(sliders["sens_" + k] as HSlider).set_value_no_signal(GameSettings.sens[k])
	for key in sliders.keys():
		_update_value_label(key)
	(checks["invert_x"] as CheckButton).set_pressed_no_signal(GameSettings.invert_x)
	(checks["invert_y"] as CheckButton).set_pressed_no_signal(GameSettings.invert_y)
	(checks["aim_assist"] as CheckButton).set_pressed_no_signal(GameSettings.aim_assist)
	_update_graphics_label()
	visible = true
	(sliders["volume_master"] as HSlider).grab_focus()


func close() -> void:
	visible = false


func _update_graphics_label() -> void:
	GraphicsSettings.load_saved()
	graphics_button.text = "画質：" + GraphicsSettings.label()


func _section(grid: GridContainer, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", FONT_SIZE + 2)
	l.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	grid.add_child(l)
	grid.add_child(Control.new())
	grid.add_child(Control.new())


func _add_slider(grid: GridContainer, key: String, text: String, lo: float, hi: float, step: float, on_change: Callable) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", FONT_SIZE)
	grid.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size = Vector2(SLIDER_WIDTH, 24)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value_changed.connect(func(v: float) -> void:
		on_change.call(v)
		_update_value_label(key))
	grid.add_child(s)
	var vl := Label.new()
	vl.custom_minimum_size = Vector2(70, 0)
	vl.add_theme_font_size_override("font_size", FONT_SIZE)
	grid.add_child(vl)
	sliders[key] = s
	_value_labels[key] = vl


func _update_value_label(key: String) -> void:
	var v: float = (sliders[key] as HSlider).value
	(_value_labels[key] as Label).text = ("%d%%" % int(round(v * 100.0))) if key.begins_with("volume_") else ("%.1f 倍" % v)


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(240, 48)
	b.add_theme_font_size_override("font_size", FONT_SIZE)
	return b
