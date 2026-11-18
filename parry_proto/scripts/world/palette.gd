# Godot 4.7.2 / GDScript
# res://scripts/world/palette.gd
#
# 世界の色・光・霧（W-07）。ここを変えれば、エリア全体の色が変わる
#  ・くすんだベージュ・灰色・錆の茶色、落ち着いた緑、明るく淡い空（WORLD_PROMPT.md 3.3）
#  ・昼。やわらかい太陽の光が1つ、遠くが少しかすむ普通の霧（ボリュームフォグは使わない）
class_name Palette
extends RefCounted

# ---- 地面・建物 ----
const GROUND := Color(0.6, 0.57, 0.5)          # 道（くすんだベージュ灰）
const CONCRETE := Color(0.66, 0.65, 0.62)      # 建物（灰色のコンクリート）
const BEIGE := Color(0.74, 0.68, 0.57)         # 建物（ベージュの外壁）
const BUILDING := Color(0.68, 0.66, 0.6)       # 建物（ふつう）
const OVERPASS := Color(0.62, 0.61, 0.58)      # 高架
const OBSTACLE := Color(0.5, 0.42, 0.34)       # 倒れた本棚（古い木）
const RUST := Color(0.5, 0.33, 0.22)           # 錆
const WINDOW := Color(0.11, 0.12, 0.13)        # 割れた窓の奥（暗い）
const DOOR := Color(0.36, 0.3, 0.2)            # ホールの扉（絡んだ根）
const WATER := Color(0.36, 0.5, 0.52, 0.72)    # 水（半透明の、少し緑がかった灰青）

# ---- 植物 ----
const MOSS := Color(0.34, 0.43, 0.25)          # 苔
const GRASS := Color(0.45, 0.55, 0.3)          # 草
const GRASS_DRY := Color(0.62, 0.6, 0.38)      # 枯れかけた草
const LEAF := Color(0.27, 0.4, 0.21)           # 木の葉・ツタ
const LEAF_LIGHT := Color(0.44, 0.55, 0.28)
const TRUNK := Color(0.38, 0.31, 0.24)         # 幹
const FLOWER := Color(0.92, 0.9, 0.82)         # 白い小さな花（緑眠の花）

# ---- 空・光・霧 ----
const SKY_TOP := Color(0.6, 0.73, 0.86)
const SKY_HORIZON := Color(0.86, 0.88, 0.87)
const SUN := Color(1.0, 0.96, 0.88)
const SUN_ENERGY := 2.2
const SUN_ROTATION_DEG := Vector3(-48, -35, 0)
const AMBIENT_ENERGY := 0.6
const AMBIENT_COLOR := Color(0.42, 0.45, 0.48)  # 日かげの色（空の色と混ぜる）
const AMBIENT_SKY_CONTRIBUTION := 1.0        # 日かげの光は、写真の空から取る
const SATURATION := 1.0                      # 色の鮮やかさ（色調補正）
const CONTRAST := 1.05
const FOG := Color(0.82, 0.85, 0.85)
const FOG_DENSITY := 0.008
const EXPOSURE := 1.0                       # 全体の明るさ（トーンマップ）
const OUTER_GROUND := Color(0.5, 0.48, 0.42) # エリアの外の地面（遠くの景色）
const SKY := SKY_HORIZON                     # 部屋（自動テスト用）の背景
const SKY_HDRI := "res://textures/sky/aristea_wreck_puresky_2k.hdr"  # 写真の空（Poly Haven、CC0）
const SKY_ENERGY := 1.0
