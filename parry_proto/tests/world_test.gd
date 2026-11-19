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
#  9. 記録の断片（W-15）：街に10ある（建物の中ではなく、下に地面がある）／近づくと「1 / 10」と出る／同じ断片は2度数えない
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
				_p.global_position = Vector3(CityBuilder.CITY_MAX.x + 20.0, 3.0, 0.0)  # 街の外（床がない）
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
				_check_fragments()
				Discoveries.reset()
				_sign = get_tree().get_nodes_in_group("lore_fragments")[0]
				_place(_sign.global_position + Vector3(0, 0.1, 2.0))
				_next()
		8:  # 記録の断片を読む
			if _t == 30:
				var toast := _main.get_node("DiscoveryToast") if _main.has_node("DiscoveryToast") else _main.find_child("DiscoveryToast", true, false)
				_results["記録の断片を読むと「1 / %d」と出る（%s）" % [CityBuilder.FRAGMENTS.size(), toast.label.text]] = (
					Discoveries.fragments.size() == 1 and toast.label.text.contains("1 / %d" % CityBuilder.FRAGMENTS.size()) and toast.label.modulate.a > 0.5)
				_place(Vector3(0, 0.1, 30))
			if _t == 60:
				_place(_sign.global_position + Vector3(0, 0.1, 2.0))
			if _t == 90:
				_results["同じ断片は2度数えない"] = Discoveries.fragments.size() == 1
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
		var expect: float = points[name][1] + WorldBuilder.ground_y(xz.x, xz.z)  # 起伏（T-01）の上なら、その高さ
		var from := Vector3(xz.x, 5.5, xz.z)
		var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 20.0, 1)
		var hit := _p.get_world_3d().direct_space_state.intersect_ray(q)
		if hit.is_empty() or absf((hit["position"] as Vector3).y - expect) > 0.05:
			ok = false
			bad.append(name)
	_results["道の床がつながっている（だめ：%s）" % str(bad)] = ok
	_check_terrain()
	# 廃墟の飾り（W-06）：種類ごとに MultiMesh でまとめて描いている。シードが同じなら、作り直しても同じ街になる
	var decor: Dictionary = _main.world_decor
	var kinds := ["window", "frame", "rail", "rebar", "chunk", "car", "wheel", "vine", "leaf", "block", "grass", "fern", "nettle", "weed", "shrub", "rock", "rubble", "tree", "crown", "trunk", "branch", "log", "lamp"]
	var all_kinds := kinds.all(func(k): return decor.get(k, 0) > 0)
	var missing := kinds.filter(func(k): return decor.get(k, 0) == 0)
	_results["廃墟の飾り・植物ができている（足りない：%s）" % str(missing)] = all_kinds and not get_tree().get_nodes_in_group("nature_decor").is_empty()
	var tmp := Node3D.new()
	add_child(tmp)
	var again: Dictionary = WorldBuilder.build(tmp)["decor"]
	var wname := ""
	for n in _main.get_node("World").get_children():
		if String(n.name).begins_with("Ruin_window"):
			wname = n.name
			break
	var first_a := (_main.get_node("World/" + wname) as MultiMeshInstance3D).multimesh.get_instance_transform(5)
	var first_b := (tmp.get_node("World/" + wname) as MultiMeshInstance3D).multimesh.get_instance_transform(5)
	_results["シード固定：作り直しても同じ街になる"] = again == decor and first_a.is_equal_approx(first_b)
	tmp.free()
	# 広い街（W-13）：街の地面がある・広場と落ち高架から街へ出られる（建物にふさがれていない）・川・塔
	var space := _p.get_world_3d().direct_space_state
	var city_ok := true
	for xz in [Vector2(60, 0), Vector2(-60, 80), Vector2(0, -100), Vector2(100, 120)]:
		var q3 := PhysicsRayQueryParameters3D.create(Vector3(xz.x, 70, xz.y), Vector3(xz.x, -10, xz.y), 1)
		var h3 := space.intersect_ray(q3)
		city_ok = city_ok and not h3.is_empty()
	_results["広い街：街のあちこちに地面か建物がある"] = city_ok
	var blocked: Array[String] = []
	for seg in [[Vector3(0, 1, -1), Vector3(30, 1, -1)], [Vector3(0, 1, -1), Vector3(-30, 1, -1)], [Vector3(0, 1, 45), Vector3(25, 1, 45)], [Vector3(0, 1, 45), Vector3(-25, 1, 45)]]:
		var q4 := PhysicsRayQueryParameters3D.create(seg[0], seg[1], 1)
		var h4 := space.intersect_ray(q4)
		if not h4.is_empty() and (h4["position"] as Vector3).distance_to(seg[0]) < 22.0:
			blocked.append("%s→%s で %s（%s）" % [str(seg[0]), str(seg[1]), (h4["collider"] as Node).name, str(h4["position"])])
	_results["広い街：広場と落ち高架の左右から街へ出られる（ふさがれている：%s）" % str(blocked)] = blocked.is_empty()
	var decor2: Dictionary = _main.world_decor
	_results["広い街：ビル %d・廃墟 %d・空き地 %d、川と見晴らしの塔" % [decor2.get("building", 0), decor2.get("ruin", 0), decor2.get("park", 0)]] = (
		decor2.get("building", 0) > 30 and get_tree().get_nodes_in_group("water").size() >= 2 and not get_tree().get_nodes_in_group("tower_top_ledge").is_empty())
	# 見えない壁：広場の上空から外へ向かうと当たる
	var q2 := PhysicsRayQueryParameters3D.create(Vector3(0, 50, 0), Vector3(300, 50, 0), 1)
	var hit2 := _p.get_world_3d().direct_space_state.intersect_ray(q2)
	_results["エリアの外は見えない壁で出られない"] = not hit2.is_empty() and (hit2["collider"] as Node).is_in_group("invisible_wall")


