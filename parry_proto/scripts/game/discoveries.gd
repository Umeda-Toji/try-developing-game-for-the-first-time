# Godot 4.7.2 / GDScript
# res://scripts/game/discoveries.gd
#
# 見つけたもの（W-15。広い街の ④）を覚えておく（オートロード "Discoveries"）
#  ・リトライ（シーンの作り直し）をしても消えない
#  ・④-1：記録の断片（街に置いた手帳・貼り紙）。初めて読んだときに discovered を出す
#  ・④-2 アイテム、④-3 寄り道の敵、④-4 眺めのいい場所
#  ・セーブ（S-01。11/19）：見つけるたびに自動で user://save.cfg に保存する。ポーズメニューの「セーブ」でも保存できる
#    保存するもの：上の全部・回復薬の数・強化の数・難易度・最後に立っていた場所
#    自動テストのとき（起動に -- の付いた引数があるとき）は保存しない。--save-test だけはテスト用の別のファイルを使う
extends Node

signal discovered(message: String)   # 画面に短く出す文（scripts/ui/discovery_toast.gd が受け取る）

const HEAL_CARRY_MAX := 3  # 回復薬を持てる数
const SAVE_PATH := "user://save.cfg"
const TEST_SAVE_PATH := "user://save_test.cfg"
const SAVE_TEST_FLAG := "--save-test"

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
# 銃の弾（G-03）："ar" など → {"mag": 弾倉の弾, "reserve": 予備の弾}。最初は弾倉ぶんだけ
var ammo := {}
var ammo_crates := 0       # 拾った弾の箱の数（G-04）
var ammo_total := 0        # 街にある弾の箱の数（CityBuilder が入れる）
# ④-4 眺めのいい場所
var vistas := {}           # 見た眺めの番号 → true
var vista_total := 0       # 街にある眺めのいい場所の数（CityBuilder が入れる）
# 街にある数（ポーズメニューの「見つけたもの」用。CityBuilder が入れる）
var heal_total := 0
var upgrade_total := 0
var side_total := 0
# セーブ
var save_enabled := true   # false のときは保存も読み込みもしない（自動テスト）
var save_path := SAVE_PATH
var saved_position := Vector3.ZERO  # 最後に保存した場所（つづきから・リトライで、ここから始める）
var has_position := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if SAVE_TEST_FLAG in args:
		save_path = TEST_SAVE_PATH
	else:
		for a in args:
			if a.begins_with("--"):
				save_enabled = false  # 自動テストは、遊んでいる人のセーブを読まない・書かない


# 記録の断片を読んだ。初めてなら true を返して、画面に出す
func find_fragment(id: int) -> bool:
	if fragments.has(id):
		return false
	fragments[id] = true
	discovered.emit("記録の断片　%d / %d" % [fragments.size(), fragment_total])
	autosave()
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
		"ammo_ar", "ammo_smg", "ammo_sg":
			var gun := kind.trim_prefix("ammo_")
			var a := ammo_of(gun)
			a["reserve"] = mini(int(a["reserve"]) + int(Weapons.GUNS[gun]["pickup"]), int(Weapons.GUNS[gun]["reserve_max"]))
			ammo_crates += 1
			discovered.emit("%s の弾 +%d（予備 %d）" % [Weapons.LABELS[gun], int(Weapons.GUNS[gun]["pickup"]), int(a["reserve"])])
	autosave()


# 寄り道の敵を倒した
func kill_side_enemy(id: int) -> void:
	killed[id] = true
	autosave()


# 眺めのいい場所を見た（お知らせは、映し終わったときに VistaDirector が出す）
func see_vista(id: int) -> void:
	vistas[id] = true
	autosave()


# ポーズメニューに出す「見つけたもの」の文（B。11/19）
func summary_text() -> String:
	var ups := hp_ups + stamina_ups + attack_ups
	var heals_found := picked.size() - ups - ammo_crates
	var lines: Array[String] = [
		"記録の断片　%d / %d" % [fragments.size(), fragment_total],
		"強化　%d / %d（HP %d・スタミナ %d・攻撃 %d）" % [ups, upgrade_total, hp_ups, stamina_ups, attack_ups],
		"回復薬　%d / %d（いま %d つ持っている）" % [heals_found, heal_total, heals],
		"弾の箱　%d / %d" % [ammo_crates, ammo_total],
		"寄り道の敵　%d / %d" % [killed.size(), side_total],
		"眺めのいい場所　%d / %d" % [vistas.size(), vista_total],
	]
	return "\n".join(lines)


