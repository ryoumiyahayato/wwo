shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
uniform vec4 tint : source_color = vec4(0.7,0.72,0.73,0.8);
uniform float opacity = 1.0;
uniform float age = 0.0;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz), INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz), INV_VIEW_MATRIX[2] * length(MODEL_MATRIX[2].xyz), MODEL_MATRIX[3]);
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float edge = 1.0 - smoothstep(0.32, 1.0, length(p));
	float waves = sin(p.x * 10.0 + sin(p.y * 7.0) + age * 0.3) * sin(p.y * 13.0 - p.x * 4.0);
	float small = sin(p.x * 29.0 + p.y * 13.0) * sin(p.y * 27.0 - p.x * 17.0);
	float body = clamp(0.72 + 0.18 * waves + 0.06 * small, 0.34, 1.0);
	ALBEDO = tint.rgb * (0.72 + 0.26 * (1.0 - UV.y) + waves * 0.07);
	ALPHA = edge * body * tint.a * opacity;
}
