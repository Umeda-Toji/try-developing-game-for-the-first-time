# Godot 4.7.2 / GDScript
# res://scripts/combat/sfx.gd
#
# 効果音（F-05）
#  ・GameFeel の合図を聞いて音を鳴らす（プレイヤーや敵のコードは変えなくてよい）
#      火花の合図（ヒット・パリィ・体幹ブレイク） → それぞれの音
#      スローが始まった合図（ジャスト回避）       → ジャスト回避の音
#  ・音のファイルは res://sounds/ にある。Kenney の CC0 素材（Impact Sounds ／ RPG Audio）
#    別の音にしたいときは、sounds/ にファイルを入れて、下の表のファイル名を書き換える
#  ・files に2つ以上書くと、鳴らすたびにランダムに1つ選ぶ（同じ音の繰り返しで飽きないように）
#  ・ファイルが無くてもエラーにせず、その音を鳴らさないだけにする
class_name Sfx
extends Node

# 種類ごとの音：files ファイル / volume_db 音量（0 = そのまま、マイナスで小さく）/ pitch_jitter 毎回少し高さを変える幅
const SOUNDS := {
	"hit": {"files": ["res://sounds/knifeSlice.ogg", "res://sounds/knifeSlice2.ogg"], "volume_db": -4.0, "pitch_jitter": 0.1},
	"parry": {"files": ["res://sounds/impactBell_heavy_000.ogg"], "volume_db": -6.0, "pitch_jitter": 0.04},
	"perfect_dodge": {"files": ["res://sounds/cloth1.ogg"], "volume_db": 0.0, "pitch_jitter": 0.0},
	"break": {"files": ["res://sounds/impactPlate_heavy_000.ogg"], "volume_db": -2.0, "pitch_jitter": 0.0},
}
const MAX_POLYPHONY := 4  # 同じ音が重なって鳴ってよい数（連続ヒットで前の音が切れないように）

# テスト用：種類ごとに何回鳴らしたか
var play_counts := {}

var _players := {}  # 種類 → AudioStreamPlayer
var _muted := false  # stop_all() の後は鳴らさない


func _ready() -> void:
	for kind in SOUNDS.keys():
		play_counts[kind] = 0
		var cfg: Dictionary = SOUNDS[kind]
		var streams: Array[AudioStream] = []
		for path in cfg["files"]:
			if ResourceLoader.exists(path):
				streams.append(load(path))
		if streams.is_empty():
			continue  # ファイルが無ければ、この音は鳴らさない
		var p := AudioStreamPlayer.new()
		p.name = "Sfx_" + kind
		if streams.size() == 1:
			p.stream = streams[0]
		else:
			# 複数あるときは、鳴らすたびにランダムに選ぶ（高さの揺らしは play() で行うので、ここでは揺らさない）
			var r := AudioStreamRandomizer.new()
			r.random_pitch = 1.0
			for s in streams:
				r.add_stream(-1, s)
			p.stream = r
		p.volume_db = cfg["volume_db"]
		p.max_polyphony = MAX_POLYPHONY
		add_child(p)
		_players[kind] = p
	GameFeel.spark_requested.connect(_on_spark)
	GameFeel.witch_time_changed.connect(_on_witch_time_changed)


func play(kind: String) -> void:
	if not SOUNDS.has(kind):
		push_warning("知らない効果音の種類: " + kind)
		return
	play_counts[kind] = int(play_counts[kind]) + 1
	var p: AudioStreamPlayer = _players.get(kind)
	if p == null or _muted:
		return
	var jitter: float = SOUNDS[kind]["pitch_jitter"]
	p.pitch_scale = 1.0 + randf_range(-jitter, jitter)
	p.play()


# 火花の種類（GameFeel.SPARK_*）と効果音の種類は同じ名前にしてある
func _on_spark(_pos: Vector3, kind: String) -> void:
	play(kind)


func _on_witch_time_changed(active: bool) -> void:
	if active:
		play("perfect_dodge")


# 鳴っている音をすべて止め、これ以降は鳴らさない。ゲームを終える前に呼ぶ（main.gd の quit_game()）
# （鳴ったまま終わると、終了時に「使用中のまま残った」という警告が出るため）
func stop_all() -> void:
	_muted = true
	for p in _players.values():
		(p as AudioStreamPlayer).stop()


# 音のファイルが読み込めているか（テスト用）
func is_loaded(kind: String) -> bool:
	return _players.has(kind)
