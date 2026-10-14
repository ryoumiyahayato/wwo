shader_type canvas_item;
render_mode unshaded;
uniform sampler2D relief_world : filter_linear, repeat_enable;
uniform sampler2D relief_region : filter_linear, repeat_enable;
uniform float relief_weight = 0.0;
uniform float relief_detail_weight = 0.0;
uniform mat3 globe_basis = mat3(1.0);
uniform vec2 globe_center = vec2(0.0);
uniform float region_km_per_pixel = 5.5;
uniform vec2 region_bearing = vec2(1.0, 0.0);
varying vec2 map_pixel;
void vertex() { map_pixel = VERTEX; }
void fragment() {
	vec3 base = vec3(0.10, 0.14, 0.16);
	if (relief_weight > 0.0) {
		vec2 xy = map_pixel - globe_center;
		vec2 km = vec2(xy.x * region_bearing.x + xy.y * region_bearing.y,
			xy.x * region_bearing.y - xy.y * region_bearing.x) * region_km_per_pixel;
		float distance = length(km);
		float angle = distance / 6371.0088;
		vec3 earth = transpose(globe_basis) * vec3(km * sin(angle) / max(distance, 0.000001), cos(angle));
		float longitude = length(earth.xz) > 0.000001 ? atan(earth.x, earth.z) : 0.0;
		vec2 uv = vec2(longitude / 6.28318530718 + 0.5, 0.5 - asin(clamp(earth.y, -1.0, 1.0)) / 3.14159265359);
		vec2 coarse = texture(relief_world, vec2(uv.x, clamp(uv.y, 0.5 / 512.0, 1.0 - 0.5 / 512.0))).rg;
		vec2 detail = texture(relief_region, vec2(uv.x, clamp(uv.y, 0.5 / 2048.0, 1.0 - 0.5 / 2048.0))).rg;
		vec2 relief = mix(coarse, detail, relief_detail_weight);
		// Only a broad positive-height backdrop where political content has no
		// fill. It supplies neither a shoreline fact nor a polity/controller.
		base = mix(base, vec3(0.27, 0.32, 0.29) * (1.0 + relief_weight * (relief.r * 2.0 - 1.0)), smoothstep(0.005, 0.04, relief.g) * 0.75);
	}
	COLOR = vec4(base, 1.0);
}
