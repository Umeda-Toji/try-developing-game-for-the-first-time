# Godot 4.7.2 / GDScript
# res://tests/model_test.gd
# プレイヤーの3Dモデルとアニメーション（P-16）の確認。遊ぶときは不要。
# 実行: godot --path . --headless --fixed-fps 60 -- --model-test
#  敵が近づいてこないようにしてから、次を順に確かめる
#   ・使うアニメーションが全部読み込めている
#   ・止まっている／走っているときのアニメ
#   ・攻撃：当たり始めのフレームで、ちょうど「剣を一番速く振る瞬間」のポーズになる（見た目と判定がずれない）
#   ・パリィ受付中は色が付き、受付が終わると消える
#   ・回避・ヒットストップ・やられ
extends Node

var _main: Node
var _player: Player
var _model: CharacterModel
var _frame := 0
var _results := {}
var _release: Array[String] = []
var _pose_ok := true          # 攻撃中のポーズが毎tick正しいか
var _key_checked := {}        # 当たり始めのポーズを確かめた攻撃
var _tint_in_window := true   # パリィ受付中はずっと色が付いているか
var _tint_after_window := true
var _hitstop_time := -1.0


func _ready() -> void:
	process_physics_priority = 100  # プレイヤーの後に動いて、そのtickのポーズを確かめる
	_main = get_parent()
	_player = _main.player
	_model = _player.model
	for e in _main.enemies:  # 敵は動かさない
		e.aggro_range = 0.0


func _physics_process(_delta: float) -> void:
	_frame += 1
	for a in _release:
		Input.action_release(a)
	_release.clear()
	_check_attack_pose()

	match _frame:
		2:
			var clips: Array[String] = [Player.ANIM_IDLE, Player.ANIM_RUN, Player.ANIM_DODGE["clip"],
				Player.ANIM_HITSTUN["clip"], Player.ANIM_DEATH]
			for id in Player.ATTACK_ANIMS.keys():
				clips.append(Player.ATTACK_ANIMS[id]["clip"])
			var missing: Array[String] = []
			for c in clips:
				if not _model.has_clip(c):
					missing.append(c)
			_results["アニメが全部ある（足りない：%s）" % str(missing)] = missing.is_empty()
			_results["モデルに剣が付いている"] = _model.find_child("Sword", true, false) != null
			# 服のモデルには顔が無いので、素体から切り出した顔が付いているか（三角形が1つ以上ある）
			var head := _model.find_child("Head_*", true, false) as MeshInstance3D
			_results["服のモデルに顔が付いている"] = head != null and head.mesh.get_surface_count() > 0
		10:
			_results["止まっているときは待機のアニメ"] = _model.current_clip == Player.ANIM_IDLE
			Input.action_press("move_forward")
		30:
			_results["走っているときは走りのアニメ"] = _model.current_clip == Player.ANIM_RUN
			Input.action_release("move_forward")
		50:
			_press("attack_light")  # L1 → L2 → L3 とつなぐ
		62:
			_press("attack_light")
		78:
			_press("attack_light")
		130:
			_press("attack_heavy")  # H1
		190:
			_results["攻撃中のポーズが表どおり（毎tick）"] = _pose_ok
			for id in ["L1", "L2", "L3", "H1"]:
				_results["%s：当たり始めで剣を振り切るポーズ" % id] = _key_checked.get(id, false)
			_results["パリィ受付中は色が付く"] = _tint_in_window
			_results["パリィ受付が終わると色が消える"] = _tint_after_window
			_press("dodge")
		194:
			_results["回避中は前転のアニメ"] = _model.current_clip == Player.ANIM_DODGE["clip"]
		230:
			_player.hitstop_frames = 5  # ヒットストップ中はポーズが止まるか
			_hitstop_time = _model.current_time
		233:
			_results["ヒットストップ中はポーズが止まる"] = is_equal_approx(_model.current_time, _hitstop_time)
		240:
			_player.hp = 0
			_player._set_state(Player.State.DEAD)
		270:
			# 結果画面が出るとゲームが止まるので（RESULT_DELAY_FRAMES 後）、その前に確かめて終わる
			# やられのアニメは 1tick に 1/60 秒ずつ進む
			var expect := float(_player.state_frame) * CharacterModel.TICK_SEC
			_results["やられのアニメが1tickずつ進む"] = _model.current_clip == Player.ANIM_DEATH and is_equal_approx(_model.current_time, expect)
			print("==== モデルテスト結果 ====")
			for k in _results.keys():
				print("%s: %s" % [k, str(_results[k])])
			_main.quit_game()


# 攻撃中は毎tick、ポーズの位置が表どおりか確かめる
func _check_attack_pose() -> void:
	if _player.state != Player.State.ATTACK or _player.hitstop_frames > 0:
		return
	var id: String = _player._attack_id
	var atk: Dictionary = Player.ATTACKS[id]
	var anim: Dictionary = Player.ATTACK_ANIMS[id]
	if _model.current_clip != anim["clip"]:
		_pose_ok = false
	if _player.state_frame == int(atk["startup"]):
		_key_checked[id] = is_equal_approx(_model.current_time, anim["key"])
	var tinted := _model.tint_strength() > 0.0
	if _player._is_parry_window():
		_tint_in_window = _tint_in_window and tinted
	elif _player._counter_frames == 0:
		_tint_after_window = _tint_after_window and not tinted


func _press(action: String) -> void:
	Input.action_press(action)
	_release.append(action)
