# Godot 4.7.2 / GDScript
# res://tests/vista_test.gd
# 眺めのいい場所（W-15 ④-4）の確認。遊ぶときは不要。
# 実行: godot --path . --headless --fixed-fps 60 -- --vista-test
#  （白砂市のエリアで動く）
#  1. 街に眺めのいい場所が3つあり、どれも下に床（屋上・橋）がある
#  2. 立つと、カメラが切り替わって景色を映す（その間はゲームが止まり、ポーズメニューは開けない）
#  3. 映し終わると、もとのカメラに戻ってゲームが動き、「眺めのいい場所 1 / 3」と出る
#  4. 同じ場所にもう一度立っても、もう映さない
#  5. 別の場所では、ジャンプのボタンで飛ばせる
extends Node

var _main: Node
var _p: Player
var _step := 0
var _t := 0
var _results := {}
var _release: Array[String] = []
var _vd: VistaDirector
var _game_cam: Camera3D


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # ゲームが止まっている間も確かめる
	process_physics_priority = -100
	_main = get_parent()
	_p = _main.player
	_vd = _main.vista_director
	for e in _main.enemies:
		e.aggro_range = 0.0
	Discoveries.reset()


func _physics_process(_delta: float) -> void:
	_t += 1
	for a in _release:
		Input.action_release(a)
	_release.clear()
	var vistas := get_tree().get_nodes_in_group("vistas")
	match _step:
		0:
			if _t == 20:
				var bad: Array[String] = []
				var space := _p.get_world_3d().direct_space_state
				for v in vistas:
					var q := PhysicsRayQueryParameters3D.create(v.global_position + Vector3.UP, v.global_position + Vector3.DOWN, 1)
					if space.intersect_ray(q).is_empty():
						bad.append("%s（%s）" % [v.name, str(v.global_position)])
				_results["眺めのいい場所が%d（下に床がない：%s）" % [vistas.size(), str(bad)]] = vistas.size() == 3 and bad.is_empty()
				_game_cam = get_viewport().get_camera_3d()
				_place(vistas[0].global_position)
				_next()
		1:
			if _t == 10:
				_results["立つと景色を映す（ゲームは止まる・カメラが変わる・ポーズできない）"] = (
					_vd.active and get_tree().paused and get_viewport().get_camera_3d() == _vd.cam and not _main.can_pause())
			if _t == 10 + VistaDirector.VISTA_FRAMES:
				var toast: DiscoveryToast = _main.find_child("DiscoveryToast", true, false)
				# 画面いっぱいの幅で、文字を真ん中に寄せる（ヘッドレスでは画面がとても小さいので、位置ではなく作りを確かめる）
				var vw := get_viewport().get_visible_rect().size.x
				_results["お知らせは画面の幅いっぱいで、真ん中寄せ（幅 %.0f／画面 %.0f）" % [toast.size.x, vw]] = (
					is_equal_approx(toast.size.x, vw) and is_equal_approx(toast.label.anchor_right, 1.0)
					and toast.label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER)
				_results["映し終わると、もとのカメラに戻ってゲームが動く（%s）" % toast.label.text] = (
					not _vd.active and not get_tree().paused and get_viewport().get_camera_3d() == _game_cam
					and Discoveries.vistas.size() == 1 and toast.label.text.contains("1 / 3"))
				_place(Vector3(vistas[0].global_position) + Vector3(0, 0.1, 0))
				_next()
		2:
			if _t == 30:
				_results["同じ場所では、もう映さない"] = not _vd.active and Discoveries.vistas.size() == 1
				_place(vistas[1].global_position)
				_next()
		3:
			if _t == 10:
				_results["別の場所でも映す"] = _vd.active
			if _t == 10 + VistaDirector.SKIP_AFTER_FRAMES + 10:
				_press("jump")
			if _t == 10 + VistaDirector.SKIP_AFTER_FRAMES + 14:
				_results["ジャンプのボタンで飛ばせる（%d フレームで終わる）" % _vd.frame] = not _vd.active and not get_tree().paused
				_finish()


func _place(pos: Vector3) -> void:
	_p.global_position = pos + Vector3.UP * 0.1
	_p.velocity = Vector3.ZERO
	_p._set_state(Player.State.MOVE)


func _next() -> void:
	_step += 1
	_t = 0


func _press(action: String) -> void:
	Input.action_press(action)
	_release.append(action)


func _finish() -> void:
	_step = 99
	Input.action_release("jump")
	print("==== 眺めのいい場所のテスト結果 ====")
	for k in _results.keys():
		print("%s: %s" % [k, str(_results[k])])
	_main.quit_game()
