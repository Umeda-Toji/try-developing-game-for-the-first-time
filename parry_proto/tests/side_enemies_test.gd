# Godot 4.7.2 / GDScript
# res://tests/side_enemies_test.gd
# 街の寄り道の敵（W-15 ④-3）の確認。遊ぶときは不要。
# 実行: godot --path . --headless --fixed-fps 60 -- --side-enemies-test
#  （白砂市のエリアで動く）
#  1. 街に寄り道の敵が12体いて、どれも床の上にいる。ホールの扉の番（広場の3体）には入っていない
#  2. 遠くの寄り道の敵は止まっていて、近づくと動き出す
#  3. 近づくと気づいて追ってくる。遠くへ離れると、あきらめる
#  4. 倒すと覚えていて、作り直しても（リトライと同じ）その敵は出てこない
extends Node

var _main: Node
var _p: Player
var _step := 0
var _t := 0
var _results := {}
var _e: Enemy


func _ready() -> void:
	process_physics_priority = -100
	_main = get_parent()
	_p = _main.player
	Discoveries.reset()


func _physics_process(_delta: float) -> void:
	_t += 1
	match _step:
		0:
			if _t == 30:
				var sides: Array = _main.side_enemies
				var bad: Array[String] = []
				var space := _p.get_world_3d().direct_space_state
				for e in sides:
					var q := PhysicsRayQueryParameters3D.create(e.global_position + Vector3.UP, e.global_position + Vector3.DOWN * 2.0, 1)
					if space.intersect_ray(q).is_empty():
						bad.append("%s（%s）" % [e.name, str(e.global_position)])
				_results["街に寄り道の敵が%d体いて、床の上にいる（おかしい：%s）" % [sides.size(), str(bad)]] = sides.size() == 12 and bad.is_empty()
				_results["寄り道の敵は、ホールの扉の番に入っていない"] = _main.boss_door.guards.size() == 3 and not sides.any(func(e): return e in _main.boss_door.guards)
				_e = sides[0]
				_results["遠くの寄り道の敵は止まっている"] = _e.process_mode == Node.PROCESS_MODE_DISABLED
				# 近くに行く（気づく距離の内側）
				_place(_e.global_position + Vector3(0, 0, 6))
				_next()
		1:
			if _t == 40:
				_results["近づくと動き出して、追ってくる（状態 %s）" % _e.state_name()] = (
					_e.process_mode == Node.PROCESS_MODE_INHERIT and _e.state != Enemy.State.IDLE)
				# 気づく距離の 2.5倍より遠く（でも止まる距離 50m よりは近く）へ離れる
				_place(_e.global_position + Vector3(0, 0, 40))
				_next()
		2:
			if _t == 40:
				_results["遠くへ離れると、あきらめる（状態 %s）" % _e.state_name()] = _e.state == Enemy.State.IDLE
				_e.receive_attack({"damage": 9999, "posture": 0, "hitstop": 0}, _p)
				_next()
		3:
			if _t == 5:
				var id: int = _e.side_id
				_results["倒した寄り道の敵を覚えている（番号 %d）" % id] = Discoveries.killed.has(id)
				# 作り直す（リトライと同じ）：倒した1体だけ出てこない
				var before: int = _main.side_enemies.size()
				var made: int = _main.build_side_enemies(_main._side_spots)
				_results["作り直すと、倒した敵は出てこない（%d → %d体）" % [before, made]] = made == before - 1
				_finish()


func _place(pos: Vector3) -> void:
	_p.global_position = pos + Vector3.UP * 0.1
	_p.velocity = Vector3.ZERO
	_p._set_state(Player.State.MOVE)
	_p.hp = _p.max_hp


func _next() -> void:
	_step += 1
	_t = 0


func _finish() -> void:
	_step = 99
	print("==== 寄り道の敵のテスト結果 ====")
	for k in _results.keys():
		print("%s: %s" % [k, str(_results[k])])
	_main.quit_game()
