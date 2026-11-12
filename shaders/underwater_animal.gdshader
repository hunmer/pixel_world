shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

// 每一水柱深度的前景水层。该材质由 spawn 按实际水深配置，鱼仍由真实 3D 深度遮挡。
uniform vec4 water_colour : source_color = vec4(0.25, 0.58, 0.62, 0.42);
uniform float fin_coverage : hint_range(0.0, 1.0) = 0.88;
uniform float body_coverage : hint_range(0.0, 1.0) = 0.62;
uniform float waterline : hint_range(0.0, 1.0) = 0.62;
uniform float submerged_visibility : hint_range(0.0, 1.0) = 0.88;
uniform sampler2D albedo_texture : source_color, filter_nearest, repeat_disable;

void vertex() {
	// 自定义 spatial shader 不继承 BaseMaterial3D 的 billboard 分支。
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0],
		INV_VIEW_MATRIX[1],
		INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]
	);
}

void fragment() {
	vec4 sprite_tint = COLOR;
	vec4 sprite = texture(albedo_texture, UV) * sprite_tint;
	float submerged_part = 1.0 - smoothstep(waterline - 0.055, waterline + 0.055, UV.y);
	float above_part = 1.0 - submerged_part;
	vec3 water_tint = mix(water_colour.rgb, water_colour.rgb * 1.08, above_part);
	float tint_amount = mix(body_coverage, fin_coverage, above_part);
	vec3 submerged = mix(sprite.rgb, water_tint * max(sprite.rgb, vec3(0.34)), tint_amount);
	float visibility = mix(submerged_visibility, 1.0, above_part);
	ALBEDO = submerged;
	ALPHA = sprite.a * visibility;
}
