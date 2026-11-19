# Godot 4.7.2 / GDScript
# res://tests/gun_test.gd
# 撃つ・構え・反動・リロード（G-03。まず AR）の確認。遊ぶときは不要。
# 実行: godot --path . --headless --fixed-fps 60 -- --gun-test
#  （20m四方の部屋。敵は動かさない）
#  1. AR に持ち替えると、弾は弾倉ぶん（30）だけ、予備は0。右下に「AR 30 ／ 0」、真ん中に照準
#  2. ロックオンして撃ち続けると、6フレームに1発。敵に当たり、HP は2ずつ、体幹は1ずつ減る。敵は怯まない
#  3. 撃つとカメラが上に跳ねる（反動）。撃つ音が鳴る
#  4. 壁の向こうの敵には当たらない
#  5. 弾が切れると、弾切れの音がして撃てない。予備があれば R でリロード（120フレーム）。回避するとやり直し
#  6. 構える（右クリック）と、10フレームでカメラが寄って（1.6m）ズームする（視野45°）。歩く速さは半分。回避で構えを解く
#  7. 胞子玉を撃ち落とせる
#  8. 剣のときは撃てない
#  9. SMG は4フレームに1発・ダメージ1、SG は50フレームに1発・8粒（近くで何粒も当たる）・15mより遠くには届かない（G-04）
extends Node

var _main: Node
var _p: Player
var _w: Weapons
var _zako: Enemy
var _t := 0
var _step := 0
var _results := {}
var _f := {}
var _shots := 0
var _hits := 0       # 撃った弾（粒）が敵に当たった数の合計
var _pellets := []   # 1発ごとの粒の数


func _ready() -> void:
	process_physics_priority = -100
	_main = get_parent()
	_p = _main.player
	_w = _p.weapons
	_zako = _main.enemies[0]
	for e in _main.enemies:
		e.aggro_range = 0.0
	_w.fired.connect(func(info: Dictionary) -> void:
		_shots += 1
		_hits += int(info["hits"])
		_pellets.append(int(info["pellets"])))
	Discoveries.reset()


