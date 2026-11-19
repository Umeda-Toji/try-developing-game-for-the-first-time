// Godot 4.7.2
// res://shaders/flower.gdshader
// 敵の頭の花（F-01）：素材の花の明るさ（陰影）を残したまま、色を tint に塗り替える
//  ・tint：つぼみ＝緑、パリィできる＝白、パリィできない＝赤
//  ・glow：合図のときに少し光らせる（遠くからでも見えるように）
shader_type spatial;
render_mode cull_disabled;   // 花びらは薄い板なので、裏からも見えるように

uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0);
uniform float glow = 0.0;

void fragment() {
	vec3 c = texture(tex, UV).rgb;
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	// 明るさを 0.55〜1.15 にそろえてから色を掛ける（元の色が濃い花でも、白くできるように）
	float shade = mix(0.55, 1.15, clamp(lum * 1.3, 0.0, 1.0));
	ALBEDO = tint.rgb * shade;
	ROUGHNESS = 0.7;
	EMISSION = tint.rgb * glow;
}
