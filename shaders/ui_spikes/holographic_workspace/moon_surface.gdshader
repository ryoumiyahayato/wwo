shader_type spatial;
render_mode unshaded, cull_back, depth_draw_opaque;

uniform vec3 moon_base_color : source_color = vec3(0.54, 0.56, 0.54);
uniform vec3 moon_light_color : source_color = vec3(0.78, 0.78, 0.70);
uniform vec3 moon_shadow_color : source_color = vec3(0.10, 0.13, 0.15);
uniform float surface_contrast : hint_range(0.0, 1.0) = 0.42;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 local = fract(p);
	local = local * local * (3.0 - 2.0 * local);
	float a = hash21(cell);
	float b = hash21(cell + vec2(1.0, 0.0));
	float c = hash21(cell + vec2(0.0, 1.0));
	float d = hash21(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, local.x), mix(c, d, local.x), local.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.58;
	for (int index = 0; index < 4; index++) {
		value += value_noise(p) * amplitude;
		p = p * 2.07 + vec2(5.1, 8.7);
		amplitude *= 0.46;
	}
	return value;
}

void fragment() {
	vec3 normal_view = normalize(NORMAL);
	vec3 light_direction = normalize(vec3(-0.72, 0.38, 0.58));
	float direct_light = smoothstep(-0.18, 0.82, dot(normal_view, light_direction));
	float limb = pow(clamp(1.0 - dot(normal_view, normalize(VIEW)), 0.0, 1.0), 2.4);

	float broad_surface = fbm(UV * vec2(8.0, 4.0));
	float fine_surface = fbm(UV * vec2(23.0, 11.0) + vec2(4.7, 1.9));
	float crater_mask = smoothstep(0.62, 0.84, fine_surface);
	float surface_value = mix(0.78, 1.08, broad_surface);
	surface_value *= mix(1.0, 0.64, crater_mask * surface_contrast);

	vec3 lit_color = mix(moon_base_color, moon_light_color, direct_light);
	vec3 shaded_color = mix(moon_shadow_color, lit_color, direct_light);
	shaded_color *= surface_value;
	shaded_color += moon_light_color * limb * 0.045;

	ALBEDO = shaded_color;
	EMISSION = shaded_color * 0.14;
	ROUGHNESS = 1.0;
	ALPHA = 1.0;
}
