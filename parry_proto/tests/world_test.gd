# Godot 4.7.2 / GDScript
# res://tests/world_test.gd
# 白砂市のエリア（W-01〜W-05）と、壁のぼり（M-05）・泳ぎ（M-06）の確認。遊ぶときは不要。
# 実行: godot --path . --headless --fixed-fps 60 -- --world-test
#  （このテストだけは、20m四方の部屋ではなくエリアで動く）
#  1. エリアができている（扉は閉じている・見えない壁・水がある）。道の床がつながっている
#  2. 高架の端から2段ジャンプ→滑空で、水路を越えて降りられる
#  3. 水路に入ると泳ぐ → 向こう岸の壁につかまって登り、通りに上がれる
#  4. 書店街の倒れた本棚（3.2m）を、ジャンプ→壁のぼりで越えられる
#  5. 泳いでいてスタミナが切れると溺れて、最後に立っていた所へ戻る（ダメージ20）
#  6. 下に落ちると戻される（ダメージ10）
#  7. 広場の敵を全部倒すと、ホールの扉が開く
#  8. 看板・端末（W-08）：7つある（文章は80字以内）／遠いと文章は出ない／近づくと出る／離れると消える
#  敵は動かさない
extends Node

const TIMEOUT := 600

var _main: Node
var _p: Player
var _door: BossDoor
var _frame := 0
var _step := 0
var _t := 0
var _results := {}
var _release: Array[String] = []
var _flags := {}
var _hp_before := 0
var _sign: SignPost


func _ready() -> void:
	process_physics_priority = -100  # プレイヤーより先に入力を入れる
	_main = get_parent()
	_p = _main.player
	_door = _main.boss_door
	for e in _main.enemies:
		e.aggro_range = 0.0


