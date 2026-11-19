# Godot 4.7.2 / GDScript
# res://tests/sound_test.gd
# 探索の曲・環境音・花の音（A-01〜A-03）の確認。遊ぶときは不要。
# 実行: godot --path . --headless --fixed-fps 60 -- --sound-test
#  （白砂市のエリアで動く）
#  1. 始まったときは探索の曲。曲はループする
#  2. 敵に気づかれる（追いかけてくる）と戦闘の曲になる
#  3. 追いかけてくる敵がいなくなって180フレームたつと、探索の曲に戻る
#  4. 風と鳥の音が流れている。環境音は音のバス Ambient を通る
#  5. 水の近くでは水の音が大きく、遠いと聞こえない
#  6. 敵の花が白く開くと「白の音」、赤く開くと「赤の音」が鳴る（花びらの音も）
extends Node

const TIMEOUT := 1500

var _main: Node
var _p: Player
var _zako: Enemy
var _t := 0
var _step := 0
var _results := {}
var _f := {}


func _ready() -> void:
	process_physics_priority = -100
	_main = get_parent()
	_p = _main.player
	_zako = _main.enemies[0]
	for e in _main.enemies:
		e.aggro_range = 0.0


func _physics_process(_delta: float) -> void:
	_t += 1
	_p.hp = _p.max_hp
	if _t > TIMEOUT and _step < 99:
		_results["時間内に終わる（step %d）" % _step] = false
		_finish()
		return
	var bgm: Bgm = _main.bgm
	var amb: Ambience = _main.ambience
	match _step:
		0:
			if _t == 10:
				var explore := bgm.get_node("Bgm_explore") as AudioStreamPlayer
				_results["始まったときは探索の曲（%s）" % bgm.current] = bgm.current == "explore" and bgm.is_playing("explore")
				_results["探索の曲はループする"] = explore.stream is AudioStreamMP3 and (explore.stream as AudioStreamMP3).loop
				_results["風と鳥の音が流れ、音のバス Ambient を通る"] = amb != null and amb.wind.playing and amb.wind.bus == "Ambient" and amb.water.bus == "Ambient" and (amb.wind.stream as AudioStreamOggVorbis).loop
				# 水：遠く（スタート）と、水路のそば
				_f["far_db"] = Ambience.water_db_for(amb.water_distance())
				_p.global_position = Vector3(0, 0.1, 22)  # 花梨通りの水路のそば
				_step = 1
				_t = 0
		1:
			if _t == 5:
				var near_db := Ambience.water_db_for(amb.water_distance())
				_results["水の近くでは水の音が大きい（遠く %.0f dB → 近く %.0f dB）" % [float(_f["far_db"]), near_db]] = near_db > float(_f["far_db"]) + 10.0 and near_db > -20.0
				_p.global_position = Vector3(CityBuilder.CITY_MIN.x + 20.0, 0.1, CityBuilder.CITY_MIN.y + 20.0)
			if _t == 8:
				_results["水から遠いと聞こえない（%.0f dB）" % Ambience.water_db_for(amb.water_distance())] = Ambience.water_db_for(amb.water_distance()) <= Ambience.SILENT_DB
				# ザコに気づかせる（追いかけてくる）
				_p.global_position = _zako.global_position + Vector3(0, 0, 4)
				_zako.aggro_range = 15.0
				_zako._attack_count = 0  # 次は普通の攻撃（白）
				_f["white_before"] = _main.sfx.play_counts["flower_white"]
				_f["petal_before"] = _main.sfx.play_counts["petal"]
				_step = 2
				_t = 0
		2:
			if _t == 3:
				_results["敵に気づかれると戦闘の曲になる（%s）" % bgm.current] = bgm.current == "battle"
			if _zako.is_glinting() and not _zako.is_fake_glint() and _zako.flower.open_amount >= 1.0 and not _f.has("white"):
				_f["white"] = true
				_results["花が白く開くと白の音と花びらの音が鳴る"] = (
					_main.sfx.play_counts["flower_white"] > int(_f["white_before"]) and _main.sfx.play_counts["petal"] > int(_f["petal_before"]))
				# 重装兵：次はパリィできない攻撃（赤）
				_zako.aggro_range = 0.0
				_zako._set_state(Enemy.State.IDLE)
				var heavy: Enemy = _main.heavy
				_p.global_position = heavy.global_position + Vector3(0, 0, 2.5)
				heavy.aggro_range = 15.0
				heavy._attack_count = 1
				_f["red_before"] = _main.sfx.play_counts["flower_red"]
				_step = 3
				_t = 0
		3:
			var heavy: Enemy = _main.heavy
			if heavy.is_glinting() and heavy.flower.open_amount >= 1.0 and not _f.has("red"):
				_f["red"] = true
				_results["花が赤く開くと赤の音が鳴る"] = _main.sfx.play_counts["flower_red"] > int(_f["red_before"])
				# 誰も追いかけてこないようにする → 探索の曲に戻るか
				for e in _main.enemies:
					e.aggro_range = 0.0
					if not e.is_dead():
						e._set_state(Enemy.State.IDLE)
				_p.global_position = Vector3(CityBuilder.CITY_MIN.x + 20.0, 0.1, CityBuilder.CITY_MIN.y + 20.0)
				_step = 4
				_t = 0
		4:
			for e in _main.enemies:  # 攻撃の途中だった敵も止める
				if not e.is_dead() and e.state != Enemy.State.IDLE:
					e._set_state(Enemy.State.IDLE)
			if _t == Bgm.CALM_FRAMES - 10:
				_results["追いかけてくる敵がいなくなっても、すぐには戻らない"] = bgm.current == "battle"
			if _t == Bgm.CALM_FRAMES + 10:
				_results["%d フレームたつと探索の曲に戻る（%s）" % [Bgm.CALM_FRAMES, bgm.current]] = bgm.current == "explore"
				_finish()


func _finish() -> void:
	_step = 99
	print("==== 音のテスト結果 ====")
	for k in _results.keys():
		print("%s: %s" % [k, str(_results[k])])
	_main.quit_game()
