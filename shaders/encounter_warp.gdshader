// encounter_warp.gdshader — 遭遇转场的径向扭曲、双闪与暗化覆盖层
// 只采样屏幕纹理，不接触世界坐标、单位格位或随机状态。
shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform float warp_amount : hint_range(0.0, 1.0) = 0.0;
uniform float dim_amount : hint_range(0.0, 1.0) = 0.0;
uniform float cover_alpha : hint_range(0.0, 1.0) = 0.0;
uniform float flash_phase : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 centered = SCREEN_UV - vec2(0.5);
	float radius = length(centered);
	vec2 direction = centered / max(radius, 0.0001);
	float radial_falloff = 1.0 - smoothstep(0.08, 0.72, radius);
	float ripple = sin(radius * 30.0 - flash_phase * 6.2831853);
	vec2 warped_uv = clamp(
		SCREEN_UV + direction * ripple * radial_falloff * warp_amount * 0.022,
		vec2(0.001),
		vec2(0.999)
	);
	vec3 scene_color = textureLod(screen_texture, warped_uv, 0.0).rgb;

	// 正、负半周各产生一次窄闪光；不使用 TIME，保证同一帧状态可复现。
	float pulse_in = pow(max(sin(flash_phase * 6.2831853), 0.0), 12.0);
	float pulse_out = pow(max(-sin(flash_phase * 6.2831853), 0.0), 12.0);
	float flash = (pulse_in + pulse_out) * warp_amount * 0.48;

	vec3 color = scene_color * (1.0 - dim_amount * 0.72);
	color = mix(color, vec3(0.012, 0.020, 0.055), cover_alpha);
	color += vec3(0.66, 0.80, 1.0) * flash * (1.0 - cover_alpha);
	COLOR = vec4(color, 1.0);
}