func _physics_process(_delta: float) -> void:
	_t += 1
	_p.hp = _p.max_hp
	if _t > 3000 and _step < 99:
		_results["時間内に終わる（step %d）" % _step] = false
		_finish()
		return
	match _step:
		0:  # 剣のときは撃てない → AR に持ち替え
			if _t == 5:
				_p.global_position = Vector3(-3, 0.1, 4)
				_zako.global_position = Vector3(-3, 0.1, -2)
				Input.action_press("fire")
			if _t == 15:
				Input.action_release("fire")
				_results["剣のときは撃てない"] = _shots == 0
				_w.request("ar")
			if _t == 15 + Weapons.SWAP_FRAMES + 5:
				var a := _w.ammo("ar")
				var hud: BattleHud = _main.battle_hud
				_results["AR の弾は弾倉ぶん（%d）、予備は0。右下に「%s」" % [int(a["mag"]), hud.weapon_label.text]] = (
					int(a["mag"]) == 30 and int(a["reserve"]) == 0 and hud.weapon_label.text.contains("30 ／ 0"))
				_results["銃のときは真ん中に照準が出る"] = hud.crosshair.visible
				_p.lock_target = _zako
				_f["hp"] = _zako.hp
				_f["posture"] = _zako.posture
				_f["pitch"] = (_main.get_node("CameraRig") as Node3D).get("pitch")
				_f["shot_snd"] = _main.sfx.play_counts["shot_ar"]
				_shots = 0
				Input.action_press("fire")
				_step = 1
				_t = 0
		1:  # 60フレーム撃ち続ける
			if _t == 3:
				_f["rig_pitch_after"] = (_main.get_node("CameraRig") as Node3D).get("pitch")
			if _t == 60:
				Input.action_release("fire")
			if _t == 62:
				var hits := int(_f["hp"]) - _zako.hp
				_results["60フレームで %d 発（6フレームに1発）" % _shots] = _shots >= 9 and _shots <= 11
				_results["敵に当たり、HP は2ずつ減る（%d 減った）" % hits] = hits == _shots * 2
				_results["体幹はダメージの半分ずつ削る（%.1f 増えた）" % (_zako.posture - float(_f["posture"]))] = _zako.posture > float(_f["posture"])
				_results["銃では敵は怯まない（状態 %s）" % _zako.state_name()] = _zako.state != Enemy.State.HITSTUN
				_results["撃つとカメラが上に跳ねる（反動）"] = float(_f["rig_pitch_after"]) > float(_f["pitch"])
				_results["撃つ音が鳴る"] = _main.sfx.play_counts["shot_ar"] > int(_f["shot_snd"])
				_results["弾倉の弾が減る（%d）" % int(_w.ammo("ar")["mag"])] = int(_w.ammo("ar")["mag"]) == 30 - _shots
				# 壁：プレイヤーと敵の間に壁を置く
				var wall := StaticBody3D.new()
				var cs := CollisionShape3D.new()
				var bx := BoxShape3D.new()
				bx.size = Vector3(4, 4, 0.5)
				cs.shape = bx
				wall.add_child(cs)
				wall.position = Vector3(-3, 1.5, 1)
				_main.add_child(wall)
				_f["wall"] = wall
				_f["hp"] = _zako.hp
				_w.ammo("ar")["mag"] = 30
			if _t == 66:
				Input.action_press("fire")
			if _t == 90:
				Input.action_release("fire")
				_results["壁の向こうの敵には当たらない"] = _zako.hp == int(_f["hp"])
				(_f["wall"] as Node).queue_free()
				# 弾切れ
				_w.ammo("ar")["mag"] = 0
				_w.ammo("ar")["reserve"] = 0
				_f["empty_snd"] = _main.sfx.play_counts["gun_empty"]
				_shots = 0
				Input.action_press("fire")
			if _t == 100:
				Input.action_release("fire")
				_results["弾切れだと撃てず、弾切れの音が鳴る"] = _shots == 0 and _main.sfx.play_counts["gun_empty"] > int(_f["empty_snd"])
				_w.ammo("ar")["reserve"] = 60
				Input.action_press("reload")
			if _t == 102:
				Input.action_release("reload")
				_results["予備があれば R でリロードが始まる（%d）" % _w.reload_left] = _w.is_reloading()
				_f["reload_t"] = _t
			if _t == 152:
				Input.action_press("dodge")
			if _t == 154:
				Input.action_release("dodge")
			if _t == 156:
				_results["回避するとリロードはやり直し（残り %d）" % _w.reload_left] = _w.reload_left >= int(Weapons.GUNS["ar"]["reload"]) - 4
				_f["restart_t"] = _t
			if _f.has("restart_t") and not _w.is_reloading() and not _f.has("reload_done"):
				_f["reload_done"] = _t - int(_f["restart_t"])
				var a := _w.ammo("ar")
				_results["リロードが終わると弾倉が満タン（%d ／ %d、%d フレーム）" % [int(a["mag"]), int(a["reserve"]), int(_f["reload_done"])]] = (
					int(a["mag"]) == 30 and int(a["reserve"]) == 30 and absi(int(_f["reload_done"]) - int(Weapons.GUNS["ar"]["reload"])) <= 6)
				_p.lock_target = null
				Input.action_press("aim")
				_step = 2
				_t = 0
		2:  # 構え
			var rig: Node3D = _main.get_node("CameraRig")
			if _t == 14:
				var spring := rig.get_node("SpringArm3D") as SpringArm3D
				var cam := rig.get_node("SpringArm3D/Camera3D") as Camera3D
				_results["構えると、カメラが寄って（%.1f m）ズームする（視野 %.0f°）" % [spring.spring_length, cam.fov]] = (
					_p.aiming and absf(spring.spring_length - 1.6) < 0.05 and absf(cam.fov - 45.0) < 0.5)
				Input.action_press("move_forward")
			if _t == 30:
				var v := Vector2(_p.velocity.x, _p.velocity.z).length()
				_results["構えている間は、歩く速さが半分（%.1f m/秒）" % v] = absf(v - Player.MOVE_SPEED * Player.AIM_WALK_MULT) < 0.2
				Input.action_release("move_forward")
				Input.action_press("dodge")
			if _t == 32:
				Input.action_release("dodge")
			if _t == 34:
				_results["回避すると構えを解く（構えのボタンを押したままでも）"] = not _p.aiming
			if _t == 60:
				_results["回避が終わっても、構えのボタンを離すまで構えない"] = not _p.aiming
				Input.action_release("aim")
				# 胞子玉：プレイヤーとザコの間に置いて、ロックオンして撃つ
				var pr := Projectile.new()
				pr.speed = 0.0
				pr.direction = Vector3.BACK
				_main.add_child(pr)
				pr.global_position = (_p.global_position + _zako.global_position) * 0.5 + Vector3.UP * float(_zako.bar_height) * 0.45
				_f["proj"] = pr
				_p.lock_target = _zako
				Input.action_press("fire")
			if _t == 75:
				Input.action_release("fire")
				_results["胞子玉を撃ち落とせる"] = not is_instance_valid(_f["proj"]) or (_f["proj"] as Node).is_queued_for_deletion()
				_w.request("smg")
				_step = 3
				_t = 0
		3:  # SMG：4フレームに1発、ダメージ1
			if _t == Weapons.SWAP_FRAMES + 5:
				_f["hp"] = _zako.hp
				_shots = 0
				_hits = 0
				_f["smg_snd"] = _main.sfx.play_counts["shot_smg"]
				Input.action_press("fire")
			if _t == Weapons.SWAP_FRAMES + 65:
				Input.action_release("fire")
				var hits := int(_f["hp"]) - _zako.hp
				_results["SMG：60フレームで %d 発（4フレームに1発）、当たった %d 発でダメージ1ずつ（%d 減った）" % [_shots, _hits, hits]] = _shots >= 14 and _shots <= 16 and _hits > 0 and hits == _hits
				_results["SMG の撃つ音が鳴る"] = _main.sfx.play_counts["shot_smg"] > int(_f["smg_snd"])
				_w.request("sg")
			if _t == Weapons.SWAP_FRAMES * 2 + 75:
				_f["hp"] = _zako.hp
				_shots = 0
				_hits = 0
				_pellets.clear()
				Input.action_press("fire")
			if _t == Weapons.SWAP_FRAMES * 2 + 135:
				Input.action_release("fire")
				var hits := int(_f["hp"]) - _zako.hp
				_results["SG：60フレームで %d 発（50フレームに1発）、1発 %s 粒。当たった %d 粒でダメージ1ずつ（%d 減った）" % [_shots, str(_pellets), _hits, hits]] = (
					_shots == 2 and _pellets.all(func(n): return n == 8) and _hits >= 2 and hits == _hits)
				# 遠く（18m）の敵には届かない
				_p.global_position = Vector3(-3, 0.1, 9)
				_zako.global_position = Vector3(-3, 0.1, -9)
				_f["hp"] = _zako.hp
				_w.ammo("sg")["mag"] = 6
			if _t == Weapons.SWAP_FRAMES * 2 + 140:
				Input.action_press("fire")
			if _t == Weapons.SWAP_FRAMES * 2 + 150:
				Input.action_release("fire")
				_results["SG は %d m より遠い敵には届かない" % int(Weapons.GUNS["sg"]["range"])] = _zako.hp == int(_f["hp"])
				_finish()


func _finish() -> void:
	_step = 99
	for a in ["fire", "aim", "move_forward", "dodge", "reload"]:
		Input.action_release(a)
	print("==== 銃のテスト結果 ====")
	for k in _results.keys():
		print("%s: %s" % [k, str(_results[k])])
	_main.quit_game()
