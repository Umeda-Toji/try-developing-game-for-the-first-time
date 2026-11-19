# Godot 4.7.2 / GDScript
# res://scripts/game/discoveries.gd
#
# 見つけたもの（W-15。広い街の ④）を覚えておく（オートロード "Discoveries"）
#  ・リトライ（シーンの作り直し）をしても消えない。ゲームを終了すると消える
#  ・④-1：記録の断片（街に置いた手帳・貼り紙）。初めて読んだときに discovered を出す
#  ・④-2 以降で、アイテム・寄り道の敵・眺めの場所もここに足す
extends Node

signal discovered(message: String)   # 画面に短く出す文（scripts/ui/discovery_toast.gd が受け取る）

const HEAL_CARRY_MAX := 3  # 回復薬を持てる数

var fragments := {}        # 読んだ記録の断片の番号 → true
var fragment_total := 0    # 街にある記録の断片の数（CityBuilder が入れる）
# ④-2 アイテム
var picked := {}           # 拾ったアイテムの番号 → true（リトライしても戻らない）
var heals := 0             # 持っている回復薬の数
var hp_ups := 0            # 拾った「最大HP+10」の数
var stamina_ups := 0       # 拾った「最大スタミナ+10」の数
var attack_ups := 0        # 拾った「攻撃力+5%」の数
# ④-3 寄り道の敵
var killed := {}           # 倒した寄り道の敵の番号 → true（リトライしても戻らない）
# ④-4 眺めのいい場所
var vistas := {}           # 見た眺めの番号 → true
var vista_total := 0       # 街にある眺めのいい場所の数（CityBuilder が入れる）


# 記録の断片を読んだ。初めてなら true を返して、画面に出す
func find_fragment(id: int) -> bool:
	if fragments.has(id):
		return false
	fragments[id] = true
	discovered.emit("記録の断片　%d / %d" % [fragments.size(), fragment_total])
	return true


# アイテムを拾った
func take_item(id: int, kind: String) -> void:
	picked[id] = true
	match kind:
		"heal":
			heals = mini(heals + 1, HEAL_CARRY_MAX)
			discovered.emit("回復薬を拾った　%d / %d　（Q ／ 十字キー上で使う）" % [heals, HEAL_CARRY_MAX])
		"hp":
			hp_ups += 1
			discovered.emit("最大HP +%d" % Player.UPGRADE_HP)
		"stamina":
			stamina_ups += 1
			discovered.emit("最大スタミナ +%d" % int(Player.UPGRADE_STAMINA))
		"attack":
			attack_ups += 1
			discovered.emit("攻撃力 +%d%%" % int(round(Player.UPGRADE_ATTACK * 100.0)))


# 眺めのいい場所を見た（お知らせは、映し終わったときに VistaDirector が出す）
func see_vista(id: int) -> void:
	vistas[id] = true


# すべて忘れる（テスト用）
func reset() -> void:
	fragments.clear()
	picked.clear()
	heals = 0
	hp_ups = 0
	stamina_ups = 0
	attack_ups = 0
	killed.clear()
	vistas.clear()