func _physics_process(_delta: float) -> void:
	_frame += 1
	_t += 1
	for a in _release:
		Input.action_release(a)
	_release.clear()
	if _p.state == Player.State.SWIM:
		_flags["swim"] = true
	if _p.state == Player.State.CLIMB:
		_flags["climb"] = true
	if _p.gliding:
		_flags["glide"] = true
	match _step:
		0:
			if _t == 20:
				_check_layout()
				_place(Vector3(0, 5.1, 31.5))  # 高架の崩れた端の手前
				Input.action_press("move_forward")
				_next()
		1:  # 高架から 2段ジャンプ → 滑空
			if _t == 3:
				_press("jump")
			if _p.jumps_used == 1 and _p.velocity.y < 0.5 and not _flags.has("j2"):
				_press("jump")
				_flags["j2"] = true
			if _p.jumps_used == 2 and _p.velocity.y < 0.0 and not _flags.has("j3"):
				Input.action_press("jump")  # 押し続けて滑空
				_flags["j3"] = true
			if _t > 10 and _p.is_on_floor():
				Input.action_release("jump")
				Input.action_release("move_forward")
				var pos := _p.global_position
				_results["高架から滑空して水路を越える（z %.1f に着地）" % pos.z] = _flags.has("glide") and pos.z < 16.0 and pos.y > -0.2 and pos.y < 0.7  # 噴水の縁（0.6m）に降りてもよい
				_flags.clear()
				_place(Vector3(0, 0.1, 24))  # 水路の手前
				Input.action_press("move_forward")
				_next()
			elif _t > TIMEOUT:
				_fail("滑空")
		2:  # 水路を泳いで渡り、向こう岸を登る
			# 登りきった後も前へ歩き続けて、岸から少し離れたら合格
			if _flags.has("climb") and _p.state == Player.State.MOVE and _p.is_on_floor() and _p.global_position.z < 15.0:
				Input.action_release("move_forward")
				var pos := _p.global_position
				_results["水路で泳ぐ"] = _flags.has("swim")
				_results["向こう岸の壁を登って通りに上がる（z %.1f, y %.1f）" % [pos.z, pos.y]] = pos.z < 16.0 and absf(pos.y) < 0.3
				_flags.clear()
				_place(Vector3(0, 0.1, -18))  # 書店街の抜け道（本棚の手前）
				Input.action_press("move_forward")
				_next()
			elif _t > TIMEOUT:
				Input.action_release("move_forward")
				_fail("泳いで渡る（swim=%s climb=%s state=%s pos=%s）" % [_flags.has("swim"), _flags.has("climb"), _p.state_name(), str(_p.global_position)])
		3:  # 本棚を登って越える
			if not _flags.has("jumped") and _p.global_position.z < -20.2:
				_press("jump")
				_flags["jumped"] = true
			if _flags.has("climb") and _p.is_on_floor() and _p.global_position.z < -22.3:
				Input.action_release("move_forward")
				_results["倒れた本棚を登って越える（z %.1f）" % _p.global_position.z] = absf(_p.global_position.y) < 0.3
				_flags.clear()
				# 溺れる：水路に入れて、スタミナを少なくする（最後に立っていた所＝本棚の向こう）
				_hp_before = _p.hp
				_p.global_position = Vector3(0, -1.9, 19)
				_p.velocity = Vector3.ZERO
				_p.stamina = 3.0
				Input.action_press("move_forward")
				_next()
			elif _t > TIMEOUT:
				Input.action_release("move_forward")
				_fail("本棚を越える（climb=%s state=%s pos=%s）" % [_flags.has("climb"), _p.state_name(), str(_p.global_position)])
		4:  # 溺れる
			if _p.hp < _hp_before:
				Input.action_release("move_forward")
				_results["スタミナが切れると溺れて戻される（HP %d → %d、z %.1f）" % [_hp_before, _p.hp, _p.global_position.z]] = (
					_p.hp == _hp_before - Player.DROWN_DAMAGE and _p.global_position.z < -20.0 and _p.state == Player.State.MOVE)
				_hp_before = _p.hp
				_p.global_position = Vector3(14.5, 3.0, 24.0)  # ビルの外側（床がない）
				_p.velocity = Vector3.ZERO
				_next()
			elif _t > TIMEOUT:
				Input.action_release("move_forward")
				_fail("溺れる")
		5:  # 落ちる
			if _p.hp < _hp_before:
				_results["下に落ちると戻される（HP %d → %d）" % [_hp_before, _p.hp]] = _p.hp == _hp_before - Player.FALL_DAMAGE and _p.global_position.y > -1.0
				# 広場の敵を全部倒す
				_results["広場の敵がいる間、扉は閉じている"] = not _door.is_open
				for e in [_main.heavy, _main.swift, _main.caster]:
					e.receive_attack({"damage": 9999, "posture": 0, "hitstop": 0}, _p)
				_next()
			elif _t > TIMEOUT:
				_fail("落ちる")
		6:
			if _t == BossDoor.OPEN_FRAMES + 10:
				_results["広場の敵を全部倒すと扉が開く（沈む）"] = _door.is_open and _door.position.y < WorldBuilder.DOOR_POS.y - WorldBuilder.DOOR_SIZE.y * 0.9
				# 看板：最初の看板（落ち高架）から遠い所に置く
				var signs := get_tree().get_nodes_in_group("sign_posts")
				var texts_ok := signs.all(func(s): return s.text != "" and s.text.length() <= 80)
				_results["看板・端末が7つある（文章は80字以内）"] = signs.size() == WorldBuilder.SIGN_POSTS.size() and signs.size() == 7 and texts_ok
				_sign = signs[0]
				_place(Vector3(0, 0.1, 30))
				_next()
		7:
			if _t == 30:
				_results["遠いと看板の文章は出ない"] = not _sign.label.visible
				_place(_sign.global_position + Vector3(0, 0.1, 2.0))  # 2m 手前
			if _t == 60:
				_results["近づくと看板の文章が出る（%s）" % _sign.text.left(10)] = _sign.label.visible and _sign.shown > 0.99
				_place(Vector3(0, 0.1, 30))
			if _t == 100:
				_results["離れると看板の文章が消える"] = not _sign.label.visible
				_finish()


