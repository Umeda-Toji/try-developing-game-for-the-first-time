// Godot 4.7.2 / Godot Shading Language
// res://shaders/foliage.gdshader
// 草・ツタの葉（W-11）。葉を描いた画像を板に貼り、透明な所は描かない（アルファの切り抜き）
//  ・両面を描く。光が葉を透けて、裏から見ても明るく見える（BACKLIGHT）
//  ・風でゆれる：板の上ほど大きく、場所ごとに少しずつずらして動かす（見た目だけ。判定には関係しない）
//  ・MultiMesh の1つずつの色（COLOR）で、緑の濃さを変える
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D leaf_tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float alpha_cut = 0.5;
uniform vec3 translucency : source_color = vec3(0.32, 0.4, 0.16);
uniform float wind_strength = 0.08;      // ゆれの大きさ（m）
uniform float wind_speed = 1.3;
uniform float roughness_value = 0.8;

varying vec4 inst_color;

void vertex() {
	inst_color = COLOR;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float sway = (1.0 - UV.y);  // 板の上（UV.y = 0）ほど大きくゆれる
	float phase = world.x * 0.35 + world.z * 0.27;
	VERTEX.x += sin(TIME * wind_speed + phase) * wind_strength * sway;
	VERTEX.z += cos(TIME * wind_speed * 0.8 + phase * 1.3) * wind_strength * 0.6 * sway;
}

void fragment() {
	vec4 t = texture(leaf_tex, UV);
	if (t.a < alpha_cut) {
		discard;
	}
	ALBEDO = t.rgb * inst_color.rgb;
	ROUGHNESS = roughness_value;
	BACKLIGHT = translucency * inst_color.rgb;
	// 葉の根もとは少し暗く（草むらの奥は光が届きにくい）
	ALBEDO *= mix(0.55, 1.0, 1.0 - UV.y * 0.6);
}
