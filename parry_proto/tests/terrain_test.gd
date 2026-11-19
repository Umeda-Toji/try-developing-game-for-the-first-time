# Godot 4.7.2 / GDScript
# res://tests/terrain_test.gd
# 起伏のある地面（T-01・T-02。ステップ6a の試し）の確認。遊ぶときは不要。
# 実行: godot --path . --headless --fixed-fps 60 -- --terrain-test
#  （20m四方の部屋は平らのまま。部屋から離れた所（x 100〜228）に試しの起伏を作って確かめる）
#  1. 高さは −2m〜+4m、坂はいちばん急な所でも35°まで
#  2. 当たり判定の高さと、height_at の高さが合っている
#  3. 平らにする所の中は高さ0、まわりはなめらかにつながる
#  4. プレイヤーは坂を登れる（いちばん低い所から高い所へ歩いて着く）
#  5. 坂を下るとき、地面から浮かない（ほとんどのフレームで床の上）
#  6. 敵は坂の上に立ち、プレイヤーを追って坂を動ける
#  7. 胞子玉は丘に当たると消える
extends Node

const ORIGIN := Vector2(100, -64)

var _main: Node
var _p: Player
var _zako: Enemy
var _t := 0
var _step := 0
var _results := {}
var _f := {}
var _terrain: Terrain


func _ready() -> void:
	process_physics_priority = -100
	_main = get_parent()
	_p = _main.player
	_zako = _main.enemies[0]
	for e in _main.enemies:
		e.aggro_range = 0.0
	_terrain = Terrain.new()
	_terrain.name = "TrialTerrain"
	_terrain.area = Rect2(ORIGIN, Vector2(128, 128))
	_terrain.flat_zones = [[Rect2(ORIGIN + Vector2(4, 4), Vector2(8, 8)), 4.0]]
	_terrain.build(_main)


