# Godot 4.7.2 / GDScript
# res://scripts/world/world_materials.gd
#
# 世界の材質（W-09）。写真から作った CC0 テクスチャ（Poly Haven、textures/ フォルダ）を使う
#  ・make(種類, 色合い) で材質を作る。テクスチャは1回だけ読み込んで使い回す
#  ・種類ごとに、どのテクスチャを使うか・何mでくり返すか・苔の量を、下の表で決める
#  ・壁・地面・小物は shaders/ruin_pbr.gdshader（三方向から貼る・苔・雨の跡）
#  ・窓の奥・植物は、ふつうの StandardMaterial3D（1つずつの色を使う）
class_name WorldMaterials
extends RefCounted

const TEX_DIR := "res://textures/"
const SHADER := preload("res://shaders/ruin_pbr.gdshader")
const MOSS_TEX := "mossy_rock"

# 種類 → [テクスチャ, 1mあたりのくり返し, 上の苔, 地面近くの苔, 雨の跡]
const KINDS := {
	"concrete": ["concrete_wall_006", 0.3, 0.55, 0.35, 0.35],      # 灰色のコンクリートの建物・高架
	"plaster": ["beige_wall_002", 0.35, 0.55, 0.35, 0.4],          # ベージュの外壁
	"street": ["dirty_concrete", 0.22, 0.4, 0.0, 0.0],             # 花梨通り・落ち高架の地面
	"plaza": ["mossy_cobblestone", 0.4, 0.2, 0.0, 0.0],            # 広場の石畳
	"hall_floor": ["concrete_floor_damaged_01", 0.2, 0.35, 0.0, 0.0],  # ホールの床
	"wood": ["old_planks_02", 0.5, 0.6, 0.3, 0.1],                 # 倒れた本棚など
	"roots": ["bark_brown_02", 0.6, 0.3, 0.2, 0.0],                # ホールの扉（絡んだ根）
	"bark": ["bark_brown_02", 0.8, 0.2, 0.3, 0.0],                 # 木の幹
	"rubble": ["concrete_wall_006", 0.6, 0.45, 0.0, 0.0],          # 瓦礫・屋上の塊・柱
}

static var _textures := {}


static func make(kind: String, tint: Color = Color.WHITE, ground_y: float = 0.0) -> ShaderMaterial:
	var k: Array = KINDS[kind]
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("base_albedo", _tex(k[0], "diff"))
	mat.set_shader_parameter("base_normal", _tex(k[0], "nor_gl"))
	mat.set_shader_parameter("base_rough", _tex(k[0], "rough"))
	mat.set_shader_parameter("moss_albedo", _tex(MOSS_TEX, "diff"))
	mat.set_shader_parameter("moss_normal", _tex(MOSS_TEX, "nor_gl"))
	mat.set_shader_parameter("moss_rough", _tex(MOSS_TEX, "rough"))
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("uv_scale", k[1])
	mat.set_shader_parameter("moss_top", k[2])
	mat.set_shader_parameter("moss_low", k[3])
	mat.set_shader_parameter("streak_amount", k[4])
	mat.set_shader_parameter("ground_y", ground_y)
	return mat


# 1つずつの色だけで塗る材質（窓の奥・植物など）
static func flat(roughness: float = 0.85, translucent_leaves: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true  # 1つずつの色は、ふだんの色（sRGB）で指定しているため
	mat.roughness = roughness
	if translucent_leaves:
		# 葉：光が透けるように（裏から光が当たると明るく見える）
		mat.backlight_enabled = true
		mat.backlight = Color(0.25, 0.3, 0.12)
	return mat


static func _tex(name: String, map: String) -> Texture2D:
	var path := "%s%s/%s_%s_1k.jpg" % [TEX_DIR, name, name, map]
	if not _textures.has(path):
		_textures[path] = load(path)
	return _textures[path]
