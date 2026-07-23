shader_type spatial;
render_mode blend_mix, depth_draw_alpha_prepass, cull_back, unshaded;
uniform vec4 surface_tint : source_color = vec4(0.45, 0.72, 0.68, 0.18);
uniform vec4 rim_tint : source_color = vec4(0.92, 0.82, 0.55, 0.46);
void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.8);
	ALBEDO = mix(surface_tint.rgb, rim_tint.rgb, rim * 0.45);
	ALPHA = surface_tint.a + rim * rim_tint.a;
}
