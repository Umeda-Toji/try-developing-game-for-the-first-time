# Godot 4.7.2 / GDScript
# res://scripts/game/graphics_settings.gd
#
# 画質の切り替え（U-09）。「高画質」と「軽い」の2つ
#  ・高画質：SSAO（すき間・角の暗さ）、SSIL（跳ね返った光）、グロー（明るい所のにじみ）、
#           ボリュームフォグ（光の筋が見える霧）、細かい影（4分割）、解像度100%、アンチエイリアス（MSAA 2x）
#  ・軽い：上の重い効果をすべて切る。解像度75%、影は分割なし、普通の霧（11/18 より前の設定）
#  ・選んだ画質は user://settings.cfg に保存して、次に起動したときも同じにする
#  ・ポーズメニューの「画質」ボタンで切り替える（すぐ反映される）
class_name GraphicsSettings
extends RefCounted

const HIGH := "high"
const LOW := "low"
const LABELS := {HIGH: "高画質", LOW: "軽い"}
const SAVE_PATH := "user://settings.cfg"

# ---- 高画質の数値 ----
const SSAO_RADIUS := 1.2
const SSAO_INTENSITY := 1.6
const SSIL_INTENSITY := 0.7
const GLOW_INTENSITY := 0.35
const GLOW_BLOOM := 0.05
const VOLUMETRIC_DENSITY := 0.012
const VOLUMETRIC_ANISOTROPY := 0.55    # 太陽の方向を見ると明るく見える霧
const SHADOW_DISTANCE_HIGH := 80.0
const SHADOW_DISTANCE_LOW := 40.0
const SCALE_HIGH := 1.0
const SCALE_LOW := 0.75

static var current := HIGH
static var _loaded := false


static func load_saved() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		var q: String = cfg.get_value("graphics", "quality", HIGH)
		if LABELS.has(q):
			current = q


static func save() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("graphics", "quality", current)
	cfg.save(SAVE_PATH)


static func label() -> String:
	return LABELS[current]


# 今の画質を、環境・画面・太陽に当てはめる
static func apply(env: Environment, viewport: Viewport, sun: DirectionalLight3D, fog_density: float) -> void:
	var high := current == HIGH
	env.ssao_enabled = high
	env.ssao_radius = SSAO_RADIUS
	env.ssao_intensity = SSAO_INTENSITY
	env.ssil_enabled = high
	env.ssil_intensity = SSIL_INTENSITY
	env.glow_enabled = high
	env.glow_intensity = GLOW_INTENSITY
	env.glow_bloom = GLOW_BLOOM
	env.volumetric_fog_enabled = high
	env.volumetric_fog_density = VOLUMETRIC_DENSITY
	env.volumetric_fog_anisotropy = VOLUMETRIC_ANISOTROPY
	env.volumetric_fog_albedo = Palette.FOG
	# ボリュームフォグを使うときは、普通の霧を薄くして、かすみ過ぎないようにする
	env.fog_density = fog_density * (0.4 if high else 1.0)
	if viewport != null:
		viewport.scaling_3d_scale = SCALE_HIGH if high else SCALE_LOW
		viewport.msaa_3d = Viewport.MSAA_2X if high else Viewport.MSAA_DISABLED
	if sun != null:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS if high else DirectionalLight3D.SHADOW_ORTHOGONAL
		sun.directional_shadow_max_distance = SHADOW_DISTANCE_HIGH if high else SHADOW_DISTANCE_LOW
		sun.light_volumetric_fog_energy = 1.5 if high else 0.0
	RenderingServer.directional_soft_shadow_filter_set_quality(
		RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM if high else RenderingServer.SHADOW_QUALITY_SOFT_LOW)


static func toggle() -> void:
	current = LOW if current == HIGH else HIGH
	save()
