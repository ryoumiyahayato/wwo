shader_type spatial;
render_mode diffuse_burley, specular_disabled, cull_back;

uniform sampler2D region_color : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D region_normal : filter_linear_mipmap, repeat_disable;
uniform sampler2D land_color : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D land_control : filter_linear_mipmap, repeat_disable;
uniform sampler2D grass_detail : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_detail : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stone_detail : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_coverage : filter_nearest, repeat_disable;
uniform bool has_region_color = false;
uniform bool has_region_normal = false;
uniform bool has_land_color = false;
uniform bool has_land_control = false;
uniform bool has_grass_detail = false;
uniform bool has_soil_detail = false;
uniform bool has_stone_detail = false;
uniform bool native_surface = false;
uniform bool coverage_enabled = false;
uniform bool far_mesh = false;
uniform float coverage_cells = 10.0;
uniform bool use_vertex_damage = false;
uniform mat4 terrain_to_local;
uniform mat4 terrain_to_world;
uniform vec3 grass_color = vec3(0.085, 0.160, 0.035);
uniform vec3 soil_color = vec3(0.160, 0.090, 0.035);
uniform vec3 rock_color = vec3(0.220, 0.230, 0.215);
uniform float detail_scale = 0.32;
uniform float detail_contrast = 1.8;
uniform float detail_bump_metres = 0.014;

varying vec3 terrain_point;
varying vec3 terrain_normal;
varying vec3 world_point;

void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	terrain_point = (terrain_to_local * vec4(world_point, 1.0)).xyz;
	terrain_normal = normalize((terrain_to_local * vec4(MODEL_NORMAL_MATRIX * NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 region_uv = (terrain_point.xz + vec2(22500.0)) / 50000.0;
	vec2 native_uv = (terrain_point.xz + vec2(2500.0)) / 5000.0;
	vec2 coverage_grid = clamp(native_uv * coverage_cells, vec2(0.0), vec2(coverage_cells - 0.0001));
	vec2 coverage_uv = (floor(coverage_grid) + vec2(0.5)) / coverage_cells;
	bool covered = native_surface && (coverage_enabled || far_mesh) && texture(detail_coverage, coverage_uv).r > 0.5;
	// Screen footprint also works for a high, narrow orthographic camera.
	float metres_per_pixel = max(length(dFdx(terrain_point.xz)), length(dFdy(terrain_point.xz)));
	float close_weight = 1.0 - smoothstep(0.08, 1.4, metres_per_pixel);
	float native_distance = 2500.0 - max(abs(terrain_point.x), abs(terrain_point.z));
	float native_edge = smoothstep(0.0, 128.0, native_distance);
	// 100m authored fields remain readable at the 5km projection (~11m/px).
	// Grain/bump resolution below keeps its separate, much tighter footprint.
	float local_weight = (1.0 - smoothstep(8.0, 64.0, metres_per_pixel)) * native_edge;

	// One macro base and lighting convention for every LOD and both terrain owners.
	// The original map already contains weak baked slope structure: do not shade
	// it again with an exaggerated normal or invent an unrelated beige/green map.
	vec3 base = grass_color;
	if (has_region_color) { base = texture(region_color, region_uv).rgb; }
	vec3 source_normal = normalize(terrain_normal);
	if (has_region_normal) {
		// Original Y-up object RGB, NOT a tangent/blue-up normal-map import.
		source_normal = normalize(texture(region_normal, region_uv).rgb * 2.0 - 1.0);
	}
	vec3 masks = vec3(0.0);
	if (native_surface) {
		if (has_land_control) { masks = clamp(texture(land_control, native_uv).rgb, vec3(0.0), vec3(1.0)); }
		base = mix(base, base * vec3(1.10, 1.04, 0.82), masks.g * local_weight * 0.55);
		base = mix(base, soil_color, masks.r * local_weight * 0.75);
		base = mix(base, rock_color, masks.b * local_weight * 0.70);
		if (has_land_color) {
			float source_luma = dot(texture(land_color, native_uv).rgb, vec3(0.2126, 0.7152, 0.0722));
			float known_local = max(max(masks.r, masks.g), masks.b);
			base *= mix(1.0, clamp(1.0 + (source_luma - 0.15) * 1.4, 0.85, 1.15), known_local * local_weight);
		}
		// True local geometry normals enter continuously near the eye, never at
		// a 5km rectangular LOD boundary; shared boundary nodes use the same rule.
		source_normal = normalize(mix(source_normal, normalize(terrain_normal), close_weight * native_edge));
	}
	NORMAL = normalize((VIEW_MATRIX * terrain_to_world * vec4(source_normal, 0.0)).xyz);

	vec2 detail_uv = terrain_point.xz * detail_scale;
	vec3 grass = vec3(0.22);
	vec3 soil = vec3(0.22);
	vec3 stone = vec3(0.22);
	if (has_grass_detail) { grass = texture(grass_detail, detail_uv).rgb; }
	if (has_soil_detail) { soil = texture(soil_detail, detail_uv * 0.86).rgb; }
	if (has_stone_detail) { stone = texture(stone_detail, detail_uv * 0.68).rgb; }
	vec3 grain = mix(mix(grass, soil, masks.r * local_weight), stone, masks.b * local_weight);
	float grain_height = dot(grain, vec3(0.2126, 0.7152, 0.0722));
	float footprint = max(length(dFdx(detail_uv)), length(dFdy(detail_uv))) * 512.0;
	float resolved = 1.0 - smoothstep(1.5, 12.0, footprint);
	base *= mix(1.0, clamp(1.0 + (grain_height - 0.22) * detail_contrast, 0.72, 1.32), close_weight);
	vec3 position_dx = dFdx(VERTEX);
	vec3 position_dy = dFdy(VERTEX);
	vec3 cross_x = cross(position_dy, NORMAL);
	vec3 cross_y = cross(NORMAL, position_dx);
	float determinant = dot(position_dx, cross_x);
	vec3 gradient = (dFdx(grain_height) * cross_x + dFdy(grain_height) * cross_y) * sign(determinant) / max(abs(determinant), 0.000001);
	vec3 perturbation = gradient * detail_bump_metres * close_weight * resolved;
	perturbation /= max(1.0, length(perturbation) * 2.5);
	NORMAL = normalize(NORMAL - perturbation);
	if (use_vertex_damage) {
		// The original editable owner supplies actual crater COLOR, not fake edits.
		float damage = clamp((COLOR.r - COLOR.g) * 4.8, 0.0, 1.0);
		base = mix(base, vec3(0.047, 0.026, 0.012), damage);
	}
	ALBEDO = clamp(base, vec3(0.0), vec3(1.0));
	ROUGHNESS = clamp(mix(0.96, 0.87, masks.b * local_weight) + (0.22 - grain_height) * 0.3 * close_weight, 0.82, 1.0);
	SPECULAR = 0.10;
	// Our observer uses actual stitched geometry, not a coverage-mask seam trick.
	// This optional discard is solely for the original training owner's horizon.
	if (covered) { discard; }
}