func _check_layout() -> void:
	_results["エリアができている（扉・水・見えない壁）"] = (
		_door != null and not _door.is_open and not get_tree().get_nodes_in_group("water").is_empty()
		and get_tree().get_nodes_in_group("invisible_wall").size() >= 4)
	_results["スタートでプレイヤーが床に立つ"] = _p.is_on_floor() and _p.global_position.z > 38.0
	# 道の床：真ん中を上から調べて、床の高さが合っているか
	var points := {
		"落ち高架": [Vector3(4.5, 0, 41), 0.0], "花梨通り": [Vector3(0, 0, 27), 0.0], "水路の底": [Vector3(0, 0, 19), -3.0],
		"花梨通りの先": [Vector3(0, 0, 12), 0.0], "広場": [Vector3(5, 0, 5), 0.0], "書店街の抜け道": [Vector3(0, 0, -14), 0.0],
		"旧市民ホール": [Vector3(0, 0, -44), 0.0],
	}
	var ok := true
	var bad: Array[String] = []
	for name in points.keys():
		var xz: Vector3 = points[name][0]
		var expect: float = points[name][1]
		var from := Vector3(xz.x, 5.5, xz.z)
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 20.0, 1)
		var hit := _p.get_world_3d().direct_space_state.intersect_ray(q)
		if hit.is_empty() or absf((hit["position"] as Vector3).y - expect) > 0.05:
			ok = false
			bad.append(name)
	_results["道の床がつながっている（だめ：%s）" % str(bad)] = ok
	# 廃墟の飾り（W-06）：種類ごとに MultiMesh でまとめて描いている。シードが同じなら、作り直しても同じ街になる
	var decor: Dictionary = _main.world_decor
	var kinds := ["window", "frame", "rail", "rebar", "chunk", "car_body", "wheel", "vine", "leaf", "block", "grass", "fern", "nettle", "weed", "shrub", "rock", "rubble", "tree", "crown", "trunk", "branch", "log", "lamp"]
	var all_kinds := kinds.all(func(k): return decor.get(k, 0) > 0)
	var missing := kinds.filter(func(k): return decor.get(k, 0) == 0)
	_results["廃墟の飾り・植物ができている（足りない：%s）" % str(missing)] = all_kinds and not get_tree().get_nodes_in_group("nature_decor").is_empty()
	var tmp := Node3D.new()
	add_child(tmp)
	var again: Dictionary = WorldBuilder.build(tmp)["decor"]
	var first_a := (_main.get_node("World/Ruin_window") as MultiMeshInstance3D).multimesh.get_instance_transform(5)
	var first_b := (tmp.get_node("World/Ruin_window") as MultiMeshInstance3D).multimesh.get_instance_transform(5)
	_results["シード固定：作り直しても同じ街になる"] = again == decor and first_a.is_equal_approx(first_b)
	tmp.free()
	# 見えない壁：広場の上空から外へ向かうと当たる
	var q2 := PhysicsRayQueryParameters3D.create(Vector3(0, 25, 0), Vector3(40, 25, 0), 1)
	var hit2 := _p.get_world_3d().direct_space_state.intersect_ray(q2)
	_results["エリアの外は見えない壁で出られない"] = not hit2.is_empty() and (hit2["collider"] as Node).is_in_group("invisible_wall")


func _place(pos: Vector3) -> void:
	_p.global_position = pos
	_p.velocity = Vector3.ZERO
	_p.rotation.y = 0.0
	_p.stamina = Player.STAMINA_MAX
	_p._set_state(Player.State.MOVE)


func _next() -> void:
	_step += 1
	_t = 0


func _press(action: String) -> void:
	Input.action_press(action)
	_release.append(action)


func _fail(what: String) -> void:
	_results[what + "（時間切れ）"] = false
	_finish()


func _finish() -> void:
	_step = 99
	for a in ["move_forward", "jump"]:
		Input.action_release(a)
	print("==== エリアのテスト結果 ====")
	for k in _results.keys():
		print("%s: %s" % [k, str(_results[k])])
	_main.quit_game()
