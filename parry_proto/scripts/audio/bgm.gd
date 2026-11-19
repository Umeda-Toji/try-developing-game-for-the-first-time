# Godot 4.7.2 / GDScript
# res://scripts/audio/bgm.gd
#
# BGM（F-07）
#  ・ゲームが始まったら「探索の曲」を流す（A-01。11/19）。敵に気づかれる（追いかけてくる敵がいる）と、
#    BATTLE_IN_FRAMES かけて「通常の曲（戦闘）」へ。追いかけてくる敵がいなくなって CALM_FRAMES たつと、探索の曲へ戻す
#  ・ボスが第2形態になったら「ボスの曲」へ切り替える（クロスフェード）。その後はボスの曲のまま
#  ・勝ち負けが決まったら、ゆっくり小さくして止める
#  ・ポーズ中は少し小さくする（ポーズ中も止めずに流す）
#  ・音量の変化はフレーム数で数える（N-03 にそろえる。判定には関係しない）
#  ・曲は res://music/ にある CC0 の曲。ループの設定は .import ファイル（loop / edit/loop_mode）でしてある
#  ・ファイルが無くてもエラーにせず、鳴らさないだけにする
class_name Bgm
extends Node

const TRACKS := {
	"explore": "res://music/contemplation.mp3",        # Contemplation（Joth）。探索中の静かな曲
	"battle": "res://music/battle_theme_a_loop.ogg",   # Battle Theme A（cynicmusic、ループ版 Ferk）
	"boss": "res://music/epic_boss_battle_loop.wav",   # Epic Boss Battle（Juhani Junkala）
}
const VOLUME_DB := -10.0           # BGM の基本の音量（効果音より小さめ）
const PAUSE_DUCK_DB := -8.0        # ポーズ中はこれだけ小さくする
const SILENT_DB := -60.0           # ほぼ聞こえない音量（フェードの端）
const CROSSFADE_FRAMES := 90       # 曲の切り替えにかけるフレーム（1.5秒）
const FADE_OUT_FRAMES := 120       # 勝ち負けが決まってから消えるまで（2秒）
const BATTLE_IN_FRAMES := 60       # 敵に気づかれてから、戦闘の曲になるまで
const CALM_FRAMES := 180           # 追いかけてくる敵がいなくなってから、探索の曲に戻すまで

var current := ""                  # 今流している曲（"explore" ／ "battle" ／ "boss" ／ ""）
var boss: Node = null              # main.gd が渡す。第2形態になったかを見る
var enemies: Array = []            # main.gd が渡す。追いかけてくる敵がいるかを見る
var _calm_frames := 0              # 追いかけてくる敵がいなくなってからのフレーム

var _players := {}                 # 曲の名前 → AudioStreamPlayer
var _fade := {}                    # 曲の名前 → {"from": dB, "to": dB, "frame": 今, "total": 全体, "stop": 終わったら止めるか}
var _muted := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # ポーズ中もフェードを進める
	for name in TRACKS.keys():
		var path: String = TRACKS[name]
		if not ResourceLoader.exists(path):
			continue
		var p := AudioStreamPlayer.new()
		p.name = "Bgm_" + name
		p.bus = "BGM"  # 設定の「BGM」の音量（O-01）
		p.stream = load(path)
		p.volume_db = SILENT_DB
		add_child(p)
		_players[name] = p


func start() -> void:
	play_track("explore", 1)


# 追いかけてくる（戦っている）敵がいるか：生きていて、立ち止まっていない敵
func enemy_engaged() -> bool:
	for e in enemies:
		if e != null and is_instance_valid(e) and not e.call("is_dead") and int(e.get("state")) != Enemy.State.IDLE:
			return true
	return false


# name の曲に切り替える（今の曲は frames かけて小さくして止め、新しい曲は frames かけて大きくする）
func play_track(name: String, frames: int = CROSSFADE_FRAMES) -> void:
	if _muted or name == current or not _players.has(name):
		return
	if current != "":
		_start_fade(current, SILENT_DB, frames, true)
	current = name
	var p: AudioStreamPlayer = _players[name]
	p.volume_db = SILENT_DB
	p.play()
	_start_fade(name, VOLUME_DB, frames, false)


# 勝ち負けが決まったとき：ゆっくり小さくして止める
func fade_out(frames: int = FADE_OUT_FRAMES) -> void:
	if current != "":
		_start_fade(current, SILENT_DB, frames, true)
	current = ""


# ゲームを終える前に呼ぶ（main.gd の quit_game()）。鳴ったまま終わると警告が出るため
func stop_all() -> void:
	_muted = true
	current = ""
	_fade.clear()
	for p in _players.values():
		(p as AudioStreamPlayer).stop()


func is_playing(name: String) -> bool:
	return _players.has(name) and (_players[name] as AudioStreamPlayer).playing


func is_loaded(name: String) -> bool:
	return _players.has(name)


func _start_fade(name: String, to_db: float, frames: int, stop_at_end: bool) -> void:
	var p: AudioStreamPlayer = _players[name]
	_fade[name] = {"from": p.volume_db, "to": to_db, "frame": 0, "total": maxi(frames, 1), "stop": stop_at_end}


func _physics_process(_delta: float) -> void:
	if boss != null and is_instance_valid(boss) and boss.call("is_phase2") and current != "boss" and current != "":
		play_track("boss")
	elif not _muted and not get_tree().paused and (current == "explore" or current == "battle"):
		if enemy_engaged():
			_calm_frames = 0
			if current == "explore":
				play_track("battle", BATTLE_IN_FRAMES)
		else:
			_calm_frames += 1
			if current == "battle" and _calm_frames >= CALM_FRAMES:
				play_track("explore")
	var vd := get_tree().get_first_node_in_group("vista_director") as VistaDirector
	var in_vista := vd != null and vd.active  # 眺めを映している間は、止めていても音を下げない
	var duck := PAUSE_DUCK_DB if get_tree().paused and not in_vista else 0.0
	for name in _players.keys():
		var p: AudioStreamPlayer = _players[name]
		if _fade.has(name):
			var f: Dictionary = _fade[name]
			f["frame"] = int(f["frame"]) + 1
			var t := float(f["frame"]) / float(f["total"])
			p.volume_db = lerpf(f["from"], f["to"], t)
			if f["frame"] >= f["total"]:
				_fade.erase(name)
				if f["stop"]:
					p.stop()
		elif name == current:
			p.volume_db = VOLUME_DB + duck
