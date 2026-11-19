# Godot 4.7.2 / GDScript
# res://tests/items_test.gd
# 回復・強化アイテム（W-15 ④-2）の確認。遊ぶときは不要。
# 実行: godot --path . --headless --fixed-fps 60 -- --items-test
#  （白砂市のエリアで動く）
#  1. 街に 回復薬8・最大HP3・最大スタミナ3・攻撃力3 がある。どれも下に床か屋上がある
#  2. 回復薬に近づくと拾う（持っている数 1、お知らせが出る）。消える
#  3. Q で使うと HP が 40 戻る。持っていないときは何も起きない。満タンのときは使わない
#  4. 3つ持っているときは、回復薬を拾わない
#  5. 最大HP+10・最大スタミナ+10・攻撃力+5% を拾うと、それぞれ増える（HPバーの最大も変わる）
#  6. 弾の箱（G-04）：種類ごとに5つ。拾うと予備の弾が増える（AR+30・SMG+35・SG+6）。上限なら拾わない
#  敵は動かさない
extends Node

var _main: Node
var _p: Player
var _step := 0
var _t := 0
var _results := {}
var _release: Array[String] = []
var _target: Pickup
var _hp_before := 0


func _ready() -> void:
	process_physics_priority = -100  # プレイヤーより先に入力を入れる
	_main = get_parent()
	_p = _main.player
	for e in _main.enemies:
		e.aggro_range = 0.0
	Discoveries.reset()


func _physics_process(_delta: float) -> void:
	_t += 1
	for a in _release:
		Input.action_release(a)
	_release.clear()
	match _step:
		0:
			if _t == 20:
				_check_layout()
				_target = _first("heal")
				_p.hp = 50
				_place(_target.global_position)
				_next()
		1:  # 回復薬を拾う
			if _t == 10:
				var toast: DiscoveryToast = _main.find_child("DiscoveryToast", true, false)
				_results["回復薬に近づくと拾う（持っている数 %d、お知らせ「%s」）" % [Discoveries.heals, toast.label.text]] = (
					Discoveries.heals == 1 and not is_instance_valid(_target) and toast.label.text.contains("回復薬"))
				_hp_before = _p.hp
				_press("use_item")
			if _t == 14:
				_results["Q で回復薬を使うと HP が %d 戻る（%d → %d）" % [Player.HEAL_AMOUNT, _hp_before, _p.hp]] = (
					_p.hp == _hp_before + Player.HEAL_AMOUNT and Discoveries.heals == 0)
				_hp_before = _p.hp
				_press("use_item")
			if _t == 18:
				_results["回復薬がないときは何も起きない"] = _p.hp == _hp_before
				Discoveries.heals = 1
				_p.hp = _p.max_hp
				_press("use_item")
			if _t == 22:
				_results["HP が満タンのときは回復薬を使わない"] = Discoveries.heals == 1
				Discoveries.heals = Discoveries.HEAL_CARRY_MAX
				_target = _first("heal")
				_place(_target.global_position)
				_next()
		2:  # いっぱいのときは拾わない
			if _t == 10:
				_results["%d つ持っているときは回復薬を拾わない" % Discoveries.HEAL_CARRY_MAX] = (
					is_instance_valid(_target) and Discoveries.heals == Discoveries.HEAL_CARRY_MAX)
				_target = _first("hp")
				_place(_target.global_position)
				_next()
		3:  # 強化
			if _t == 10:
				var hud: BattleHud = _main.battle_hud
				_results["最大HP+10 を拾うと最大HPが %d（HPバーの最大 %d）" % [_p.max_hp, int(hud.player_hp_bar.max_value)]] = (
					_p.max_hp == Player.MAX_HP + Player.UPGRADE_HP and is_instance_valid(_target) == false)
				_target = _first("stamina")
				_place(_target.global_position)
			if _t == 20:
				_results["最大スタミナ+10 を拾うと最大スタミナが %d（満タンになる）" % int(_p.max_stamina)] = (
					is_equal_approx(_p.max_stamina, Player.STAMINA_MAX + Player.UPGRADE_STAMINA) and is_equal_approx(_p.stamina, _p.max_stamina))
				_target = _first("attack")
				_place(_target.global_position)
			if _t == 30:
				var base: int = Player.ATTACKS["H1"]["damage"]
				var dmg: int = _p._make_payload(Player.ATTACKS["H1"])["damage"]
				_results["攻撃力+5%% を拾うと強攻撃のダメージが %d → %d" % [base, dmg]] = (
					is_equal_approx(_p.attack_mult, 1.0 + Player.UPGRADE_ATTACK) and dmg == int(round(base * (1.0 + Player.UPGRADE_ATTACK))))
				_target = _first("ammo_ar")
				_place(_target.global_position)
			if _t == 40:
				var a := Discoveries.ammo_of("ar")
				_results["AR の弾の箱を拾うと、予備の弾が +30（%d）" % int(a["reserve"])] = int(a["reserve"]) == 30 and not is_instance_valid(_target)
				Discoveries.ammo_of("sg")["reserve"] = int(Weapons.GUNS["sg"]["reserve_max"])
				_target = _first("ammo_sg")
				_place(_target.global_position)
			if _t == 50:
				_results["予備の弾が上限のときは、弾の箱を拾わない"] = is_instance_valid(_target) and int(Discoveries.ammo_of("sg")["reserve"]) == int(Weapons.GUNS["sg"]["reserve_max"])
				Discoveries.ammo_of("sg")["reserve"] = 30
				_place(_target.global_position + Vector3(0, 0, 0.01))
			if _t == 60:
				_results["SG の弾の箱は +6（上限 %d）" % int(Weapons.GUNS["sg"]["reserve_max"])] = int(Discoveries.ammo_of("sg")["reserve"]) == 36
				_finish()


