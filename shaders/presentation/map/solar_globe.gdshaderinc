// Fixed external cartographic light in the shared observer frame:
// +X right, +Y up, +Z toward the orthographic camera. Earth orientation
// rotates geography into this frame; it must never rotate this light.
// Composition only, not a solar ephemeris, HUD position or GameClock state.
const vec3 CHART_SUN_VIEW = vec3(0.100,0.970,0.222);

vec3 globe_view_normal(vec2 pixel, vec2 center, float radius) {
	vec2 p = (pixel-center)/max(radius,0.001);
	return normalize(vec3(p.x,-p.y,sqrt(max(0.0,1.0-dot(p,p)))));
}

vec3 solar_ground(vec3 ink, vec3 view_normal) {
	float incidence = dot(view_normal,CHART_SUN_VIEW);
	float day = smoothstep(-0.16,0.21,incidence);
	vec3 fill = mix(vec3(0.33,0.42,0.54),vec3(1.07,1.035,0.985),day);
	return ink*fill*(1.0+0.26*max(incidence,0.0));
}

vec3 solar_ocean(vec3 water, vec3 view_normal, float ice) {
	vec3 half_vector = normalize(CHART_SUN_VIEW+vec3(0.0,0.0,1.0));
	float incidence = max(dot(view_normal,CHART_SUN_VIEW),0.0);
	float glint = pow(max(dot(view_normal,half_vector),0.0),384.0)*incidence*(1.0-0.85*ice);
	// A restrained warm reflection, only on physical ocean geometry.
	float grazing = 1.0-clamp(view_normal.z,0.0,1.0);
	vec3 color = solar_ground(water,view_normal)*mix(0.94,1.06,grazing)+vec3(0.15,0.19,0.18)*glint;
	float rim = pow(grazing,4.5);
	float edge_light = mix(0.25,1.0,smoothstep(0.0,0.6,incidence));
	return color+vec3(0.035,0.080,0.110)*rim*edge_light*(1.0-ice*0.6);
}