func _physics_process(_delta: float) -> void:
	_t += 1
	_p.hp = _p.max_hp
	if _t > 2400 and _step < 99:
		_results["時間内に終わる（step %d）" % _step] = false
		_finish()
		return
	match _step:
		0:
			if _t == 5:
				# 1. 高さと坂
				var lo := INF
				var hi := -INF
				var lo_p := Vector2.ZERO
				var hi_p := Vector2.ZERO
				for i in range(0, 128, 2):
					for j in range(0, 128, 2):
						var x := ORIGIN.x + 16 + i * 0.75
						var z := ORIGIN.y + 16 + j * 0.75
						var h := _terrain.height_at(x, z)
						if h < lo:
							lo = h
							lo_p = Vector2(x, z)
						if h > hi:
							hi = h
							hi_p = Vector2(x, z)
				var slope := _terrain.max_slope_deg(1.0)
				_results["高さは −%.0f〜+%.0f m の中（%.2f〜%.2f）、いちばん急な坂 %.1f°" % [Terrain.HOLLOW_MAX, Terrain.HILL_MAX, lo, hi, slope]] = (
					lo >= -Terrain.HOLLOW_MAX - 0.01 and hi <= Terrain.HILL_MAX + 0.01 and slope <= Terrain.MAX_SLOPE_DEG and hi - lo > 2.0)
				_f["lo"] = lo_p
				_f["hi"] = hi_p
				# 2. 当たり判定の高さ
				var space := _p.get_world_3d().direct_space_state
				var worst := 0.0
				for k in 20:
					var x := ORIGIN.x + 3.3 + k * 6.1
					var z := ORIGIN.y + 5.7 + k * 5.9
					var q := PhysicsRayQueryParameters3D.create(Vector3(x, 20, z), Vector3(x, -20, z), 1)
					var hit := space.intersect_ray(q)
					if hit.is_empty():
						worst = 99.0
					else:
						worst = maxf(worst, absf((hit["position"] as Vector3).y - _terrain.height_at(x, z)))
				_results["当たり判定の高さと height_at が合っている（ずれ最大 %.2f m）" % worst] = worst < 0.15
				# 3. 平らにする所
				var inside := _terrain.height_at(ORIGIN.x + 8, ORIGIN.y + 8)
				var edge := absf(_terrain.height_at(ORIGIN.x + 12.5, ORIGIN.y + 8))
				_results["平らにする所の中は高さ0（%.2f）、すぐ外はなめらか（%.2f）" % [inside, edge]] = absf(inside) < 0.001 and edge < 0.5
				# 4. いちばん低い所に立って、高い所へ歩く
				_place(_f["lo"])
				_step = 1
				_t = 0
		1:
			_walk_toward(_f["hi"])
			if _t == 2:
				_f["start_y"] = _p.global_position.y
			var to: Vector2 = _f["hi"] - Vector2(_p.global_position.x, _p.global_position.z)
			if to.length() < 1.5:
				Input.action_release("move_forward")
				_results["坂を登って、いちばん高い所に着く（%.1f m → %.1f m）" % [float(_f["start_y"]), _p.global_position.y]] = _p.global_position.y > float(_f["start_y"]) + 2.0
				# 5. 下る
				_f["air"] = 0
				_f["frames"] = 0
				_step = 2
				_t = 0
			elif _t > 1200:
				Input.action_release("move_forward")
				_results["坂を登って、いちばん高い所に着く（着かなかった：%s）" % str(_p.global_position)] = false
				_step = 2
				_t = 0
		2:
			_walk_toward(_f["lo"])
			if _t > 5:
				_f["frames"] = int(_f["frames"]) + 1
				if not _p.is_on_floor():
					_f["air"] = int(_f["air"]) + 1
			var to2: Vector2 = _f["lo"] - Vector2(_p.global_position.x, _p.global_position.z)
			if to2.length() < 1.5 or _t > 1200:
				Input.action_release("move_forward")
				var ratio := float(_f["air"]) / maxf(float(_f["frames"]), 1.0)
				_results["坂を下るとき、地面から浮かない（浮いたフレーム %.0f%%）" % (ratio * 100.0)] = ratio < 0.05
				# 6. 敵：丘の中ほどに置いて、追わせる
				var mid: Vector2 = (_f["lo"] + _f["hi"]) * 0.5
				_zako.global_position = Vector3(mid.x, _terrain.height_at(mid.x, mid.y) + 0.3, mid.y)
				_zako.aggro_range = 40.0
				_f["zako_start"] = _zako.global_position
				_step = 3
				_t = 0
		3:
			if _t == 90:
				_results["敵は坂の上に立ち（床の上：%s）、プレイヤーを追って動ける（%.1f m 動いた）" % [_zako.is_on_floor(), _zako.global_position.distance_to(_f["zako_start"])]] = (
					_zako.global_position.distance_to(_f["zako_start"]) > 1.0
					and absf(_zako.global_position.y - _terrain.height_at(_zako.global_position.x, _zako.global_position.z)) < 0.4)
				_zako.aggro_range = 0.0
				# 7. 胞子玉を丘へ向けて飛ばす
				var hi: Vector2 = _f["hi"]
				var pr := Projectile.new()
				pr.speed = 10.0
				_main.add_child(pr)
				var from := Vector3(hi.x + 12.0, _terrain.height_at(hi.x, hi.y) - 0.5, hi.y)
				pr.global_position = from
				pr.direction = Vector3(-1, 0, 0)
				_f["proj"] = pr
			if _t == 200:
				var pr = _f["proj"]
				_results["胞子玉は丘に当たると消える"] = not is_instance_valid(pr) or (pr as Node).is_queued_for_deletion()
				_finish()


func _place(xz: Vector2) -> void:
	_p.global_position = Vector3(xz.x, _terrain.height_at(xz.x, xz.y) + 0.2, xz.y)
	_p.velocity = Vector3.ZERO
	_p._set_state(Player.State.MOVE)


# 目的地の方を向いて前へ歩く（カメラの向きに関係なく、まっすぐ進むように体を向ける）
func _walk_toward(xz: Vector2) -> void:
	var cam := get_viewport().get_camera_3d()
	var d := Vector3(xz.x - _p.global_position.x, 0, xz.y - _p.global_position.z)
	if cam != null and d.length() > 0.1:
		var rig := cam.get_parent().get_parent() as Node3D
		rig.set("yaw", atan2(-d.x, -d.z))
	Input.action_press("move_forward")


func _finish() -> void:
	_step = 99
	Input.action_release("move_forward")
	print("==== 起伏のテスト結果 ====")
	for k in _results.keys():
		print("%s: %s" % [k, str(_results[k])])
	_main.quit_game()
