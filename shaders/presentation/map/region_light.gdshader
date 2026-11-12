shader_type canvas_item;
render_mode unshaded;

uniform float km_per_pixel = 1.0;
#include "res://shaders/presentation/map/solar_globe.gdshaderinc"

void fragment() {
	// Match the globe's screen-relative light across the projection handoff.
	vec2 map_offset = (UV-vec2(0.5))/TEXTURE_PIXEL_SIZE;
	vec3 normal_view = globe_view_normal(map_offset,vec2(0.0),6371.0088/km_per_pixel);
	float strength = 0.78*smoothstep(0.9,4.5,km_per_pixel);
	COLOR.rgb = mix(COLOR.rgb,solar_ground(COLOR.rgb,normal_view),strength);
}
