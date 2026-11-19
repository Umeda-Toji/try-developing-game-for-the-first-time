// Godot 4.7.2 / Godot Shading Language
// res://shaders/ruin_pbr.gdshader
// 廃墟の表面（リアル版。W-09）。写真から作った CC0 テクスチャ（Poly Haven）を使う
//  ・三方向から貼る（トリプラナー）：箱の大きさに関係なく、テクスチャが伸びずに同じ細かさで並ぶ
//    箱の面のように1つの向きしか向いていない所は、その1方向だけ読む（読む回数が1/3になり、軽い）
//    （世界の座標で貼るので、となりの箱とも模様がつながる）
//  ・色・凹凸（法線）・ざらざら具合（ラフネス）の3枚。光の計算は Godot 標準のリアルな陰影（PBR）
//  ・苔：上を向いた面と、地面の近く。苔の写真テクスチャを、ノイズでまだらに重ねる
//  ・雨の跡：壁を流れた縦の筋（計算で作る）
//  ・MultiMesh で並べた小物は、1つずつの色（COLOR）を掛ける
shader_type spatial;

uniform sampler2D base_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D base_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D base_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D moss_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;

uniform vec4 tint : source_color = vec4(1.0);
uniform float uv_scale = 0.33;           // 1m あたり何回くり返すか（0.33 なら 3m で1回）
uniform float moss_uv_scale = 0.5;
uniform float normal_strength = 1.0;
uniform float moss_top = 0.6;            // 上を向いた面の苔の量
uniform float moss_low = 0.35;           // 地面近くの苔の量
uniform float moss_low_height = 1.5;     // 地面（ground_y）からこの高さまで
uniform float ground_y = 0.0;
uniform float streak_amount = 0.35;      // 雨の跡の強さ
uniform vec4 dirt_color : source_color = vec4(0.25, 0.23, 0.2, 1.0);

varying vec3 world_pos;
varying vec3 world_normal;
varying vec4 inst_color;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x),
			mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
			mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

vec3 tri_weights(vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	return w / (w.x + w.y + w.z);
}

// 三方向から読んで混ぜる。ただし、面がほぼ1つの向き（箱の面）なら、その1方向だけ読む（軽くするため）
vec4 tri_sample(sampler2D t, vec3 p, vec3 w) {
	if (w.x > 0.98) { return texture(t, p.zy); }
	if (w.y > 0.98) { return texture(t, p.xz); }
	if (w.z > 0.98) { return texture(t, p.xy); }
	return texture(t, p.zy) * w.x + texture(t, p.xz) * w.y + texture(t, p.xy) * w.z;
}

// 法線マップを三方向から読んで、世界の向きの法線にする（whiteout 合成）
vec3 tri_normal(sampler2D t, vec3 p, vec3 w, vec3 n, float strength) {
	// 箱の面（ほぼ1つの向き）なら、その1方向だけ読む（軽くするため）
	if (w.x > 0.98 || w.y > 0.98 || w.z > 0.98) {
		vec3 tn;
		vec3 r;
		if (w.x > 0.98) {
			tn = texture(t, p.zy).xyz * 2.0 - 1.0;
			tn.xy *= strength;
			r = vec3(tn.xy + n.zy, abs(tn.z) * n.x).zyx;
		} else if (w.y > 0.98) {
			tn = texture(t, p.xz).xyz * 2.0 - 1.0;
			tn.xy *= strength;
			r = vec3(tn.xy + n.xz, abs(tn.z) * n.y).xzy;
		} else {
			tn = texture(t, p.xy).xyz * 2.0 - 1.0;
			tn.xy *= strength;
			r = vec3(tn.xy + n.xy, abs(tn.z) * n.z);
		}
		return normalize(r);
	}
	vec3 tx = texture(t, p.zy).xyz * 2.0 - 1.0;
	vec3 ty = texture(t, p.xz).xyz * 2.0 - 1.0;
	vec3 tz = texture(t, p.xy).xyz * 2.0 - 1.0;
	tx.xy *= strength;
	ty.xy *= strength;
	tz.xy *= strength;
	tx = vec3(tx.xy + n.zy, abs(tx.z) * n.x);
	ty = vec3(ty.xy + n.xz, abs(ty.z) * n.y);
	tz = vec3(tz.xy + n.xy, abs(tz.z) * n.z);
	return normalize(tx.zyx * w.x + ty.xzy * w.y + tz.xyz * w.z);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	inst_color = COLOR;
}

void fragment() {
	vec3 n = normalize(world_normal);
	vec3 w = tri_weights(n);
	vec3 p = world_pos * uv_scale;
	vec3 col = tri_sample(base_albedo, p, w).rgb * tint.rgb * inst_color.rgb;
	float rough = tri_sample(base_rough, p, w).r;
	vec3 wn = tri_normal(base_normal, p, w, n, normal_strength);

	// 雨の跡（壁の面だけ）
	float wall = 1.0 - abs(n.y);
	float streak = noise(vec3(world_pos.x * 1.7 + world_pos.z * 1.7, world_pos.y * 0.15, 0.0));
	col = mix(col, col * dirt_color.rgb * 2.0, smoothstep(0.55, 0.9, streak) * streak_amount * wall);

	// 苔：上を向いた面と、地面の近く。ノイズでまだらに
	float up = smoothstep(0.55, 0.9, n.y) * moss_top;
	float low = (1.0 - smoothstep(0.0, moss_low_height, world_pos.y - ground_y)) * moss_low * wall;
	float mn = noise(world_pos * 0.45 + vec3(7.0)) * 0.65 + noise(world_pos * 1.3) * 0.35;
	float moss = clamp(up + low, 0.0, 1.0) * smoothstep(0.38, 0.62, mn);
	if (moss > 0.001) {
		vec3 mp = world_pos * moss_uv_scale;
		col = mix(col, tri_sample(moss_albedo, mp, w).rgb, moss);
		rough = mix(rough, tri_sample(moss_rough, mp, w).r, moss);
		wn = normalize(mix(wn, tri_normal(moss_normal, mp, w, n, 1.0), moss));
	}

	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = 0.0;
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
}
