# Godot 4.7.2 / GDScript
# res://scripts/ui/enemy_bars.gd
#
# 敵の頭の上の体力バー（U-08）
#  ・敵ごとに、HPバー（赤）と体幹バー（オレンジ。ブレイク中は黄色）を頭の上に出す
#  ・画面の上の位置は、毎フレームカメラから計算する（3Dの位置 → 画面の位置）
#  ・攻撃を当てる（またはパリィする）までは出さない。一度出たら、その後はずっと出す（11/18 変更）
#  ・カメラの後ろにいる敵や、遠い敵（SHOW_DISTANCE より先）は出さない。倒した敵も出さない
#  ・ロックオン中の敵は、下の中央の大きな表示（battle_hud.gd）にも出る
#  ・ノードはすべてコードで組み立てる
class_name EnemyBars
extends Control

const HP_BAR_SIZE := Vector2(64, 6)
const POSTURE_BAR_SIZE := Vector2(64, 3)
const SHOW_DISTANCE := 24.0            # カメラからこの距離（m）までの敵だけ出す（今の部屋は全部入る）
const COLOR_BACK := Color(0.05, 0.05, 0.07, 0.75)
const COLOR_HP := Color(0.85, 0.2, 0.2)
const COLOR_POSTURE := Color(1.0, 0.6, 0.15)
const COLOR_POSTURE_BROKEN := Color(1.0, 0.9, 0.2)

var _bars := {}   # 敵 → {"box", "hp", "posture", "posture_fill"}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	var cam := get_viewport().get_camera_3d()
	var alive := {}
	for node in get_tree().get_nodes_in_group("enemies"):
		var e := node as Enemy
		if e == null or e.is_dead():
			continue
		alive[e] = true
		if not _bars.has(e):
			_bars[e] = _make_bar()
		_update_bar(e, _bars[e], cam)
	# 倒した敵・いなくなった敵のバーを片付ける
	for e in _bars.keys():
		if not alive.has(e):
			(_bars[e]["box"] as Control).queue_free()
			_bars.erase(e)


func bar_of(e: Enemy) -> Dictionary:
	return _bars.get(e, {})


func _update_bar(e: Enemy, bar: Dictionary, cam: Camera3D) -> void:
	var box: Control = bar["box"]
	var head := e.global_position + Vector3.UP * e.bar_height
	if not e.bar_revealed or cam == null or cam.is_position_behind(head) or cam.global_position.distance_to(head) > SHOW_DISTANCE:
		box.visible = false
		return
	box.visible = true
	var p := cam.unproject_position(head)
	box.position = p - Vector2(HP_BAR_SIZE.x * 0.5, 0)
	var hp: ProgressBar = bar["hp"]
	hp.max_value = e.max_hp
	hp.value = e.hp
	var po: ProgressBar = bar["posture"]
	po.max_value = e.max_posture
	po.value = e.posture
	(bar["posture_fill"] as StyleBoxFlat).bg_color = COLOR_POSTURE_BROKEN if e.state == Enemy.State.BROKEN else COLOR_POSTURE


func _make_bar() -> Dictionary:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 1)
	add_child(box)
	var hp := _make_progress(HP_BAR_SIZE, COLOR_HP)
	box.add_child(hp["bar"])
	var po := _make_progress(POSTURE_BAR_SIZE, COLOR_POSTURE)
	box.add_child(po["bar"])
	return {"box": box, "hp": hp["bar"], "posture": po["bar"], "posture_fill": po["fill"]}


func _make_progress(size: Vector2, color: Color) -> Dictionary:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = size
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := StyleBoxFlat.new()
	back.bg_color = COLOR_BACK
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	bar.add_theme_stylebox_override("background", back)
	bar.add_theme_stylebox_override("fill", fill)
	return {"bar": bar, "fill": fill}
