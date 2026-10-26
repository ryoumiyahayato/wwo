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
uniform bool native_overview = false;
uniform mat4 terrain_to_local;
uniform mat4 terrain_to_world;
// Linear-light reflectance, not a replacement map or a new geographic dataset.
uniform vec3 grass_color = vec3(0.085, 0.160, 0.035);
uniform vec3 soil_color = vec3(0.160, 0.090, 0.035);
uniform vec3 rock_color = vec3(0.220, 0.230, 0.215);
uniform vec3 field_color = vec3(0.190, 0.155, 0.050);
uniform float macro_contrast : hint_range(0.0, 5.0) = 2.8;
uniform float normal_relief : hint_range(1.0, 8.0) = 1.6;
uniform float hillshade_strength : hint_range(0.0, 1.0) = 0.0;
uniform vec3 relief_light_direction = vec3(-0.45, 0.75, 0.48);
uniform float detail_scale : hint_range(0.05, 1.0) = 0.32;
uniform float detail_contrast : hint_range(0.0, 4.0) = 2.2;
uniform float detail_bump_metres : hint_range(0.0, 0.08) = 0.018;

varying vec3 terrain_point;
varying vec3 terrain_normal;
varying vec3 world_point;

void vertex() {
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	terrain_point = (terrain_to_local * vec4(world_point, 1.0)).xyz;
	terrain_normal = normalize((terrain_to_local * vec4(MODEL_NORMAL_MATRIX * NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 local_uv = (terrain_point.xz + vec2(2500.0)) / 5000.0;
	vec2 native_grid = clamp(local_uv * 10.0, vec2(0.0), vec2(9.999999));
	// Explicit cell-centre lookup avoids nearest-filter tie ambiguity on seams.
	vec2 coverage_uv = (floor(native_grid) + vec2(0.5)) / 10.0;
	bool covered = native_surface && native_overview && texture(detail_coverage, coverage_uv).r > 0.5;
	vec2 edge_fraction = min(fract(native_grid), vec2(1.0) - fract(native_grid));
	float detail_edge_fade = smoothstep(0.0, 2.0, min(edge_fraction.x, edge_fraction.y) * 500.0);
	vec3 source_normal = normalize(terrain_normal);
	vec3 base = grass_color;
	vec3 masks = vec3(0.0);
	if (!native_surface) {
		vec2 region_uv = (terrain_point.xz + vec2(22500.0)) / 50000.0;
		if (has_region_color) {
			vec3 source = texture(region_color, region_uv).rgb;
			float luminance = dot(source, vec3(0.2126, 0.7152, 0.0722));
			// Original regional color still owns forests/fields/river layout.
			base = max(vec3(0.0), mix(vec3(luminance), source, 1.14));
			base *= clamp(1.0 + (luminance - 0.10) * macro_contrast, 0.72, 1.35);
		}
		if (has_region_normal) {
			source_normal = normalize(texture(region_normal, region_uv).rgb * 2.0 - 1.0);
		}
	} else {
		if (has_land_control) {
			// Original Cedar/Ridgevale contract: R soil/roads, G fields, B rock.
			masks = clamp(texture(land_control, local_uv).rgb, vec3(0.0), vec3(1.0));
		}
		float slope = 1.0 - clamp(source_normal.y, 0.0, 1.0);
		masks.b = max(masks.b, smoothstep(0.12, 0.46, slope) * 0.68);
		base = mix(grass_color, field_color, masks.g);
		base = mix(base, soil_color, masks.r);
		base = mix(base, rock_color, masks.b);
		if (has_land_color) {
			vec3 source = texture(land_color, local_uv).rgb;
			float luminance = dot(source, vec3(0.2126, 0.7152, 0.0722));
			float structure = clamp(1.0 + (luminance - 0.15) * macro_contrast, 0.68, 1.35);
			vec3 chroma = clamp(source / max(luminance, 0.035), vec3(0.65), vec3(1.35));
			// Preserve source low-frequency structure, not its all-over beige cast.
			base *= structure * mix(vec3(1.0), chroma, 0.12);
		}
	}

	// Visual relief only: source vertices, support height and collision are untouched.
	vec3 relief_normal = normalize(vec3(source_normal.x * normal_relief, max(source_normal.y, 0.05), source_normal.z * normal_relief));
	NORMAL = normalize((VIEW_MATRIX * terrain_to_world * vec4(relief_normal, 0.0)).xyz);
	vec3 light_direction = normalize(relief_light_direction);
	float relief = dot(relief_normal, light_direction) - light_direction.y;
	base *= clamp(1.0 + relief * hillshade_strength * 3.0, 0.65, 1.22);

	vec2 detail_uv = terrain_point.xz * detail_scale;
	vec3 grass = vec3(0.22);
	vec3 soil = vec3(0.22);
	vec3 stone = vec3(0.22);
	if (has_grass_detail) { grass = texture(grass_detail, detail_uv).rgb; }
	if (has_soil_detail) { soil = texture(soil_detail, detail_uv * 0.86).rgb; }
	if (has_stone_detail) { stone = texture(stone_detail, detail_uv * 0.68).rgb; }
	vec3 grain = mix(mix(grass, soil, masks.r), stone, masks.b);
	float grain_height = dot(grain, vec3(0.2126, 0.7152, 0.0722));
	float eye_distance = length(CAMERA_POSITION_WORLD - world_point);
	float close_weight = 1.0 - smoothstep(45.0, 420.0, eye_distance);
	// Native 512px detail remains mip/anisotropic filtered; unresolved bump fades.
	float texels_per_pixel = max(length(dFdx(detail_uv)), length(dFdy(detail_uv))) * 512.0;
	float resolved_detail = 1.0 - smoothstep(1.5, 12.0, texels_per_pixel);
	float fine_edge = 1.0;
	if (native_surface && !native_overview) { fine_edge = detail_edge_fade; }
	base *= mix(1.0, clamp(1.0 + (grain_height - 0.22) * detail_contrast, 0.62, 1.45), close_weight);

	// Screen-space surface-gradient bump. Reuses the three existing detail reads:
	// no new texture samples, normal-map files, mesh vertices or height sources.
	vec3 position_dx = dFdx(VERTEX);
	vec3 position_dy = dFdy(VERTEX);
	vec3 cross_x = cross(position_dy, NORMAL);
	vec3 cross_y = cross(NORMAL, position_dx);
	float determinant = dot(position_dx, cross_x);
	vec3 gradient = (dFdx(grain_height) * cross_x + dFdy(grain_height) * cross_y) * sign(determinant) / max(abs(determinant), 0.000001);
	float bump_weight = close_weight * resolved_detail * fine_edge;
	vec3 perturbation = gradient * detail_bump_metres * bump_weight;
	// Bound near-grazing derivatives; no single bright pixel from an extreme normal.
	perturbation /= max(1.0, length(perturbation) * 2.5);
	NORMAL = normalize(NORMAL - perturbation);
	ALBEDO = clamp(base, vec3(0.0), vec3(1.0));
	float surface_roughness = mix(mix(0.97, 0.92, masks.r), 0.86, masks.b);
	ROUGHNESS = clamp(surface_roughness + (0.22 - grain_height) * 0.45 * close_weight, 0.80, 1.0);
	SPECULAR = 0.10;
	// Derivatives run before per-fragment discard, including seam helper pixels.
	if (covered) { discard; }
}
