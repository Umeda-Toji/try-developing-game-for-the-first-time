# Godot 4.7.2 / GDScript
# res://scripts/audio/ambience.gd
#
# 環境音（A-02。NEXT_FEATURES 1.4・ステップ4。11/19 決定）
#  ・風と鳥の音をずっと流す（白砂市のエリアのとき）
#  ・川・水路（group "water"）に近いほど、水の音を大きくする。WATER_HEAR_DISTANCE より遠いと聞こえない
#  ・どちらも音のバス Ambient を通る（設定の「環境音」の音量で変わる）
#  ・素材：Spring Spring「Birds and Wind - Ambient」、RandomMind「Sea and river wave sounds」（OpenGameArt、CC0）
class_name Ambience
extends Node

const WIND_FILE := "res://sounds/ambient_birds_wind.ogg"
const WATER_FILE := "res://sounds/ambient_river.mp3"
const WIND_DB := -14.0               # 風と鳥の音量
const WATER_NEAR_DB := -8.0          # 水のすぐそばの音量
const WATER_FAR_DB := -40.0          # 聞こえる範囲の端の音量
const WATER_HEAR_DISTANCE := 30.0    # 水の音が聞こえる距離（m）
const SILENT_DB := -80.0

var player: Node3D
var wind: AudioStreamPlayer
var water: AudioStreamPlayer
var _muted := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # ポーズ中も流す
	wind = _make("Wind", WIND_FILE)
	water = _make("Water", WATER_FILE)


func start() -> void:
	if _muted:
		return
	if wind.stream != null:
		wind.volume_db = WIND_DB
		wind.play()
	if water.stream != null:
		water.volume_db = SILENT_DB
		water.play()


# 一番近い水（の範囲の長方形）までの水平の距離（m）。水が無ければ INF
func water_distance() -> float:
	if player == null:
		return INF
	var best := INF
	var p := Vector2(player.global_position.x, player.global_position.z)
	for wn in get_tree().get_nodes_in_group("water"):
		var w := wn as Node3D
		var size: Vector3 = w.get("size")
		var c := Vector2(w.global_position.x, w.global_position.z)
		var half := Vector2(size.x, size.z) * 0.5
		var d := (p - c).abs() - half
		best = minf(best, Vector2(maxf(d.x, 0.0), maxf(d.y, 0.0)).length())
	return best


# 水の距離から、水の音量を決める
static func water_db_for(distance: float) -> float:
	if distance >= WATER_HEAR_DISTANCE:
		return SILENT_DB
	return lerpf(WATER_NEAR_DB, WATER_FAR_DB, distance / WATER_HEAR_DISTANCE)


func _physics_process(_delta: float) -> void:
	if _muted or water.stream == null or not water.playing:
		return
	water.volume_db = water_db_for(water_distance())


# 鳴っている音を止め、これ以降は鳴らさない（main.gd の quit_game()）
func stop_all() -> void:
	_muted = true
	wind.stop()
	water.stop()


func _make(name_: String, path: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = name_
	p.bus = "Ambient"
	if ResourceLoader.exists(path):
		p.stream = load(path)
	add_child(p)
	return p
