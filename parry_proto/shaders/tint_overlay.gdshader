// Godot 4.7.2 / Godot Shading Language
// res://shaders/tint_overlay.gdshader
// モデルの上に重ねて、状態の色（パリィ受付の水色・被弾の赤など）を足す（P-16）
//  ・material_overlay に使う。strength が 0 なら何も足さない（元の見た目のまま）
//  ・ふち（輪郭の近く）ほど強く光るので、色が付いても顔や服の形がわかる
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;

uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float strength : hint_range(0.0, 2.0) = 0.0;
uniform float flat_amount : hint_range(0.0, 1.0) = 0.35;  // 全体に足す量
uniform float rim_power = 2.0;                              // ふちの光り方の鋭さ

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	ALBEDO = tint.rgb * (flat_amount + rim) * strength;
}
