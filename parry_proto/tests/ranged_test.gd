# Godot 4.7.2 / GDScript
# res://tests/ranged_test.gd
# 飛び道具の敵（E-14 魔法使い）の確認。遊ぶときは不要。
# 実行: godot --path . --headless --fixed-fps 60 -- --ranged-test
#  1. 数値が表どおり・武器を持たない
#  2. 近づくと下がる（距離を保つ）
#  3. 撃った弾に何もしないと当たる（ダメージ12）
#  4. 弾が近づいたら攻撃する → パリィで跳ね返り、魔法使いに当たる（ダメージ20・体幹35）
#  5. 弾が近づいたら回避する → すり抜けて、ダメージを受けない
#  ほかの敵は片付ける
extends Node

const PRESS_DISTANCE := 1.6     # 弾がこの距離（m）まで来たらボタンを押す
const STEP_TIMEOUT := 400
const CASTER_POS := Vector3(-1, 0.1, -5.0)

var _main: Node
var _player: Player
var _caster: Enemy
var _frame := 0
var _step := 0
var _step_start := 0
var _results := {}
var _release: Array[String] = []
var _hp_before := 0
var _caster_hp_before := 0
var _shot: Projectile = null
var _had_shot := false          # この手順で弾を見つけたか（弾が消えると _shot は null と同じになるため）
var _pressed := false
var _dist_before := 0.0
var _wall_shot: Projectile
var _max_wall_z := 0.0
var _shots_before := 0


func _ready() -> void:
	process_physics_priority = -100  # プレイヤーより先に入力を入れる
	_main = get_parent()
	_player = _main.player
	_caster = _main.caster
	_main.enemies[0].aggro_range = 0.0
	_main.boss.aggro_range = 0.0
	for e in [_main.heavy, _main.swift]:
		_main.enemies.erase(e)
		e.queue_free()


