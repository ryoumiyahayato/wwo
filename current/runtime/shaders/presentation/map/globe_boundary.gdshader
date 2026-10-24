shader_type canvas_item;
render_mode unshaded;

uniform sampler2D line_data : filter_nearest, repeat_disable;
uniform mat3 globe_basis = mat3(1.0);
uniform vec2 globe_center = vec2(0.0);
uniform float globe_radius = 220.0;
uniform bool region_mode = false;
uniform float region_km_per_pixel = 5.5;
uniform vec2 region_bearing = vec2(1.0, 0.0);
uniform float stroke_width = 0.65;
uniform float miter_limit = 3.0;
uniform float stroke_feather = 1.25;
uniform vec4 stroke_color = vec4(0.22, 0.29, 0.30, 0.62);
uniform int rail_style = 0;
uniform vec4 river_replacement = vec4(0.0);
uniform float dash_period = 0.0;
uniform float dash_on = 0.55;
varying vec4 line_color;
varying vec2 track_position;
varying vec2 map_pixel;
#include "res://shaders/presentation/map/local_chart.gdshaderinc"

vec4 line_value(int segment, int field) {
	int texel = segment * 4 + field;
	return texelFetch(line_data, ivec2(texel % 256, texel / 256), 0);
}

vec2 screen_point(vec3 point) {
	if (region_mode) {
		vec3 p = normalize(point);
		float sine = length(p.xy);
		float angle = atan(sine, p.z);
		vec2 km = p.xy * (6371.0088 * angle / max(sine, 0.000001));
		vec2 screen = vec2(km.x * region_bearing.x + km.y * region_bearing.y,
			km.x * region_bearing.y - km.y * region_bearing.x);
		return globe_center + screen / region_km_per_pixel;
	}
	return globe_center + vec2(point.x, -point.y) * globe_radius;
}

vec3 horizon_point(vec3 outside, vec3 inside) {
	return mix(outside, inside, outside.z / (outside.z - inside.z));
}

vec2 edge_offset(vec2 before, vec2 after) {
	vec2 difference = before - after;
	vec2 bisector = length(difference) > 0.00001 ? normalize(difference) : vec2(after.y, -after.x);
	float sine = bisector.x * before.y - bisector.y * before.x;
	float extent = abs(sine) > 0.00001 && length(difference) > 0.00001 ? clamp(1.0 / sine, -miter_limit, miter_limit) : 1.0;
	return bisector * extent;
}

void vertex() {
	int segment = int(VERTEX.x);
	int slot = int(VERTEX.y);
	vec4 a_data = line_value(segment, 0);
	vec4 b_data = line_value(segment, 1);
	vec3 a = globe_basis * a_data.xyz;
	vec3 b = globe_basis * b_data.xyz;
	vec3 before = globe_basis * line_value(segment, 2).xyz;
	vec3 after = globe_basis * line_value(segment, 3).xyz;
	line_color = stroke_color;
	track_position = vec2(0.0);
	VERTEX = vec2(-10000.0);
	map_pixel = VERTEX;
	if (a.z >= 0.0 || b.z >= 0.0) {
		bool cap_a = a_data.w > 0.5 || a.z < 0.0;
		bool cap_b = b_data.w > 0.5 || b.z < 0.0;
		if (a.z < 0.0) { a = horizon_point(a, b); }
		if (b.z < 0.0) { b = horizon_point(b, a); }
		if (before.z < 0.0) { before = horizon_point(before, a); }
		if (after.z < 0.0) { after = horizon_point(after, b); }
		vec2 start = screen_point(a);
		vec2 end = screen_point(b);
		vec2 delta = end - start;
		if (length(delta) > 0.00001) {
			vec2 direction = normalize(delta);
			vec2 preceding = start - screen_point(before);
			vec2 following = screen_point(after) - end;
			vec2 normal_a = cap_a || length(preceding) < 0.00001 ? vec2(direction.y, -direction.x) : edge_offset(normalize(preceding), direction);
			vec2 normal_b = cap_b || length(following) < 0.00001 ? vec2(direction.y, -direction.x) : edge_offset(direction, normalize(following));
			bool at_start = slot < 4 || (slot >= 8 && slot < 12);
			bool feather_cap = slot >= 8;
			int band = slot % 4;
			float feather = stroke_feather * min(stroke_width, 1.0);
			float side = band < 2 ? 1.0 : -1.0;
			bool outer = band == 0 || band == 3;
			vec2 point = at_start ? start : end;
			vec2 normal = at_start ? normal_a : normal_b;
			point += normal * side * (stroke_width * 0.5 + (outer ? feather : 0.0));
			if (feather_cap) {
				point += direction * (at_start ? -1.0 : 1.0) * feather * ((at_start ? cap_a : cap_b) ? 1.0 : 0.0);
			}
			line_color.a *= outer || feather_cap ? 0.0 : 1.0;
			// One existing strip carries both rails and periodic ties. No new draws.
			track_position = vec2(dot(at_start ? start : end,direction),side*(stroke_width*0.5+(outer?feather:0.0)));
			map_pixel = point;
			point.y -= local_displacement(at_start ? a : b);
			VERTEX = point;
		}
	}
}


void fragment() {
	COLOR = line_color;
	COLOR.a *= 1.0-local_cover(map_pixel);
	if (region_mode && river_replacement.w>0.0) {
		vec3 earth = transpose(globe_basis)*local_view_at_pixel(map_pixel);
		float owner = smoothstep(river_replacement.w,river_replacement.w+0.0000074,dot(earth,river_replacement.xyz));
		COLOR.a *= 1.0-owner;
	}
	if (dash_period > 0.0) { COLOR.a *= 1.0-smoothstep(dash_period*dash_on-0.5,dash_period*dash_on+0.5,mod(track_position.x,dash_period)); }
	if (rail_style == 3) {
		COLOR.a *= 1.0-smoothstep(7.0,8.0,mod(track_position.x,13.0));
	} else if (rail_style > 0) {
		float core = 1.0-smoothstep(0.28,0.75,abs(track_position.y));
		float tie = 1.0-smoothstep(0.6,1.15,abs(mod(track_position.x+3.5,7.0)-3.5));
		vec3 dark = vec3(0.10,0.16,0.18);
		vec3 light = vec3(0.89,0.86,0.70);
		COLOR.rgb = mix(dark,light,core*(rail_style==2?1.0-tie*0.8:1.0));
	}
}
