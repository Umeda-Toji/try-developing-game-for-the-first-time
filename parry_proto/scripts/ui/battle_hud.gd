# Godot 4.7.2 / GDScript
# res://scripts/ui/battle_hud.gd
#
# 戦闘用のバー表示（U-02）
#  ・左下：プレイヤーのHPバー、その下にスタミナのバー（M-04）
#  ・下の中央：ロックオン中の敵の名前・HPバー・体幹バー（ロックオンしていないときは隠す）
#  ・体幹は殴られないと少しずつ減るので、シグナルではなく毎フレーム値を読んで表示する
#  ・ノードはすべてコードで組み立てる（エディタでの手作業なし）
class_name BattleHud
extends Control

# ---- 見た目の数値（ここを変えれば見た目が変わる）----
const PLAYER_BAR_SIZE := Vector2(260, 18)
const ENEMY_HP_BAR_SIZE := Vector2(400, 16)
const ENEMY_POSTURE_BAR_SIZE := Vector2(400, 10)
const MARGIN := 24.0                      # 画面の端からの距離
const FONT_SIZE := 16

const COLOR_BACK := Color(0.08, 0.08, 0.1, 0.75)      # バーの背景
const COLOR_PLAYER_HP := Color(0.3, 0.85, 0.45)
const COLOR_PLAYER_HP_LOW := Color(0.95, 0.3, 0.25)   # HPが少ないとき
const PLAYER_HP_LOW_RATIO := 0.3                      # この割合以下で「少ない」色にする
const COLOR_ENEMY_HP := Color(0.85, 0.2, 0.2)
const COLOR_POSTURE := Color(1.0, 0.6, 0.15)
const COLOR_POSTURE_BROKEN := Color(1.0, 0.9, 0.2)    # 体幹ブレイク中
const STAMINA_BAR_SIZE := Vector2(260, 8)
const COLOR_STAMINA := Color(0.95, 0.85, 0.35)
const COLOR_STAMINA_EMPTY := Color(0.6, 0.45, 0.3)    # 空になったとき

var player: Player

var player_hp_bar: ProgressBar
var enemy_panel: VBoxContainer      # 敵の表示ひとまとめ（ロックオン中だけ表示）
var enemy_hp_bar: ProgressBar
var enemy_posture_bar: ProgressBar
var stamina_bar: ProgressBar
var _stamina_fill: StyleBoxFlat

var _player_label: Label
var _enemy_name_label: Label
var _player_fill: StyleBoxFlat
var _posture_fill: StyleBoxFlat
var weapon_label: Label   # 右下：今の武器と弾の数（G-01・G-03）
var crosshair: Control    # 真ん中の照準（銃のときだけ。G-03）


func _ready() -> void:
	# 画面全体を覆うが、マウス操作は邪魔しない
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_player_bar()
	_build_enemy_panel()
	weapon_label = _make_label()
	weapon_label.name = "Weapon"
	weapon_label.add_theme_font_size_override("font_size", 24)
	weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	weapon_label.anchor_left = 1.0
	weapon_label.anchor_right = 1.0
	weapon_label.anchor_top = 1.0
	weapon_label.anchor_bottom = 1.0
	weapon_label.offset_left = -360
	weapon_label.offset_right = -MARGIN
	weapon_label.offset_top = -MARGIN - 40
	weapon_label.offset_bottom = -MARGIN
	add_child(weapon_label)
	crosshair = Control.new()
	crosshair.name = "Crosshair"
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.draw.connect(_draw_crosshair)
	add_child(crosshair)


func _process(_delta: float) -> void:
	if player == null:
		return
	_update_player()
	_update_enemy()


# =========================================================
# 組み立て
# =========================================================
func _build_player_bar() -> void:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	box.grow_vertical = Control.GROW_DIRECTION_BEGIN  # 下端を基準に上へ伸ばす
	box.position = Vector2(MARGIN, -MARGIN)
	add_child(box)

	_player_label = _make_label()
	box.add_child(_player_label)
	_player_fill = _make_fill(COLOR_PLAYER_HP)
	player_hp_bar = _make_bar(PLAYER_BAR_SIZE, _player_fill)
	box.add_child(player_hp_bar)
	_stamina_fill = _make_fill(COLOR_STAMINA)
	stamina_bar = _make_bar(STAMINA_BAR_SIZE, _stamina_fill)
	box.add_child(stamina_bar)


