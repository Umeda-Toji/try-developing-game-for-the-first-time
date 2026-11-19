# Godot 4.7.2 / GDScript
# res://scripts/ui/credits.gd
#
# クレジットの文章を作る（U-05）
#  ・Godot は MIT ライセンス。配るゲームには Godot の著作権表示とライセンス文を入れる必要がある
#  ・Godot が中で使っている他のソフト（FreeType など）の表示も入れる（Godot 公式ドキュメントのおすすめ）
#  ・ライセンス文は Godot 自身から取り出すので、Godot のバージョンを変えても自動で正しくなる
#  ・素材を追加したら、下の CREDITS_HEAD に書き足す
class_name Credits
extends RefCounted

# ゲーム自体のクレジット（素材を足したらここに書く）
const CREDITS_HEAD := """ParryProto（試作）

■ BGM（OpenGameArt.org、CC0 1.0）
・Battle Theme A — Alex Smith（cynicmusic.com / pixelsphere.org）、ループ版 Ferk
・Epic Boss Battle — Juhani Junkala（SubspaceAudio）
・Contemplation — Joth（探索中の曲）

■ 環境音（OpenGameArt.org、CC0 1.0）
・Birds and Wind - Ambient — Spring Spring（鳥の声：isaiah658 ／ syncopika ／ pauliuw、パブリックドメイン）
・Sea and river wave sounds — RandomMind

■ テクスチャ・空・植物などの3Dモデル（Poly Haven、https://polyhaven.com、CC0 1.0）
・concrete_wall_006 ／ beige_wall_002 ／ dirty_concrete ／ mossy_cobblestone ／
  concrete_floor_damaged_01 ／ mossy_rock ／ old_planks_02 ／ bark_brown_02
・空：aristea_wreck_puresky
・3Dモデル：fern_02 ／ nettle_plant ／ weed_plant_02 ／ shrub_02 ／ shrub_03 ／ shrub_04 ／
  rock_moss_set_01 ／ dead_tree_trunk ／ street_lamp_02

■ 効果音
Kenney（https://kenney.nl）
・Impact Sounds（パリィ・体幹ブレイク）
・RPG Audio（ヒット・ジャスト回避）
ライセンス：CC0 1.0（パブリックドメイン）。表記は必須ではないが、感謝を込めて記載

■ 3Dモデル・アニメーション
Quaternius（https://quaternius.com）
・Universal Base Characters（プレイヤー・ボスの顔）
・Modular Character Outfits - Fantasy（プレイヤー・ボスの服：Ranger）
・Universal Animation Library ／ Universal Animation Library 2（アニメーション、ザコのマネキン）
・LowPoly Medieval Weapons（剣・ハンマー・短剣）
・Stylized Nature MegaKit（敵の頭の花：Petal_1〜5）
ライセンス：CC0 1.0（パブリックドメイン）。表記は必須ではないが、感謝を込めて記載
"""


static func build_text() -> String:
	var s := CREDITS_HEAD
	s += "\n■ Godot Engine\n"
	s += "This game uses Godot Engine, available under the following license:\n\n"
	s += Engine.get_license_text() + "\n"

	s += "\n■ Godot Engine が中で使っているソフトウェア\n"
	for item in Engine.get_copyright_info():
		var name: String = item["name"]
		if name == "Godot Engine":
			continue
		var licenses: Array[String] = []
		var copyrights: Array[String] = []
		for part in item["parts"]:
			if not licenses.has(part["license"]):
				licenses.append(part["license"])
			for c in part["copyright"]:
				if not copyrights.has(c):
					copyrights.append(c)
		s += "・%s（%s）\n" % [name, ", ".join(licenses)]
		for c in copyrights:
			s += "    © %s\n" % c

	s += "\n■ ライセンスの全文\n"
	var info := Engine.get_license_info()
	for key in info.keys():
		s += "\n----- %s -----\n%s\n" % [key, info[key]]
	return s
