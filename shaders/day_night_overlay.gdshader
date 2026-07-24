shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

// Screen-fixed atmospheric grading. The overlay never approaches black: its
// indigo ambient color preserves terrain detail, while the upper-right pool is
// slightly brighter and cooler to suggest diffuse moonlight.
uniform float night_amount : hint_range(0.0, 1.0) = 0.0;
uniform float night_opacity : hint_range(0.0, 1.0) = 0.63;
uniform float cycle_time = 0.0;

void fragment() {
	vec2 centered_uv = UV - vec2(0.5);
	float vignette = smoothstep(0.28, 0.78, length(centered_uv));

	vec2 moon_delta = (UV - vec2(0.80, 0.13)) * vec2(0.82, 1.0);
	float moon_pool = 1.0 - smoothstep(0.08, 0.72, length(moon_delta));

	float cloud_band = 0.5 + 0.5 * sin(
		UV.x * 5.1 + UV.y * 2.4 + cycle_time * 0.025
	);
	float density = clamp(
		night_opacity
		+ vignette * 0.075
		+ cloud_band * 0.014
		- moon_pool * 0.125,
		0.0,
		0.78
	);
	float alpha = night_amount * density;

	vec3 deep_indigo = vec3(0.018, 0.040, 0.105);
	vec3 moon_blue = vec3(0.105, 0.175, 0.310);
	vec3 overlay_color = mix(deep_indigo, moon_blue, moon_pool * 0.62);
	COLOR = vec4(overlay_color * alpha, alpha);
}
