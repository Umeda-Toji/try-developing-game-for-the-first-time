# Godot 4.7.2 / GDScript
# res://scripts/game/vista_director.gd
#
# 眺めのいい場所で、カメラがゆっくり景色を映す（W-15 ④-4）
#  ・映している間はゲームを止める（プレイヤー・敵は動かない）。カメラと文字だけが動く
#  ・VISTA_FRAMES かけて、カメラを動かす。始めと終わりの FADE_FRAMES で文字が出る・消える
#  ・SKIP_AFTER_FRAMES たった後なら、ジャンプ・攻撃のボタンで飛ばせる
#  ・終わったら、もとのカメラに戻して、ゲームを動かす
class_name VistaDirector
extends Node

const VISTA_FRAMES := 300        # 映す長さ（フレーム。5秒）
const FADE_FRAMES := 40          # 文字が出る・消えるのにかける長さ（フレーム）
const SKIP_AFTER_FRAMES := 30    # これより後なら飛ばせる（フレーム）
const SKIP_ACTIONS := ["jump", "attack_light", "attack_heavy"]

var active := false
var hud_layer: CanvasLayer       # 映している間は隠す（HPバーなど。main.gd が入れる）
var frame := 0
var cam: Camera3D
var _vista: Vista
var _prev_cam: Camera3D
var _layer: CanvasLayer
var _title: Label
var _line: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # ゲームを止めている間も動く
	add_to_group("vista_director")
	cam = Camera3D.new()
	cam.name = "VistaCamera"
	cam.fov = 60.0
	add_child(cam)
	_layer = CanvasLayer.new()
	_layer.layer = 5
	_layer.visible = false
	add_child(_layer)
	_title = _make_label(40, 0.62)
	_line = _make_label(24, 0.70)


# 映し始める。もう何かを映している・ゲームが止まっているときは映さない（false を返す）
func play(v: Vista) -> bool:
	if active or get_tree().paused:
		return false
	_vista = v
	active = true
	frame = 0
	_prev_cam = get_viewport().get_camera_3d()
	_place_camera(0.0)
	cam.make_current()
	_title.text = v.place_name
	_line.text = v.line
	_layer.visible = true
	if hud_layer != null:
		hud_layer.visible = false
	get_tree().paused = true
	return true


func _physics_process(_delta: float) -> void:
	if not active:
		return
	frame += 1
	var t := float(frame) / VISTA_FRAMES
	_place_camera(t)
	var a := minf(1.0, minf(float(frame) / FADE_FRAMES, float(VISTA_FRAMES - frame) / FADE_FRAMES))
	_title.modulate.a = a
	_line.modulate.a = a
	var skip := frame > SKIP_AFTER_FRAMES and SKIP_ACTIONS.any(func(act: String) -> bool: return Input.is_action_just_pressed(act))
	if frame >= VISTA_FRAMES or skip:
		finish()


func finish() -> void:
	active = false
	_layer.visible = false
	if hud_layer != null:
		hud_layer.visible = true
	if _prev_cam != null and is_instance_valid(_prev_cam):
		_prev_cam.make_current()
	get_tree().paused = false
	Discoveries.discovered.emit("眺めのいい場所　%d / %d" % [Discoveries.vistas.size(), Discoveries.vista_total])


# t（0〜1）のときのカメラ：なめらかに動き始めて、なめらかに止まる
func _place_camera(t: float) -> void:
	var s := smoothstep(0.0, 1.0, t)
	var pos := _vista.cam_from.lerp(_vista.cam_to, s)
	var look := _vista.look_from.lerp(_vista.look_to, s)
	cam.look_at_from_position(pos, look)


func _make_label(font_size: int, y_ratio: float) -> Label:
	var l := Label.new()
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.anchor_top = y_ratio
	l.anchor_bottom = y_ratio
	l.offset_top = 0
	l.offset_bottom = font_size * 1.6
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", Color(0.95, 0.93, 0.86))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 8)
	l.modulate.a = 0.0
	_layer.add_child(l)
	return l
