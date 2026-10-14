shader_type spatial;
// The existing front-hemisphere mesh uses the opposite winding from Godot's
// clockwise front faces. Keep its geometry; show the physical backdrop on it.
render_mode blend_mix, depth_prepass_alpha, cull_disabled, unshaded;

uniform vec4 surface_tint : source_color = vec4(0.45, 0.72, 0.68, 0.18);
uniform vec4 rim_tint : source_color = vec4(0.92, 0.82, 0.55, 0.46);
uniform sampler2D relief_world : filter_linear, repeat_enable;
uniform mat3 globe_basis = mat3(1.0);
uniform float relief_weight = 0.0;
varying vec3 globe_point;
void vertex() { globe_point = VERTEX; }

void fragment() {
	float rim = pow(1.0 - clamp(dot(normalize(globe_point), VIEW), 0.0, 1.0), 2.8);
	ALBEDO = mix(surface_tint.rgb, rim_tint.rgb, rim * 0.45);
	ALPHA = surface_tint.a + rim * rim_tint.a;
	if (relief_weight > 0.0) {
		// Model position avoids the renderer's back-face normal flip on this
		// existing hemisphere, preserving north/south even with culling disabled.
		vec3 earth = transpose(globe_basis) * normalize(globe_point);
		float longitude = length(earth.xz) > 0.000001 ? atan(earth.x, earth.z) : 0.0;
		vec2 uv = vec2(longitude / 6.28318530718 + 0.5, 0.5 - asin(clamp(earth.y, -1.0, 1.0)) / 3.14159265359);
		vec2 relief = texture(relief_world, vec2(uv.x, clamp(uv.y, 0.5 / 512.0, 1.0 - 0.5 / 512.0))).rg;
		float broad_land = smoothstep(0.005, 0.04, relief.g);
		ALBEDO = mix(ALBEDO, vec3(0.27, 0.32, 0.29) * (1.0 + relief_weight * (relief.r * 2.0 - 1.0)), broad_land);
		ALPHA = mix(ALPHA, 0.85, broad_land);
	}
}