func _physics_process(_delta: float) -> void:
	_frame += 1
	for a in _release:
		Input.action_release(a)
	_release.clear()
	var t := _frame - _step_start
	match _step:
		0:
			var c := _caster
			_results["魔法使いの数値（HP40・体幹40・予兆40・ダメージ12・距離5〜8m）"] = (
				c.ranged and c.max_hp == 40 and c.max_posture == 40.0 and c.telegraph_frames == 40
				and c.damage == 12 and c.keep_distance_min == 5.0 and c.keep_distance_max == 8.0)
			_results["魔法使いは武器を持たない"] = c.model.find_child("Sword", true, false) == null
			# 近づきすぎ（3m）
			_place(3.0)
			_dist_before = _distance()
			_next()
		1:
			if t == 40:
				_results["近づくと下がる（%.1fm → %.1fm）" % [_dist_before, _distance()]] = _distance() > _dist_before + 0.5
				_place(6.5)
				_hp_before = _player.hp
				_next()
		2:  # 何もしない → 当たる
			_watch_shot()
			if _had_shot and not _shot_alive():
				_results["弾に当たるとダメージ12（%d → %d）" % [_hp_before, _player.hp]] = _player.hp == _hp_before - 12
				_player.hp = Player.MAX_HP
				_place(6.5)
				_caster_hp_before = _caster.hp
				_next()
			elif t > STEP_TIMEOUT:
				_fail("弾に当たる")
		3:  # 攻撃でパリィ → 跳ね返る
			_watch_shot()
			if _shot_alive() and not _pressed and _shot_distance() < PRESS_DISTANCE:
				_press("attack_light")
				_pressed = true
			if _shot_alive() and _shot.reflected:
				_results["攻撃の出始めで弾を跳ね返す"] = true
			if _caster.hp < _caster_hp_before:
				_results["跳ね返した弾が魔法使いに当たる（HP %d → %d・体幹 %d）" % [_caster_hp_before, _caster.hp, int(_caster.posture)]] = (
					_caster.hp == _caster_hp_before - 20 and _caster.posture >= 35.0)
				_results["パリィしたのでプレイヤーは無傷"] = _player.hp == Player.MAX_HP
				_caster.hp = _caster.max_hp
				_caster.posture = 0.0
				_place(6.5)
				_next()
			elif t > STEP_TIMEOUT:
				_fail("弾を跳ね返す")
		4:  # 回避ですり抜ける
			_watch_shot()
			if _shot_alive() and not _pressed and _shot_distance() < PRESS_DISTANCE:
				Input.action_press("move_left")  # 横へ回避
				_press("dodge")
				_pressed = true
			if _pressed and (not _shot_alive() or _shot_distance() > 3.0):
				Input.action_release("move_left")
				_results["回避で弾をすり抜ける（HP %d）" % _player.hp] = _player.hp == Player.MAX_HP
				# 次：壁に向かって撃った弾は、壁を通り抜けない
				var p := Projectile.new()
				p.speed = 12.0
				p.shooter = _caster
				p.attack = {"damage": 1, "hitstop": 0}
				_main.add_child(p)
				p.global_position = Vector3(0, 1.3, 8.0)   # 部屋の壁（z 10、厚さ0.5m）の手前
				p.direction = Vector3.BACK                  # +Z（壁の方）
				_wall_shot = p
				_next()
			elif t > STEP_TIMEOUT:
				_fail("回避ですり抜ける")
		5:  # 壁を通り抜けない
			if is_instance_valid(_wall_shot):
				_max_wall_z = maxf(_max_wall_z, _wall_shot.global_position.z)
			if t == 60:
				_results["弾は壁を通り抜けない（いちばん先 z %.2f）" % _max_wall_z] = not is_instance_valid(_wall_shot) and _max_wall_z < 9.75
				# 魔法使いとプレイヤーの間に壁を置くと、撃たない
				var wall := StaticBody3D.new()
				wall.collision_layer = 1
				var shape := CollisionShape3D.new()
				var box := BoxShape3D.new()
				box.size = Vector3(6, 4, 0.5)
				shape.shape = box
				wall.add_child(shape)
				_main.add_child(wall)
				wall.global_position = CASTER_POS + Vector3(0, 2, 3.0)
				_place(6.5)
				_caster.keep_distance_max = 100.0  # 近づいてこないように（撃てる距離ならその場で撃つ）
				_caster.move_speed = 0.0
				_shots_before = get_tree().get_nodes_in_group("projectiles").size()
				_next()
		6:
			if t == 150:
				_results["壁の向こうのプレイヤーには撃たない"] = not _caster.has_line_of_sight() and get_tree().get_nodes_in_group("projectiles").size() == _shots_before and _caster.state != Enemy.State.ATTACK
				_finish()


# 魔法使いを部屋の中ほど（CASTER_POS）に、プレイヤーをその dist m 手前（+Z 側）に置き、向かい合わせる
# （魔法使いは下がれるように、後ろ＝ -Z 側の壁まで余裕を空けておく）
func _place(dist: float) -> void:
	_caster.global_position = CASTER_POS
	_caster.velocity = Vector3.ZERO
	_caster.rotation.y = 0.0  # -Z 向き。追いかけ始めるとプレイヤーの方を向く
	_player.global_position = CASTER_POS + Vector3(0, 0, dist)
	_player.velocity = Vector3.ZERO
	_player.rotation.y = 0.0  # -Z 向き＝魔法使いの方
	_caster._cooldown = 0


func _distance() -> float:
	var d := _caster.global_position - _player.global_position
	d.y = 0.0
	return d.length()


# 新しく撃たれた弾を見つける
func _watch_shot() -> void:
	if not _had_shot:
		for p in get_tree().get_nodes_in_group("projectiles"):
			if not (p as Projectile).reflected:
				_shot = p
				_had_shot = true
				_pressed = false


func _shot_alive() -> bool:
	return _had_shot and is_instance_valid(_shot)


func _shot_distance() -> float:
	var d := _shot.global_position - (_player.global_position + Vector3.UP * 1.1)
	return d.length()


func _next() -> void:
	_step += 1
	_step_start = _frame
	_shot = null
	_had_shot = false
	_pressed = false


func _fail(what: String) -> void:
	_results[what + "（時間切れ）"] = false
	_finish()


func _press(action: String) -> void:
	Input.action_press(action)
	_release.append(action)


func _finish() -> void:
	_step = 99
	print("==== 飛び道具テスト結果 ====")
	for k in _results.keys():
		print("%s: %s" % [k, str(_results[k])])
	_main.quit_game()
