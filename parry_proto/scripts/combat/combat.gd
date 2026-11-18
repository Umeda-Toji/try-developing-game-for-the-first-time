# Godot 4.7.2 / GDScript
# res://scripts/combat/combat.gd
# 当たり判定の「結果」を表す共通の定数
class_name Combat
extends RefCounted

enum HitResult {
	HIT,            # 普通に当たった
	PARRIED,        # パリィされた
	DODGED,         # 回避の無敵中だった
	PERFECT_DODGED, # ジャスト回避された
	IGNORED,        # 死亡中など、無視
}
