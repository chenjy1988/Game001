shader_type canvas_item;

// 暗角强度（0~1）：值越大角落越黑
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.55;
// 暗角内缘半径（0~1，距中心多远开始变暗）
uniform float vignette_inner : hint_range(0.0, 1.0) = 0.35;
// 暗角外缘半径（应大于 inner）
uniform float vignette_outer : hint_range(0.0, 2.0) = 1.10;
// 基色（背景色）
uniform vec4 base_color : source_color = vec4(0.118, 0.106, 0.137, 1.0);

void fragment() {
	// UV 中心化（0~1 -> -0.5~0.5），再用 √(x²+y²) 求距中心距离
	vec2 uv = UV - vec2(0.5);
	float dist = length(uv) * 1.414;  // 1.414 ≈ √2，让对角线方向归一化到 ~1
	float v = smoothstep(vignette_inner, vignette_outer, dist);
	vec3 dimmed = base_color.rgb * (1.0 - v * vignette_strength);
	COLOR = vec4(dimmed, 1.0);
}
