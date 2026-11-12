shader_type canvas_item;
uniform bool city_overview = false;
render_mode unshaded;

varying vec4 political_color;
varying vec2 map_pixel;
uniform sampler2D relief_world : filter_linear, repeat_enable;
uniform sampler2D relief_region : filter_linear, repeat_enable;
uniform float relief_weight = 0.0;
uniform float relief_detail_weight = 0.0;
uniform float reference_opacity = 1.0;
uniform float military_grid_step = 0.0;
uniform vec4 military_grid_projection = vec4(0.0);
uniform vec3 military_grid_origin = vec3(0.0);
uniform sampler2D face_data : filter_nearest, repeat_disable;
uniform sampler2D flag_texture : source_color, filter_linear, repeat_disable;
uniform mat3 globe_basis = mat3(1.0);
uniform vec2 globe_center = vec2(0.0);
uniform float globe_radius = 220.0;
uniform bool region_mode = false;
uniform bool antarctic_land = false;
uniform float region_km_per_pixel = 5.5;
uniform vec2 region_bearing = vec2(1.0, 0.0);
uniform vec4 surface_color = vec4(1.0);
uniform vec3 political_base_color = vec3(0.42, 0.50, 0.46);
uniform bool political_focus_style = false;
uniform float political_emphasis : hint_range(0.0,1.0) = 0.70;
uniform float flag_weight : hint_range(0.0, 1.0) = 1.0;
uniform float political_weight : hint_range(0.0, 1.0) = 1.0;
uniform vec3 physical_land_color = vec3(0.40, 0.44, 0.36);
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
#include "res://shaders/presentation/map/terrain_palette.gdshaderinc"
#include "res://shaders/presentation/map/regional_relief.gdshaderinc"
#include "res://shaders/presentation/map/france_surface.gdshaderinc"
#include "res://shaders/presentation/map/solar_globe.gdshaderinc"

vec2 relief_uv_at_pixel(vec2 pixel) {
	vec2 xy = pixel-globe_center;
	vec3 view_unit;
	if (region_mode) {
		vec2 km = vec2(xy.x*region_bearing.x+xy.y*region_bearing.y,
			xy.x*region_bearing.y-xy.y*region_bearing.x)*region_km_per_pixel;
		float distance = length(km);
		float angle = distance/6371.0088;
		view_unit = vec3(km*sin(angle)/max(distance,0.000001),cos(angle));
	} else {
		xy /= globe_radius;
		view_unit = normalize(vec3(xy.x,-xy.y,sqrt(max(0.0,1.0-dot(xy,xy)))));
	}
	vec3 earth = transpose(globe_basis)*view_unit;
	float longitude = length(earth.xz)>0.000001 ? atan(earth.x,earth.z) : 0.0;
	vec2 uv = vec2(longitude/6.28318530718+0.5,0.5-asin(clamp(earth.y,-1.0,1.0))/3.14159265359);
	return uv;
}

vec2 relief_at_uv(vec2 uv) {
	// A completed LOD uses one sample, rather than sampling both forever.
	if (relief_detail_weight>=0.999) { return bounded_relief(uv,texture(relief_region,vec2(uv.x,clamp(uv.y,0.5/2048.0,1.0-0.5/2048.0))).rg); }
	vec2 coarse = texture(relief_world,vec2(uv.x,clamp(uv.y,0.5/512.0,1.0-0.5/512.0))).rg;
	if (relief_detail_weight<=0.001) { return bounded_relief(uv,coarse); }
	return bounded_relief(uv,mix(coarse,texture(relief_region,vec2(uv.x,clamp(uv.y,0.5/2048.0,1.0-0.5/2048.0))).rg,relief_detail_weight));
}

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
	int fan = slot / 3;
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
			int corner = slot % 3;
			vec2 point = triangle[corner];
			// Exact shared edges; no per-triangle coastal expansion.
			// The horizon clip already interpolated this exact corner's UV.
			vec2 uv = uvs[corner == 0 ? 0 : fan + corner];
			uv = ((uv - flag_bounds.xy) / flag_bounds.zw - vec2(0.5)) * flag_uv_scale;
			UV = vec2(uv.x * flag_uv_rotation.x - uv.y * flag_uv_rotation.y,
				uv.x * flag_uv_rotation.y + uv.y * flag_uv_rotation.x) + vec2(0.5) + flag_uv_offset;
			VERTEX = point;
		}
	}
	map_pixel = VERTEX;
}

float military_grid(vec2 ll) {
	vec4 p=military_grid_projection;
	float phi=radians(clamp(ll.y,-85.0,85.0));
	float t=tan(3.14159265359*.25-phi*.5)/pow((1.0-p.w*sin(phi))/(1.0+p.w*sin(phi)),p.w*.5);
	float rho=p.y*pow(t,p.x);
	float angle=p.x*(radians(ll.x)-military_grid_origin.z);
	vec2 xy=military_grid_origin.xy+vec2(rho*sin(angle),p.z-rho*cos(angle));
	vec2 cell=xy/military_grid_step;
	vec2 distance=min(fract(cell),1.0-fract(cell))*military_grid_step;
	vec2 pixel=max(fwidth(xy),vec2(0.001));
	return 1.0-smoothstep(0.25,1.0,min(distance.x/pixel.x,distance.y/pixel.y));
}

