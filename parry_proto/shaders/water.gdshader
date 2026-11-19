// Godot 4.7.2 / Godot Shading Language
// res://shaders/water.gdshader
// 水面（W-12）。リアルな水の見た目
//  ・映り込み：まわりの景色と空が映る（反射の光は Godot が計算する。水の上に置いた ReflectionProbe が景色を写す）
//  ・透けて見える：水の底が、さざ波でゆがんで見える（画面の絵を少しずらして読む＝屈折）
//  ・深さの色：深い所ほど、暗い緑がかった色になる（水面と底の距離から計算）
//  ・さざ波：ノイズで作った細かい波が、時間とともに流れる（頂点も少しだけ上下させる）
//  ・見る角度：真上から見ると透け、斜めから見るほど映り込みが強くなる（フレネル。Godot の反射の計算に含まれる）
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, specular_schlick_ggx;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;
uniform vec3 shallow_color : source_color = vec3(0.32, 0.42, 0.38);
uniform vec3 deep_color : source_color = vec3(0.05, 0.11, 0.1);
uniform float depth_fade = 1.8;           // この深さ（m）で、ほぼ深い色になる
uniform float clarity = 0.85;             // 浅い所の透け具合（1 で完全に透ける）
uniform float wave_scale = 0.9;           // 波の細かさ
uniform float wave_speed = 0.25;
uniform float wave_strength = 0.18;       // 波の凹凸の強さ（光の揺れ方。小さいほど静かな水面で、映り込みがはっきりする）
uniform float refraction = 0.03;          // 屈折で底がずれる量
uniform float vertex_wave = 0.03;         // 水面の上下（m）

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

// 2方向に流れるノイズを重ねた波の高さ
float wave_height(vec2 p, float t) {
	float h = noise(p * wave_scale + vec2(t * wave_speed, t * wave_speed * 0.6)) * 0.6;
	h += noise(p * wave_scale * 2.3 - vec2(t * wave_speed * 0.8, -t * wave_speed * 1.1)) * 0.3;
	h += noise(p * wave_scale * 5.1 + vec2(-t * wave_speed * 1.6, t * wave_speed)) * 0.1;
	return h;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += (wave_height(world_pos.xz, TIME) - 0.5) * vertex_wave * 2.0;
}

void fragment() {
	// 波の傾き → 法線
	float e = 0.05;
	float h = wave_height(world_pos.xz, TIME);
	float hx = wave_height(world_pos.xz + vec2(e, 0.0), TIME);
	float hz = wave_height(world_pos.xz + vec2(0.0, e), TIME);
	vec3 wn = normalize(vec3((h - hx) / e * wave_strength, 1.0, (h - hz) / e * wave_strength));
	NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);

	// 屈折：底を少しずらして読む
	vec2 off = wn.xz * refraction;
	vec2 suv = clamp(SCREEN_UV + off, vec2(0.001), vec2(0.999));
	// 水面と底の距離（深さ）
	float scene_depth = texture(depth_tex, suv).r;
	vec4 sv = INV_PROJECTION_MATRIX * vec4(suv * 2.0 - 1.0, scene_depth, 1.0);
	sv.xyz /= sv.w;
	float thickness = clamp(-sv.z - (-VERTEX.z), 0.0, 100.0);
	// 屈折した先が水より手前（水面の上の物）なら、ずらさない
	if (-sv.z < -VERTEX.z) {
		suv = SCREEN_UV;
		thickness = 0.0;
	}
	vec3 below = texture(screen_tex, suv).rgb;
	float deep = clamp(thickness / depth_fade, 0.0, 1.0);
	vec3 water = mix(shallow_color, deep_color, deep);
	vec3 col = mix(below, water, clamp(1.0 - clarity + deep * clarity, 0.0, 1.0));

	// 透けて見える色は「光らせる」形で出し、表面の映り込み（反射）は Godot に計算させる
	ALBEDO = vec3(0.0);
	EMISSION = col;
	ROUGHNESS = 0.03;
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
