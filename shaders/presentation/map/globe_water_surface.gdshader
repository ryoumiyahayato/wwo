shader_type canvas_item;
render_mode unshaded;

varying vec4 political_color;
uniform vec4 water_color = vec4(0.15,0.36,0.48,0.96);
uniform float paris_mask_weight = 0.0;
uniform float surface_expand_pixels = 0.0;
varying vec2 map_pixel;
uniform sampler2D relief_world : filter_linear, repeat_enable;
uniform sampler2D relief_region : filter_linear, repeat_enable;
uniform float relief_weight = 0.0;
uniform float relief_detail_weight = 0.0;
uniform sampler2D face_data : filter_nearest, repeat_disable;
uniform mat3 globe_basis = mat3(1.0);
uniform vec2 globe_center = vec2(0.0);
uniform float globe_radius = 220.0;
uniform bool region_mode = false;
uniform float region_km_per_pixel = 5.5;
uniform vec2 region_bearing = vec2(1.0, 0.0);
uniform vec4 surface_color = vec4(1.0);
uniform vec3 political_base_color = vec3(0.42, 0.50, 0.46);
uniform float flag_weight : hint_range(0.0, 1.0) = 1.0;
uniform float political_weight : hint_range(0.0, 1.0) = 1.0;
uniform vec3 physical_land_color = vec3(0.27, 0.32, 0.29);
uniform vec4 flag_bounds = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec2 flag_uv_scale = vec2(1.0);
uniform vec2 flag_uv_offset = vec2(0.0);
uniform vec2 flag_uv_rotation = vec2(1.0, 0.0);
uniform float map_saturation : hint_range(0.0, 1.0) = 0.70;
uniform float map_brightness : hint_range(0.0, 1.0) = 0.72;
uniform float highlight_compression : hint_range(0.0, 1.0) = 0.25;
uniform float minimum_perceived_luminance : hint_range(0.0, 0.3) = 0.18;
// Reference for the dark ocean/space palette, including the globe tint.
uniform vec3 background_reference = vec3(0.10, 0.14, 0.16);
uniform float background_luminance_separation : hint_range(0.0, 0.1) = 0.055;

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
	int face = int(VERTEX.x);
	int slot = int(VERTEX.y);
	vec3 source[3];
	vec2 source_uvs[3];
	for (int i = 0; i < 3; i++) {
		source[i] = globe_basis * face_value(face, i).xyz;
		source_uvs[i] = face_value(face, i + 3).xy;
	}
	vec2 points[4];
	vec2 uvs[4];
	int count = 0;
	vec3 previous = source[2];
	vec2 previous_uv = source_uvs[2];
	for (int i = 0; i < 3; i++) {
		vec3 current = source[i];
		bool inside = current.z >= 0.0;
		if (inside != (previous.z >= 0.0)) {
			float ratio = previous.z / (previous.z - current.z);
			vec3 horizon = mix(previous, current, ratio);
			points[count] = screen_point(horizon);
			uvs[count] = mix(previous_uv, source_uvs[i], ratio);
			count++;
		}
		if (inside) {
			points[count] = screen_point(current);
			uvs[count] = source_uvs[i];
			count++;
		}
		previous = current;
		previous_uv = source_uvs[i];
	}
	int fan = slot / 6;
	political_color = surface_color;
	VERTEX = vec2(-10000.0);
	UV = vec2(0.0);
	if (count >= 3 && fan < count - 2) {
		vec2 triangle[3];
		triangle[0] = points[0];
		triangle[1] = points[fan + 1];
		triangle[2] = points[fan + 2];
		vec2 first = triangle[1] - triangle[0];
		vec2 second = triangle[2] - triangle[0];
		float determinant = cross_2d(first, second);
		if (abs(determinant) > 0.000001) {
			int corner = (slot % 6) / 2;
			vec2 point = triangle[corner];
			// Expanded political faces hide opaque seams, but cause repeated alpha
			// blending during water fade-in. Pair each existing corner exactly;
			// shared edges rasterize once with no new mesh, triangulation or draw.
			vec2 covered = point;
			// Opaque coastal subtraction must also cover the political mesh's
			// subpixel seam expansion beyond its canonical exterior. Lakes and
			// translucent transitions keep exact corners to avoid repeated blend.
			if (surface_expand_pixels > 0.0 && water_color.a > 0.999) {
				vec2 incoming = normalize(point - triangle[(corner + 2) % 3]);
				vec2 outgoing = normalize(triangle[(corner + 1) % 3] - point);
				vec2 before = vec2(incoming.y, -incoming.x) * sign(determinant);
				vec2 after = vec2(outgoing.y, -outgoing.x) * sign(determinant);
				float tangent = tan(atan(cross_2d(before, after), dot(before, after)) * 0.25);
				covered += surface_expand_pixels * (slot % 2 == 0
					? before + vec2(-before.y, before.x) * tangent
					: after - vec2(-after.y, after.x) * tangent);
				if (dot(before, after) > 0.999) {
					covered = point + surface_expand_pixels * (before + after) / (1.0 + dot(before, after));
				}
			}
			vec2 delta = covered - triangle[0];
			vec2 uv = uvs[0] + (uvs[fan + 1] - uvs[0]) * cross_2d(delta, second) / determinant
				+ (uvs[fan + 2] - uvs[0]) * cross_2d(first, delta) / determinant;
			uv = ((uv - flag_bounds.xy) / flag_bounds.zw - vec2(0.5)) * flag_uv_scale;
			UV = vec2(uv.x * flag_uv_rotation.x - uv.y * flag_uv_rotation.y,
				uv.x * flag_uv_rotation.y + uv.y * flag_uv_rotation.x) + vec2(0.5) + flag_uv_offset;
			VERTEX = covered;
		}
	}
	map_pixel = VERTEX;
}


float paris_mask(vec2 pixel) {
 vec2 xy = (pixel-globe_center)*region_km_per_pixel;
 vec2 km = vec2(xy.x*region_bearing.x+xy.y*region_bearing.y, xy.x*region_bearing.y-xy.y*region_bearing.x);
 float angle = length(km)/6371.0088;
 vec3 view = vec3(km*sin(angle)/max(length(km),0.000001),cos(angle));
 vec3 earth = transpose(globe_basis)*view;
 vec3 paris = vec3(0.0270144,0.7530652,0.6573912);
 float distance_km = acos(clamp(dot(earth,normalize(paris)),-1.0,1.0))*6371.0088;
 return 1.0-paris_mask_weight*(1.0-smoothstep(285.0,300.0,distance_km));
}

void fragment() {
	COLOR=water_color;
	if (region_mode && paris_mask_weight > 0.001) { COLOR.a*=paris_mask(map_pixel); }
}
