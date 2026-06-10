shader_type canvas_item;

// 暗角强度（0~1）：值越大角落越黑
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.55;
// 暗角内缘半径（0~1，距中心多远开始变暗）
uniform float vignette_inner : hint_range(0.0, 1.0) = 0.35;
// 暗角外缘半径（应大于 inner）
uniform float vignette_outer : hint_range(0.0, 2.0) = 1.10;
// 基色（仅在没有贴图时作为底色用，以兼容旧的 ColorRect 用法）
uniform vec4 base_color : source_color = vec4(0.16, 0.14, 0.11, 1.0);
// 整体颜色微调（让贴图更冷或更暖，默认中性）
uniform vec3 tint : source_color = vec3(1.0, 1.0, 1.0);

// 背景模式：0=纯色（用 base_color，适用于 ColorRect）；1=贴图（用 TEXTURE，适用于 TextureRect）
uniform int bg_mode : hint_range(0, 1) = 0;

// 边缘不规则程度：0=完美圆形；越大边缘越破碎有机
uniform float edge_irregularity : hint_range(0.0, 0.3) = 0.10;

// ── 简化的 2D value noise（三层叠加做有机边缘） ──
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm_edge(vec2 p) {
	float sum = 0.0;
	sum += vnoise(p * 4.0)  * 0.50;
	sum += vnoise(p * 8.0)  * 0.30;
	sum += vnoise(p * 16.0) * 0.15;
	sum += vnoise(p * 32.0) * 0.05;
	return sum;
}

void fragment() {
	vec3 base_rgb;
	if (bg_mode == 1) {
		// 贴图模式：采样 TEXTURE 并叠加 tint
		vec4 sampled = texture(TEXTURE, UV);
		base_rgb = sampled.rgb * tint;
	} else {
		// 纯色模式：直接用 base_color
		base_rgb = base_color.rgb;
	}

	// 暗角（带不规则有机边缘）
	vec2 uv = UV - vec2(0.5);
	float dist = length(uv) * 1.414;

	// 用 fbm noise 扰动距离，制造纸杯/撕边效果
	float n = fbm_edge(uv + vec2(1.73, 2.91));
	// 把 noise 从 [0,1] 映射到 [-1,1] 再缩放
	dist += (n - 0.5) * 2.0 * edge_irregularity;

	float v = smoothstep(vignette_inner, vignette_outer, dist);
	// 输出 alpha = vignette 强度：中心全透明（露出地图），边缘渐暗
	vec3 dimmed = base_rgb * (1.0 - v * vignette_strength);
	float alpha = v * vignette_strength * base_color.a;
	COLOR = vec4(dimmed, alpha);
}