void fragment() {
	vec2 terrain = vec2(0.5,0.0);
	vec4 regional_surface = vec4(0.0);
	float regional_coverage = 0.0;
	if (relief_weight>0.0) {
		vec2 geo_uv = relief_uv_at_pixel(map_pixel);
		if (region_mode && surface_weight>0.0) {
			regional_surface=surface_sample(vec2((geo_uv.x-.5)*360.0,(.5-geo_uv.y)*180.0),regional_coverage);
		}
		// A fully covered France pixel already has height and form. Avoid an
		// additional global/native sample whose result would be overwritten.
		if (regional_coverage<0.999) { terrain = relief_at_uv(geo_uv); }
	}
	// The physical material is independent of the political/flag ink layer.
	vec3 physical = relief_weight>0.0 ? terrain_base(terrain.g) : physical_land_color;
	if (regional_coverage>0.0) { physical = mix(physical,regional_surface.rgb,regional_coverage); }
	// Preserve the admitted Antarctic WORLD base without calling it political ink.
	if (antarctic_land && !region_mode) { physical = physical_land_color; }
	float ink_form = 1.0;
	if (relief_weight>0.0) {
		float coarse_form = terrain_form(terrain,relief_weight);
		float neutral_form = mix(1.0,regional_surface.a,clamp(relief_weight/0.92,0.0,1.0));
		ink_form = mix(coarse_form,neutral_form,regional_coverage);
		// Regional RGB already includes its metric DEM print. Apply the
		// independent neutral channel to ink, never shade that RGB twice.
		physical *= mix(coarse_form,1.0,regional_coverage);
	}
	bool globe_ink = !region_mode && political_focus_style && political_weight>0.0 && !antarctic_land;
	float pattern_weight = flag_weight;
	if (!globe_ink) {
		// Fade regional prints into the ground as the map approaches street scale.
		vec2 uv_per_pixel = abs(dFdx(UV)) + abs(dFdy(UV));
		float projected_span = min(1.0/max(uv_per_pixel.x,0.00001),1.0/max(uv_per_pixel.y,0.00001));
		float print_strength = mix(0.62,0.82,smoothstep(0.60,0.96,political_emphasis));
		pattern_weight *= smoothstep(12.0,48.0,projected_span) * print_strength
			* mix(1.0,0.68,smoothstep(120.0,340.0,projected_span));
	}
	vec4 flag = vec4(0.0);
	if (pattern_weight>0.001 && political_color.a>0.0) { flag = texture(flag_texture,clamp(UV,vec2(0.0),vec2(1.0))); }
	vec3 flag_tone = flag.rgb;
	vec3 political_tone = political_base_color;
	if (globe_ink) {
		// Apply sunlight to the physical globe before laying down political ink.
		physical = solar_ground(physical,globe_view_normal(map_pixel,globe_center,globe_radius));
		ink_form = mix(1.0,ink_form,0.22);
	} else {
		float luminance = dot(flag.rgb,vec3(0.2126,0.7152,0.0722));
		float saturation = political_focus_style ? mix(0.76,0.94,political_emphasis) : map_saturation;
		flag_tone = mix(vec3(luminance),flag.rgb,saturation);
		float peak = max(flag_tone.r,max(flag_tone.g,flag_tone.b));
		float brightness = political_focus_style ? mix(0.84,0.98,political_emphasis) : map_brightness;
		flag_tone *= brightness/(1.0+highlight_compression*peak);
		if (political_focus_style) {
			float value = dot(political_tone,vec3(0.2126,0.7152,0.0722));
			political_tone = mix(vec3(value),political_tone,mix(0.26,0.67,political_emphasis))*mix(0.86,1.04,political_emphasis);
		}
	}
	vec3 base = mix(physical, political_tone*ink_form, political_weight);
	vec3 surface = mix(base,flag_tone*ink_form,political_color.a*flag.a*pattern_weight);
	// One global dark-tone rule, after selection modulation. A neutral lift
	// preserves hue (all RGB channel differences scale together), including
	// blue, red, green and brown. Bright white/yellow samples receive no lift.
	float surface_luminance = dot(surface, vec3(0.2126, 0.7152, 0.0722));
	float background_luminance = dot(background_reference, vec3(0.2126, 0.7152, 0.0722));
	float visibility_floor = max(minimum_perceived_luminance, background_luminance + background_luminance_separation);
	float neutral_lift = max(visibility_floor - surface_luminance, 0.0) / max(1.0 - surface_luminance, 0.0001);
	surface = mix(surface, vec3(1.0), neutral_lift);
	// Only the existing classified physical Antarctica triangles use this.
	// This classification is not inferred from elevation or applied to flags.
	if (antarctic_land) { surface = mix(surface,terrain_snow_base(terrain.g),0.80); }
	if (!region_mode && !globe_ink) { surface = solar_ground(surface,globe_view_normal(map_pixel,globe_center,globe_radius)); }
	if (military_grid_step>0.0) {
		vec2 uv=relief_uv_at_pixel(map_pixel);
		float grid=military_grid(vec2((uv.x-.5)*360.0,(.5-uv.y)*180.0));
		surface=mix(surface,vec3(0.75,0.82,0.70),grid*0.55);
	}
	COLOR = vec4(surface, reference_opacity);

}
