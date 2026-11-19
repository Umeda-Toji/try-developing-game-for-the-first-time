# Godot 4.7.2 / GDScript
# res://tests/weapon_test.gd
# 武器の持ち替え（G-01）・武器の輪（G-02）の確認。遊ぶときは不要。
# 実行: godot --path . --headless --fixed-fps 60 -- --weapon-test
#  （20m四方の部屋。敵は動かさない）
#  1. 最初は剣（手に剣、銃は見えない、背中の剣も見えない）
#  2. 1 で AR に持ち替え：20フレームかかる。持ち替え中も回避はできるが、攻撃（パリィ）はできない
#  3. AR を持つと、手に銃・背中に剣。銃は手のそばにあり、前を向いている。右下に「AR」
#  4. 銃のときは、攻撃ボタンで剣の攻撃が出ない
#  5. 武器の輪：R3 で開く → ゲームが1/4の速さ・プレイヤーは動かない → 右スティックで選んで × で決定（ジャンプしない）
#  6. ○ でやめると持ち替えない。銃のときは△を20フレーム押し続けると開き、離すと閉じる
#  7. 右スティックの向き：上＝剣、右＝AR、下＝SMG、左＝SG
#  8. F で剣に戻すと、剣の攻撃が出る
extends Node

var _main: Node
var _p: Player
var _w: Weapons
var _t := 0
var _step := 0
var _results := {}
var _f := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -100
	_main = get_parent()
	_p = _main.player
	_w = _p.weapons
	for e in _main.enemies:
		e.aggro_range = 0.0


