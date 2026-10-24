shader_type canvas_item;
render_mode unshaded;

uniform vec4 water_color = vec4(0.25,0.36,0.37,1.0);
varying vec2 map_pixel;
uniform sampler2D face_data : filter_nearest, repeat_disable;
uniform mat3 globe_basis = mat3(1.0);
uniform vec2 globe_center = vec2(0.0);
uniform float globe_radius = 220.0;
uniform bool region_mode = false;
uniform float region_km_per_pixel = 5.5;
uniform vec2 region_bearing = vec2(1.0, 0.0);
uniform bool ocean_surface = false;
#include "res://shaders/presentation/map/local_chart.gdshaderinc"
#include "res://shaders/presentation/map/ocean_globe.gdshaderinc"
vec4 face_value(int face, int field) {
	int texel = face * 6 + field;
	return texelFetch(face_data, ivec2(texel % 256, texel / 256), 0);
}

float cross_2d(vec2 a, vec2 b) {
	return a.x * b.y - a.y * b.x;
}

vec2 screen_point(vec3 point) {
	if (!region_mode) { return globe_center + vec2(point.x, -point.y) * globe_radius; }
	vec3 p = normalize(point);
	float sine = length(p.xy);
	float angle = atan(sine, p.z);
	vec2 km = p.xy * (6371.0088 * angle / max(sine, 0.000001));
	vec2 screen = vec2(km.x * region_bearing.x + km.y * region_bearing.y,
		km.x * region_bearing.y - km.y * region_bearing.x);
	return globe_center + screen / region_km_per_pixel;
}

void vertex() {
	// The same source faces and linear horizon intersections as GlobeProjection.
	// A clipped triangle has at most four points, hence at most two triangle fans.
	int face = VERTEX_ID / 6;
	int slot = VERTEX_ID % 6;
	vec3 source[3];
	for (int i = 0; i < 3; i++) {
		source[i] = globe_basis * face_value(face, i).xyz;
	}
	vec2 points[4];
	vec3 view_units[4];
	int count = 0;
	vec3 previous = source[2];
	for (int i = 0; i < 3; i++) {
		vec3 current = source[i];
		bool inside = current.z >= 0.0;
		if (inside != (previous.z >= 0.0)) {
			float ratio = previous.z / (previous.z - current.z);
			vec3 horizon = mix(previous, current, ratio);
			points[count] = screen_point(horizon);
			view_units[count] = horizon;
			count++;
		}
		if (inside) {
			points[count] = screen_point(current);
			view_units[count] = current;
			count++;
		}
		previous = current;
	}
	int fan = slot / 3;
	VERTEX = vec2(-10000.0);
	float local_vertex_height = 0.0;
	if (count >= 3 && fan < count - 2) {
		vec2 triangle[3];
		triangle[0] = points[0];
		triangle[1] = points[fan + 1];
		triangle[2] = points[fan + 2];
		vec2 first = triangle[1] - triangle[0];
		vec2 second = triangle[2] - triangle[0];
		float determinant = cross_2d(first, second);
		if (abs(determinant) > 0.000001) {
			int corner = slot % 3;
			vec2 point = triangle[corner];
			// Physical subtraction uses the same exact edge rasterization.
			vec2 covered = point;
			VERTEX = covered;
			local_vertex_height = local_displacement(view_units[corner==0 ? 0 : fan+corner]);
		}
	}
	map_pixel = VERTEX;
	if (region_mode && local_projection>0.5 && VERTEX.x>-9999.0) { VERTEX.y -= local_vertex_height; }
}


void fragment() {
	COLOR=water_color;
	if (!region_mode) {
		vec3 normal_view = globe_view_normal(map_pixel,globe_center,globe_radius);
		COLOR.rgb = ocean_surface ? chart_ocean(water_color.rgb,normal_view,globe_basis) : solar_ground(water_color.rgb,normal_view);
	}
	COLOR.a*=1.0-local_cover(map_pixel);
}
