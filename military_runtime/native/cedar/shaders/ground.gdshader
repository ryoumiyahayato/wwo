shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D land_color : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D land_control : filter_linear_mipmap, repeat_disable;
uniform sampler2D grass_detail : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_detail : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_detail : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_coverage : filter_nearest, repeat_disable;
uniform bool far_mesh = false;
varying vec3 world_point;
void vertex() { world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 map_uv = (world_point.xz + vec2(2500.0)) / 5000.0;
	if (far_mesh && texture(detail_coverage, map_uv).r > 0.5) { discard; }
	vec3 masks = texture(land_control, map_uv).rgb;
	vec3 base = texture(land_color, map_uv).rgb;
	vec2 uv = world_point.xz * 0.32;
	vec3 grain = mix(texture(grass_detail, uv).rgb, texture(soil_detail, uv * 0.86).rgb, masks.r);
	grain = mix(grain, texture(stone_detail, uv * 0.68).rgb, masks.b);
	float furrow = sin((world_point.x + world_point.z * 0.08) * 7.0) * 0.020 * masks.g * (1.0 - masks.r);
	float crater = clamp((COLOR.r - COLOR.g) * 4.8, 0.0, 1.0);
	ALBEDO = mix(base * (0.75 + grain * 0.57) + furrow, vec3(0.24, 0.175, 0.115), crater);
	ROUGHNESS = 0.94;
	SPECULAR = 0.20;
}
