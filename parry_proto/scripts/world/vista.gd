# Godot 4.7.2 / GDScript
# res://scripts/world/vista.gd
#
# 眺めのいい場所（W-15 ④-4）
#  ・プレイヤーが RADIUS（m）より近くに立つと、初めてのときだけ VistaDirector がカメラでゆっくり景色を映す
#  ・カメラは cam_from → cam_to へ動き、見る所は look_from → look_to へ動く（どれも世界の座標）
#  ・見た眺めは Discoveries が覚えていて、リトライしても、もう映さない
class_name Vista
extends Node3D

const RADIUS := 3.0            # これより近く（水平の距離）に立つと映す（m）
const HEIGHT := 2.5            # 高さの差がこれ以内のとき（m）

var vista_id := -1
var place_name := ""           # 場所の名前（画面に出す）
var line := ""                 # 短い一文（80字以内）
var cam_from := Vector3.ZERO
var cam_to := Vector3.ZERO
var look_from := Vector3.ZERO
var look_to := Vector3.ZERO


func _ready() -> void:
	add_to_group("vistas")


func _physics_process(_delta: float) -> void:
	if Discoveries.vistas.has(vista_id):
		return
	var player := get_tree().get_first_node_in_group("player") as Player
	if player == null or player.state != Player.State.MOVE or not player.is_on_floor():
		return
	var d := player.global_position - global_position
	if Vector2(d.x, d.z).length() > RADIUS or absf(d.y) > HEIGHT:
		return
	var director := get_tree().get_first_node_in_group("vista_director") as VistaDirector
	if director != null and director.play(self):
		Discoveries.see_vista(vista_id)