# 記録の断片：数・文章の長さ・置いた場所（建物の中ではない・下に地面がある）
func _check_fragments() -> void:
	var frags := get_tree().get_nodes_in_group("lore_fragments")
	var space := _p.get_world_3d().direct_space_state
	var bad: Array[String] = []
	for f in frags:
		var pos: Vector3 = f.global_position
		var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 30.0, pos + Vector3.DOWN * 5.0, 1)
		var h := space.intersect_ray(q)
		if h.is_empty() or (h["position"] as Vector3).y > pos.y + 0.5:
			bad.append("%s（%s）" % [f.name, str(pos)])
		if f.text.length() > 80:
			bad.append("%s の文章が長い" % f.name)
	_results["記録の断片が街に%d ある（置き場所がおかしい：%s）" % [frags.size(), str(bad)]] = frags.size() == CityBuilder.FRAGMENTS.size() and bad.is_empty()


# 起伏（T-01。6b）：広場は±1m、ホールは±0.8m、はしと噴水のまわりは平ら。敵は地面の上に立つ
func _check_terrain() -> void:
	var ranges := []
	for tt in WorldBuilder.terrains.slice(0, 2):  # 最初の2つが広場とホール（あとは広い街）
		var t: Terrain = tt
		var lo := INF
		var hi := -INF
		var x := t.area.position.x
		while x <= t.area.end.x:
			var z := t.area.position.y
			while z <= t.area.end.y:
				var h := t.height_at(x, z)
				lo = minf(lo, h)
				hi = maxf(hi, h)
				z += 0.5
			x += 0.5
		ranges.append([lo, hi])
	var plaza: Array = ranges[0]
	var hall: Array = ranges[1]
	_results["広場の起伏は±1m（%.2f〜%.2f）、ホールは±0.8m（%.2f〜%.2f）" % [plaza[0], plaza[1], hall[0], hall[1]]] = (
		WorldBuilder.terrains.size() >= 2 and plaza[0] >= -1.01 and plaza[1] <= 1.01 and hall[0] >= -0.81 and hall[1] <= 0.81
		and maxf(absf(plaza[0]), plaza[1]) > 0.2 and maxf(absf(hall[0]), hall[1]) > 0.15)
	var edge := absf(WorldBuilder.ground_y(-10.95, -1.0)) + absf(WorldBuilder.ground_y(0.0, 9.95)) + absf(WorldBuilder.ground_y(0.0, -30.05))
	_results["はし（街への出口・入口）と噴水のまわりは平ら（%.3f、噴水 %.3f）" % [edge, WorldBuilder.ground_y(0, -1)]] = edge < 0.05 and absf(WorldBuilder.ground_y(0, -1)) < 0.001
	var bad: Array[String] = []
	for e in [_main.heavy, _main.swift, _main.caster, _main.boss]:
		var g := WorldBuilder.ground_y(e.global_position.x, e.global_position.z)
		if absf(e.global_position.y - g) > 0.3:
			bad.append("%s（%.2f／地面 %.2f）" % [e.display_name, e.global_position.y, g])
	_results["広場の敵とボスは地面の上に立つ（ずれ：%s）" % str(bad)] = bad.is_empty()
	# 広い街の起伏（6c）：高さと坂、一本道と川のまわりは平ら、建物の下にすき間がない
	var city: Array = WorldBuilder.terrains.slice(2)
	var lo := INF
	var hi := -INF
	var slope := 0.0
	for t in city:
		slope = maxf(slope, t.max_slope_deg(2.0))
		var x: float = t.area.position.x
		while x <= t.area.end.x:
			var z: float = t.area.position.y
			while z <= t.area.end.y:
				var h: float = t.height_at(x, z)
				lo = minf(lo, h)
				hi = maxf(hi, h)
				z += 4.0
			x += 4.0
	_results["広い街の起伏：%d 枚、高さ %.1f〜%.1f m、いちばん急な坂 %.1f°" % [city.size(), lo, hi, slope]] = (
		city.size() >= 10 and lo >= -Terrain.HOLLOW_MAX - 0.01 and hi <= Terrain.HILL_MAX + 0.01 and hi > 2.0 and slope <= Terrain.MAX_SLOPE_DEG)
	var flat := absf(WorldBuilder.ground_y(20.0, 0.0)) + absf(WorldBuilder.ground_y(-20.0, 40.0)) + absf(WorldBuilder.ground_y(-60.0, CityBuilder.RIVER_Z.x - 0.5))
	_results["一本道のエリアと川のまわりは平ら（%.3f）" % flat] = flat < 0.01
	var gaps: Array[String] = []
	for b in get_tree().get_nodes_in_group("city_building"):
		var body := b as StaticBody3D
		var cs := body.get_child(0) as CollisionShape3D
		var sz: Vector3 = (cs.shape as BoxShape3D).size
		var bottom := body.global_position.y - sz.y * 0.5
		if bottom > 0.05:
			continue  # 上の階の部分（崩れたビル）
		for cc in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(-0.5, 0.5), Vector2(0.5, 0.5)]:
			var c: Vector2 = cc
			var gx := body.global_position.x + c.x * sz.x
			var gz := body.global_position.z + c.y * sz.z
			if WorldBuilder.ground_y(gx, gz) < bottom - 0.01:
				gaps.append(str(body.global_position))
				break
	_results["街の建物の下にすき間がない（すき間：%d）" % gaps.size()] = gaps.is_empty()


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
