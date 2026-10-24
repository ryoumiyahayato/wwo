// The user's original static ocean assets. Geography owns texture placement;
// the external solar direction remains in the observer frame.
// Read scalar variation from the original RGB files, not baked illumination.
uniform sampler2D ocean_detail : filter_linear_mipmap, repeat_enable;
uniform sampler2D ocean_ice : filter_linear_mipmap, repeat_enable;
#include "res://shaders/presentation/map/solar_globe.gdshaderinc"

vec3 chart_ocean(vec3 water, vec3 view_normal, mat3 earth_to_view) {
	vec3 earth = normalize(transpose(earth_to_view)*view_normal);
	float horizontal = length(earth.xz);
	float longitude = horizontal>0.000001 ? atan(earth.x,earth.z) : 0.0;
	vec2 uv = vec2(longitude/6.28318530718+0.5,0.5-asin(clamp(earth.y,-1.0,1.0))/3.14159265359);
	// A fixed coarse mip removes the supplied eddy filaments. One wrap across
	// the globe, with variation fading out before the longitude singularities.
	float detail = textureLod(ocean_detail,vec2(uv.x,clamp(uv.y,0.03125,0.96875)),4.0).b;
	float variation = clamp((detail-0.28)*2.2,-0.18,0.18)*(1.0-smoothstep(0.86,0.98,abs(earth.y)));
	vec3 base = mix(water,vec3(0.055,0.20,0.29),0.75);
	base *= 1.0+variation;
	base += vec3(-0.010,0.012,0.020)*variation;
	// Static cartographic cold-water/ice impression, not a dated sea-ice map.
	// Polar-plane mapping has no longitude pinching or radial ice spokes.
	float polar = earth.y>0.0 ? smoothstep(0.95106,0.99452,earth.y)*0.82 : smoothstep(0.91355,0.97815,-earth.y)*0.46;
	float ice = 0.0;
	if (polar>0.001) {
		float floe = textureLod(ocean_ice,earth.xz*2.2+vec2(0.5),5.0).b;
		ice = polar*mix(0.93,1.0,floe);
		base = mix(base,vec3(0.61,0.73,0.78),ice);
	}
	return solar_ocean(base,view_normal,ice);
}
