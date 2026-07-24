shader_type canvas_item;
render_mode unshaded;

// 2D 等距世界没有逐像素深度缓冲，因此用玩家所在的屏幕高度模拟焦平面。
// 清晰采样与 mipmap 模糊采样分开，确保焦内像素仍保持 nearest 的锐利边缘。
uniform sampler2D screen_sharp : hint_screen_texture, repeat_disable, filter_nearest;
uniform sampler2D screen_blurred : hint_screen_texture, repeat_disable, filter_linear_mipmap;

uniform float focus_y : hint_range(0.0, 1.0) = 0.5;
uniform float focus_half_height : hint_range(0.02, 0.4) = 0.13;
uniform float focus_feather : hint_range(0.02, 0.5) = 0.27;
uniform float max_blur_lod : hint_range(0.0, 5.0) = 2.6;
uniform float far_strength : hint_range(0.0, 1.5) = 0.78;
uniform float near_strength : hint_range(0.0, 1.5) = 1.08;
uniform float vignette_strength : hint_range(0.0, 0.25) = 0.05;

void fragment() {
	vec2 screen_uv = SCREEN_UV;
	float signed_distance = screen_uv.y - focus_y;
	float focus_distance = abs(signed_distance);
	float circle_of_confusion = smoothstep(
		focus_half_height,
		focus_half_height + focus_feather,
		focus_distance
	);
	float side_strength = mix(far_strength, near_strength, step(0.0, signed_distance));
	float blur_amount = clamp(circle_of_confusion * side_strength, 0.0, 1.0);

	vec4 sharp_color = textureLod(screen_sharp, screen_uv, 0.0);
	vec4 blurred_color = textureLod(
		screen_blurred,
		screen_uv,
		blur_amount * max_blur_lod
	);
	vec4 result = mix(sharp_color, blurred_color, blur_amount);

	// 极轻的镜头暗角只作用于远离焦区的内容，避免覆盖昼夜系统的色彩设计。
	vec2 centered = screen_uv - vec2(0.5);
	float vignette = smoothstep(0.34, 0.72, length(centered));
	result.rgb *= 1.0 - vignette * vignette_strength * blur_amount;
	COLOR = result;
}