func _physics_process(_delta: float) -> void:
	_t += 1
	if _t > 2000 and _step < 99:
		_results["時間内に終わる（step %d）" % _step] = false
		_finish()
		return
	match _step:
		0:
			if _t == 10:
				var sw: Node3D = _w._hand_sword
				_results["最初は剣（手に剣・銃は見えない・背中の剣は見えない）"] = (
					_w.current == "sword" and sw.visible and not _w._back_sword.visible and not (_w._guns["ar"] as Node3D).visible)
				_results["右スティックの向き：上＝剣、右＝AR、下＝SMG、左＝SG"] = (
					WeaponWheel.pick(Vector2(0, -1)) == "sword" and WeaponWheel.pick(Vector2(1, 0)) == "ar"
					and WeaponWheel.pick(Vector2(0, 1)) == "smg" and WeaponWheel.pick(Vector2(-1, 0)) == "sg" and WeaponWheel.pick(Vector2(0.2, 0.1)) == "")
				Input.action_press("weapon_ar")
			if _t == 12:
				Input.action_release("weapon_ar")
				_f["swap_start"] = _t
			if _t == 15:
				_results["1 で持ち替えが始まる"] = _w.is_swapping() and _w.target == "ar"
				Input.action_press("attack_light")
			if _t == 17:
				Input.action_release("attack_light")
				_results["持ち替え中は攻撃（パリィ）が出ない"] = _p.state != Player.State.ATTACK
				Input.action_press("dodge")
			if _t == 19:
				Input.action_release("dodge")
			if _t == 20:
				_results["持ち替え中も回避はできる"] = _p.state == Player.State.DODGE
			if _w.current == "ar" and not _f.has("swap_end"):
				_f["swap_end"] = _t
				_results["持ち替えは %d フレーム前後で終わる（%d）" % [Weapons.SWAP_FRAMES, _f["swap_end"] - _f["swap_start"]]] = absi(int(_f["swap_end"]) - int(_f["swap_start"]) - Weapons.SWAP_FRAMES) <= 2
			if _t == 60:
				var g: Node3D = _w._guns["ar"]
				var skel := _p.model.find_child("Skeleton3D", true, false) as Skeleton3D
				var hand := skel.global_transform * skel.get_bone_global_pose(skel.find_bone("hand_r")).origin
				var fwd := -_p.global_basis.z
				_results["AR を持つと、手に銃・背中に剣（剣は手から消える）"] = g.visible and _w._back_sword.visible and not _w._hand_sword.visible
				_results["銃は手のそばにあり（%.2f m）、前を向いている（%.2f）" % [g.global_position.distance_to(hand), g.global_basis.x.normalized().dot(fwd)]] = (
					g.global_position.distance_to(hand) < 0.3 and g.global_basis.x.normalized().dot(fwd) > 0.9)
				_results["右下に「AR」と弾の数が出る（%s）" % _main.battle_hud.weapon_label.text] = _main.battle_hud.weapon_label.text.begins_with("AR")
				Input.action_press("attack_light")
			if _t == 62:
				Input.action_release("attack_light")
			if _t == 66:
				_results["銃のときは攻撃ボタンで剣の攻撃が出ない"] = _p.state != Player.State.ATTACK
				Input.action_press("weapon_wheel")
			if _t == 68:
				Input.action_release("weapon_wheel")
				_step = 1
				_t = 0
		1:  # 武器の輪：R3 で開いて、左（SG）を選んで × で決定
			var wheel: WeaponWheel = _main.weapon_wheel
			if _t == 2:
				_results["R3 で武器の輪が開き、ゲームが1/4の速さになる"] = wheel.is_open and is_equal_approx(Engine.time_scale, WeaponWheel.SLOW_SCALE)
				_f["pos"] = _p.global_position
				Input.action_press("move_forward")
				Input.action_press("cam_left")
			if _t == 8:
				Input.action_release("move_forward")
				_results["武器の輪を開いている間は、プレイヤーは動かない"] = _p.global_position.distance_to(_f["pos"]) < 0.01
				_results["右スティックを左に倒すと SG を選ぶ（%s）" % wheel.selected] = wheel.selected == "sg"
				Input.action_press("jump")
			if _t == 10:
				Input.action_release("jump")
				Input.action_release("cam_left")
			if _t == 14:
				_results["× で決定して閉じ、速さが戻る・ジャンプはしない"] = (
					not wheel.is_open and is_equal_approx(Engine.time_scale, 1.0) and _w.target == "sg" and _p.jumps_used == 0)
			if _t == 60:
				_results["SG に持ち替わる"] = _w.current == "sg"
				Input.action_press("weapon_wheel")
			if _t == 62:
				Input.action_release("weapon_wheel")
				Input.action_press("cam_up")
			if _t == 66:
				Input.action_release("cam_up")
				Input.action_press("ui_cancel")
			if _t == 68:
				Input.action_release("ui_cancel")
			if _t == 72:
				_results["○ でやめると、持ち替えない"] = not wheel.is_open and not _w.is_swapping() and _w.current == "sg"
				Input.action_press("wheel_hold")
			if _t > 72 and _t < 72 + Player.WHEEL_HOLD_FRAMES + 6 and wheel.is_open and not _f.has("hold_open"):
				_f["hold_open"] = _t - 72
			if _t == 72 + Player.WHEEL_HOLD_FRAMES + 8:
				_results["銃のときは△を押し続けると武器の輪が開く（%s フレーム）" % str(_f.get("hold_open", "開かない"))] = _f.has("hold_open") and wheel.is_open
				Input.action_release("wheel_hold")
			if _t == 72 + Player.WHEEL_HOLD_FRAMES + 12:
				_results["△を離すと閉じる"] = not wheel.is_open
				Input.action_press("weapon_sword")
			if _t == 72 + Player.WHEEL_HOLD_FRAMES + 14:
				Input.action_release("weapon_sword")
				_step = 2
				_t = 0
		2:
			if _t == Weapons.SWAP_FRAMES + 10:
				_results["F で剣に戻る（手に剣・背中の剣は消える）"] = _w.current == "sword" and _w._hand_sword.visible and not _w._back_sword.visible
				Input.action_press("attack_light")
			if _t == Weapons.SWAP_FRAMES + 12:
				Input.action_release("attack_light")
			if _t == Weapons.SWAP_FRAMES + 16:
				_results["剣に戻ると、剣の攻撃が出る"] = _p.state == Player.State.ATTACK
				_finish()


func _finish() -> void:
	_step = 99
	Engine.time_scale = 1.0
	for a in ["move_forward", "cam_left", "cam_up", "jump", "wheel_hold", "attack_light"]:
		Input.action_release(a)
	print("==== 武器のテスト結果 ====")
	for k in _results.keys():
		print("%s: %s" % [k, str(_results[k])])
	_main.quit_game()