# 弾の箱を拾えるか：予備の弾が上限なら拾わない（置いたままにする）
func ammo_full(kind: String) -> bool:
	var gun := kind.trim_prefix("ammo_")
	return int(ammo_of(gun)["reserve"]) >= int(Weapons.GUNS[gun]["reserve_max"])


# 銃の弾の数（無ければ、弾倉ぶんだけ持っている状態にする）
func ammo_of(id: String) -> Dictionary:
	if not ammo.has(id):
		ammo[id] = {"mag": int(Weapons.GUNS[id]["mag"]), "reserve": 0}
	return ammo[id]


# すべて忘れる（はじめから・テスト用）。セーブのファイルは消さない
func reset() -> void:
	fragments.clear()
	picked.clear()
	heals = 0
	hp_ups = 0
	stamina_ups = 0
	attack_ups = 0
	killed.clear()
	vistas.clear()
	ammo.clear()
	ammo_crates = 0
	has_position = false


# =========================================================
# セーブ（S-01）
# =========================================================
# 自動で保存する（見つけたとき・回復薬を使ったとき）
func autosave() -> void:
	if save_enabled:
		save_game()


# 保存する。場所はプレイヤーが最後に立っていた所（水の中や空中ではない）
func save_game() -> bool:
	if not save_enabled:
		return false
	var player := get_tree().get_first_node_in_group("player") as Player
	if player != null:
		saved_position = player.safe_position
		has_position = true
	var cfg := ConfigFile.new()
	cfg.set_value("found", "fragments", fragments.keys())
	cfg.set_value("found", "picked", picked.keys())
	cfg.set_value("found", "killed", killed.keys())
	cfg.set_value("found", "vistas", vistas.keys())
	cfg.set_value("player", "heals", heals)
	cfg.set_value("player", "hp_ups", hp_ups)
	cfg.set_value("player", "stamina_ups", stamina_ups)
	cfg.set_value("player", "attack_ups", attack_ups)
	cfg.set_value("player", "difficulty", Difficulty.current)
	cfg.set_value("player", "ammo", ammo)
	cfg.set_value("player", "ammo_crates", ammo_crates)
	if has_position:
		cfg.set_value("player", "position", saved_position)
	return cfg.save(save_path) == OK


func has_save() -> bool:
	return save_enabled and FileAccess.file_exists(save_path)


# 読み込む。読めたら true（難易度も戻す）
func load_game() -> bool:
	if not has_save():
		return false
	var cfg := ConfigFile.new()
	if cfg.load(save_path) != OK:
		return false
	reset()
	for id in cfg.get_value("found", "fragments", []):
		fragments[int(id)] = true
	for id in cfg.get_value("found", "picked", []):
		picked[int(id)] = true
	for id in cfg.get_value("found", "killed", []):
		killed[int(id)] = true
	for id in cfg.get_value("found", "vistas", []):
		vistas[int(id)] = true
	heals = int(cfg.get_value("player", "heals", 0))
	hp_ups = int(cfg.get_value("player", "hp_ups", 0))
	stamina_ups = int(cfg.get_value("player", "stamina_ups", 0))
	attack_ups = int(cfg.get_value("player", "attack_ups", 0))
	var saved_ammo = cfg.get_value("player", "ammo", {})
	if saved_ammo is Dictionary:
		ammo = (saved_ammo as Dictionary).duplicate(true)
	ammo_crates = int(cfg.get_value("player", "ammo_crates", 0))
	var diff: String = cfg.get_value("player", "difficulty", Difficulty.current)
	if Difficulty.SETTINGS.has(diff):
		Difficulty.current = diff
	has_position = cfg.has_section_key("player", "position")
	if has_position:
		saved_position = cfg.get_value("player", "position")
	return true


func delete_save() -> void:
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	reset()
