shader_type canvas_item;

// CUSTOM0.xy = 默认顶面中心，CUSTOM0.z = 是否参与投影旋转。
// CUSTOM0.w = 侧壁底边保持竖直向下的像素高度；draw_mesh 的 UV 已归一化。
// 普通贴图/线条的 CUSTOM0 为零，不进入旋转分支。
uniform float view_angle = 0.0;

void vertex() {
	if (CUSTOM0.z > 0.5) {
		vec2 center = CUSTOM0.xy;
		vec2 relative = VERTEX - center;
		float vertical = CUSTOM0.w;
		relative.y -= vertical;
		float c = cos(view_angle);
		float s = sin(view_angle);
		vec2 rotated = vec2(
			relative.x * c - relative.y * s,
			relative.x * s + relative.y * c
		);
		VERTEX = center + rotated + vec2(0.0, vertical);
	}
}
