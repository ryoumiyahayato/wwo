shader_type canvas_item;
render_mode unshaded;

uniform vec4 deep_color : source_color = vec4(0.004, 0.010, 0.018, 1.0);
uniform vec4 upper_color : source_color = vec4(0.018, 0.037, 0.052, 1.0);
uniform vec4 nebula_color : source_color = vec4(0.08, 0.18, 0.20, 1.0);
uniform vec4 warm_nebula_color : source_color = vec4(0.16, 0.12, 0.08, 1.0);
uniform float star_density : hint_range(0.0, 1.0) = 0.34;
uniform float nebula_strength : hint_range(0.0, 1.0) = 0.22;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.55;
	mat2 rotation = mat2(vec2(0.80, -0.60), vec2(0.60, 0.80));
	for (int index = 0; index < 5; index++) {
		value += value_noise(p) * amplitude;
		p = rotation * p * 2.03 + vec2(7.1, 3.7);
		amplitude *= 0.48;
	}
	return value;
}

float star_layer(vec2 uv, vec2 grid_size, float threshold, float radius) {
	vec2 grid = uv * grid_size;
	vec2 cell = floor(grid);
	vec2 local = fract(grid) - 0.5;
	float random_value = hash21(cell);
	float star = smoothstep(radius, 0.0, length(local));
	float enabled = smoothstep(threshold, 1.0, random_value);
	return star * enabled;
}

void fragment() {
	vec2 uv = UV;
	float aspect = SCREEN_PIXEL_SIZE.y / max(SCREEN_PIXEL_SIZE.x, 0.000001);
	vec2 p = (uv - 0.5) * vec2(aspect, 1.0);

	float vertical = smoothstep(0.0, 1.0, 1.0 - uv.y);
	vec3 color = mix(deep_color.rgb, upper_color.rgb, vertical * 0.72);

	float cloud_a = fbm(p * 1.45 + vec2(-0.35, 0.16));
	float cloud_b = fbm(p * 2.10 + vec2(1.80, -0.70));
	float band = smoothstep(0.48, 0.82, cloud_a) * smoothstep(0.92, 0.12, abs(p.y + p.x * 0.18));
	float warm_band = smoothstep(0.58, 0.88, cloud_b) * smoothstep(0.72, 0.04, length(p - vec2(0.24, -0.10)));
	color += nebula_color.rgb * band * nebula_strength;
	color += warm_nebula_color.rgb * warm_band * nebula_strength * 0.42;

	float stars_small = star_layer(uv, vec2(210.0, 118.0), 0.9965 - star_density * 0.004, 0.080);
	float stars_medium = star_layer(uv + vec2(0.13, 0.07), vec2(116.0, 66.0), 0.9982 - star_density * 0.002, 0.105);
	float stars_large = star_layer(uv + vec2(0.31, 0.19), vec2(62.0, 35.0), 0.9993 - star_density * 0.001, 0.130);
	color += vec3(0.66, 0.78, 0.82) * stars_small * 0.38;
	color += vec3(0.82, 0.84, 0.74) * stars_medium * 0.62;
	color += vec3(0.95, 0.88, 0.70) * stars_large * 0.90;

	float vignette = smoothstep(0.90, 0.24, length(p));
	color *= mix(0.42, 1.0, vignette);
	COLOR = vec4(color, 1.0);
}