func _build_enemy_panel() -> void:
	enemy_panel = VBoxContainer.new()
	enemy_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	enemy_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	enemy_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH  # 中央を基準に左右へ伸ばす
	enemy_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	enemy_panel.position.y = -MARGIN
	enemy_panel.add_theme_constant_override("separation", 4)
	enemy_panel.visible = false
	add_child(enemy_panel)

	_enemy_name_label = _make_label()
	_enemy_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	enemy_panel.add_child(_enemy_name_label)
	enemy_hp_bar = _make_bar(ENEMY_HP_BAR_SIZE, _make_fill(COLOR_ENEMY_HP))
	enemy_panel.add_child(enemy_hp_bar)
	_posture_fill = _make_fill(COLOR_POSTURE)
	enemy_posture_bar = _make_bar(ENEMY_POSTURE_BAR_SIZE, _posture_fill)
	enemy_panel.add_child(enemy_posture_bar)


func _make_bar(size: Vector2, fill: StyleBoxFlat) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = size
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := StyleBoxFlat.new()
	back.bg_color = COLOR_BACK
	back.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", back)
	bar.add_theme_stylebox_override("fill", fill)
	return bar


func _make_fill(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(3)
	return s


# 照準：構えは小さな点、腰だめは広がり（角度）に合わせた円
func _draw_crosshair() -> void:
	if player == null or player.weapons == null or not player.weapons.is_gun():
		return
	var c := crosshair.size * 0.5
	var col := Color(1, 1, 1, 0.85)
	if player.aiming:
		crosshair.draw_circle(c, 2.5, col)
		return
	var cam := get_viewport().get_camera_3d()
	var fov := deg_to_rad(cam.fov if cam != null else 70.0)
	var spread := deg_to_rad(float(Weapons.GUNS[player.weapons.current]["spread_hip"]))
	var r := maxf(6.0, tan(spread) / tan(fov * 0.5) * crosshair.size.y * 0.5)
	crosshair.draw_arc(c, r, 0.0, TAU, 32, col, 1.5)
	crosshair.draw_circle(c, 1.5, col)


func _make_label() -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", FONT_SIZE)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	return l


# =========================================================
# 毎フレームの更新
# =========================================================
func _update_player() -> void:
	if player.weapons != null:
		var w: Weapons = player.weapons
		var text := w.label()
		var empty := false
		if w.is_gun() and not w.is_swapping():
			var a := w.ammo(w.current)
			text = "%s　%d ／ %d" % [w.label(), int(a["mag"]), int(a["reserve"])]
			if w.is_reloading():
				text += "　リロード中"
			empty = int(a["mag"]) <= 0
		weapon_label.text = ("持ち替え中… " + w.label()) if w.is_swapping() else text
		weapon_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3) if empty else Color.WHITE)
		crosshair.visible = w.is_gun()
		crosshair.queue_redraw()
	player_hp_bar.max_value = player.max_hp
	player_hp_bar.value = player.hp
	_player_label.text = "HP %d / %d" % [player.hp, player.max_hp]
	if Discoveries.heals > 0:  # 回復薬を持っていたら数を出す（W-15）
		_player_label.text += "　　回復薬 ×%d（Q ／ 十字キー上）" % Discoveries.heals
	var low := float(player.hp) <= float(player.max_hp) * PLAYER_HP_LOW_RATIO
	_player_fill.bg_color = COLOR_PLAYER_HP_LOW if low else COLOR_PLAYER_HP
	stamina_bar.max_value = player.max_stamina
	stamina_bar.value = player.stamina
	_stamina_fill.bg_color = COLOR_STAMINA_EMPTY if player.stamina <= 0.0 else COLOR_STAMINA


func _update_enemy() -> void:
	var e := player.lock_target as Enemy
	if e == null or not is_instance_valid(e) or e.is_dead():
		enemy_panel.visible = false
		return
	enemy_panel.visible = true
	_enemy_name_label.text = e.display_name + ("（第2形態）" if e.is_phase2() else "")
	enemy_hp_bar.max_value = e.max_hp
	enemy_hp_bar.value = e.hp
	enemy_posture_bar.max_value = e.max_posture
	enemy_posture_bar.value = e.posture
	_posture_fill.bg_color = COLOR_POSTURE_BROKEN if e.state == Enemy.State.BROKEN else COLOR_POSTURE