func _check_layout() -> void:
	var counts := {"heal": 0, "hp": 0, "stamina": 0, "attack": 0, "ammo_ar": 0, "ammo_smg": 0, "ammo_sg": 0}
	var bad: Array[String] = []
	var space := _p.get_world_3d().direct_space_state
	for item in get_tree().get_nodes_in_group("pickups"):
		counts[item.kind] += 1
		var pos: Vector3 = item.global_position
		var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 1.0, pos + Vector3.DOWN * 1.0, 1)
		var h := space.intersect_ray(q)
		if h.is_empty():
			bad.append("%s（%s）" % [item.name, str(pos)])
	_results["街に 回復薬%d・最大HP%d・最大スタミナ%d・攻撃力%d（下に床がない：%s）" % [counts["heal"], counts["hp"], counts["stamina"], counts["attack"], str(bad)]] = (
		counts["heal"] == CityBuilder.HEAL_ITEMS and counts["hp"] == 3 and counts["stamina"] == 3 and counts["attack"] == 3 and bad.is_empty())
	_results["弾の箱が種類ごとに %d つ（AR %d・SMG %d・SG %d）" % [CityBuilder.AMMO_CRATES, counts["ammo_ar"], counts["ammo_smg"], counts["ammo_sg"]]] = (
		counts["ammo_ar"] == CityBuilder.AMMO_CRATES and counts["ammo_smg"] == CityBuilder.AMMO_CRATES and counts["ammo_sg"] == CityBuilder.AMMO_CRATES)


# その種類の、まだあるアイテムのうち最初のもの
func _first(kind: String) -> Pickup:
	for item in get_tree().get_nodes_in_group("pickups"):
		if is_instance_valid(item) and not item.is_queued_for_deletion() and item.kind == kind:
			return item
	return null


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
	print("==== アイテムのテスト結果 ====")
	for k in _results.keys():
		print("%s: %s" % [k, str(_results[k])])
	_main.quit_game()
