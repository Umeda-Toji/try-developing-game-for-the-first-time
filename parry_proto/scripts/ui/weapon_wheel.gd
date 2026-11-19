# Godot 4.7.2 / GDScript
# res://scripts/ui/weapon_wheel.gd
#
# 武器の輪（G-02。NEXT_FEATURES 1.6・ステップ5a。11/19 決定）
#  ・パッドで武器を選ぶ円。上＝剣、右＝AR、下＝SMG、左＝SG
#  ・開き方：R3（剣のとき・銃のとき）、△を HOLD_FRAMES 押し続ける（銃のときだけ。player.gd が数える）
#  ・開いている間は、ゲームを SLOW_SCALE（1/4）の速さにする。カメラは回らない。プレイヤーは動かない
#  ・右スティックを倒した方の武器を選ぶ。× ／ もう一度 R3 ／ △で開いたときは△を離す で決定、○ でやめる
#  ・決めた武器への持ち替えは Weapons.request（持ち替えは SWAP_FRAMES）
class_name WeaponWheel
extends Control

signal chosen(id: String)

const SLOW_SCALE := 0.25
const SELECT_DEADZONE := 0.5     # 右スティックをこれより倒したら選ぶ
const ORDER := ["sword", "ar", "smg", "sg"]   # 上・右・下・左
const RADIUS := 150.0
const COLOR_BG := Color(0.05, 0.06, 0.06, 0.75)
const COLOR_ITEM := Color(0.85, 0.85, 0.8)
const COLOR_SELECTED := Color(1.0, 0.85, 0.4)

var is_open := false
var selected := ""
var current := "sword"           # 今の武器（真ん中に出す）
var _hold_mode := false          # △長押しで開いたか（△を離すと決定）
var closed_at := -100            # 閉じた物理フレーム（閉じたときの×で、ジャンプしないように）


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	add_to_group("weapon_wheel")


func open(now_weapon: String, hold_mode: bool) -> void:
	if is_open or get_tree().paused:
		return
	is_open = true
	_hold_mode = hold_mode
	current = now_weapon
	selected = ""
	visible = true
	Engine.time_scale = SLOW_SCALE
	queue_redraw()


func close(confirm: bool) -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	Engine.time_scale = 1.0
	closed_at = Engine.get_physics_frames()
	if confirm and selected != "":
		chosen.emit(selected)


# 右スティックの向きから、選ぶ武器を決める（上・右・下・左の4つ）
static func pick(stick: Vector2) -> String:
	if stick.length() < SELECT_DEADZONE:
		return ""
	var a := atan2(stick.x, -stick.y)   # 上が 0、右回り
	var idx := int(round(a / (PI * 0.5))) % 4
	if idx < 0:
		idx += 4
	return ORDER[idx]


# 開いているか、閉じたすぐ後か（プレイヤーの入力を止める）
func blocks_input() -> bool:
	return is_open or Engine.get_physics_frames() - closed_at <= 1


func _exit_tree() -> void:
	if is_open:
		Engine.time_scale = 1.0  # 開いたままシーンを作り直しても、遅いままにしない


func _process(_delta: float) -> void:
	if not is_open:
		return
	var pl := get_tree().get_first_node_in_group("player") as Player
	if get_tree().paused or pl == null or pl.is_dead():
		close(false)
		return
	var stick := Input.get_vector("cam_left", "cam_right", "cam_up", "cam_down")
	var p := pick(stick)
	if p != "" and p != selected:
		selected = p
		queue_redraw()
	if Input.is_action_just_pressed("ui_cancel"):
		close(false)
	elif Input.is_action_just_pressed("jump") or Input.is_action_just_pressed("weapon_wheel"):
		close(true)
	elif _hold_mode and not Input.is_action_pressed("wheel_hold"):
		close(true)


func _draw() -> void:
	var c := size * 0.5
	draw_circle(c, RADIUS + 70.0, COLOR_BG)
	var font := get_theme_default_font()
	for i in ORDER.size():
		var id: String = ORDER[i]
		var a := PI * 0.5 * i
		var pos := c + Vector2(sin(a), -cos(a)) * RADIUS
		var col := COLOR_SELECTED if id == selected else COLOR_ITEM
		draw_circle(pos, 46.0, Color(col, 0.25 if id != selected else 0.45))
		var text: String = Weapons.LABELS[id]
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26).x
		draw_string(font, pos + Vector2(-tw * 0.5, 9), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, col)
	var now: String = "今：" + str(Weapons.LABELS[current])
	var nw := font.get_string_size(now, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	draw_string(font, c + Vector2(-nw * 0.5, 7), now, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, COLOR_ITEM)
	var hint := "右スティックで選ぶ　× で決定　○ でやめる"
	var hw := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	draw_string(font, c + Vector2(-hw * 0.5, RADIUS + 110.0), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, COLOR_ITEM)
