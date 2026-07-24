shader_type canvas_item;
render_mode unshaded;

// The terrain batch cannot insert a moving sprite between its lakebed and
// surface draw calls. Reapplying the same water colour over aquatic sprites
// reproduces that missing foreground water layer without adding one CanvasItem
// for every water cell.
uniform vec4 water_colour : source_color = vec4(0.07, 0.32, 0.52, 1.0);
uniform float fin_coverage : hint_range(0.0, 0.5) = 0.10;
uniform float body_coverage : hint_range(0.0, 0.85) = 0.58;
uniform float waterline : hint_range(0.1, 0.8) = 0.30;
uniform float visibility : hint_range(0.5, 1.0) = 0.94;

varying vec4 sprite_tint;

void vertex() {
	sprite_tint = COLOR;
}

void fragment() {
	vec4 sprite = texture(TEXTURE, UV) * sprite_tint;
	float submerged_mask = smoothstep(
		waterline - 0.025,
		waterline + 0.025,
		UV.y
	);
	float foreground_water = mix(fin_coverage, body_coverage, submerged_mask);
	vec3 submerged = mix(sprite.rgb, water_colour.rgb, foreground_water);
	float submerged_visibility = mix(1.0, visibility, submerged_mask);
	COLOR = vec4(submerged, sprite.a * submerged_visibility);
}
