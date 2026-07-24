shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;

// The shader only handles atmosphere. Rain and snow are world-space
// GPUParticles2D, so precipitation has no procedural cell boundaries and keeps
// a physically stable velocity relative to the terrain while the camera moves.
uniform float rain_amount : hint_range(0.0, 1.0) = 0.0;
uniform float snow_amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float vignette = smoothstep(0.24, 0.82, length(UV - vec2(0.5)));
	// 平滑三角波替代全屏逐像素 sin；周期与原氛围流动接近，但在
	// Compatibility 渲染器上的成本更稳定。
	float cloud_phase = fract(
		(UV.x * 5.2 + UV.y * 2.7 + TIME * 0.035) * 0.15915494
	);
	float cloud_triangle = 1.0 - abs(cloud_phase * 2.0 - 1.0);
	float slow_cloud = cloud_triangle * cloud_triangle * (3.0 - 2.0 * cloud_triangle);
	float rain_atmosphere = rain_amount * (
		0.105 + vignette * 0.055 + slow_cloud * 0.018
	);
	float snow_atmosphere = snow_amount * (
		0.035 + vignette * 0.018
	);

	vec3 premultiplied_rgb = vec3(0.075, 0.13, 0.19) * rain_atmosphere;
	float alpha = rain_atmosphere;
	premultiplied_rgb = vec3(0.72, 0.82, 0.93) * snow_atmosphere
		+ premultiplied_rgb * (1.0 - snow_atmosphere);
	alpha = snow_atmosphere + alpha * (1.0 - snow_atmosphere);

	COLOR = vec4(premultiplied_rgb, alpha);
}
