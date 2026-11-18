// Godot 4.7.2 / Godot Shading Language
// res://shaders/toon.gdshader
// 2〜3段階の陰影だけのシンプルなトゥーン。テクスチャ無しで内蔵GPUでも軽い。
shader_type spatial;

uniform vec4 albedo : source_color = vec4(0.8, 0.8, 0.8, 1.0);
uniform float bands : hint_range(1.0, 6.0) = 3.0;
uniform float shadow_floor : hint_range(0.0, 1.0) = 0.25;
uniform vec4 emission_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float emission_energy = 0.0;

void fragment() {
	ALBEDO = albedo.rgb;
	EMISSION = emission_color.rgb * emission_energy;
}

void light() {
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0) * ATTENUATION;
	float stepped = max(floor(ndl * bands + 0.5) / bands, shadow_floor);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * stepped;
}
