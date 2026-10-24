// Physical printing tones only. Log height is the existing ETOPO encoding,
// not a land-use, vegetation, snow or geological classification.
vec3 terrain_base(float log_height) {
	vec3 low = vec3(0.41,0.45,0.37);
	vec3 upland = vec3(0.50,0.48,0.40);
	vec3 high = vec3(0.60,0.57,0.50);
	vec3 tone = mix(low,upland,smoothstep(0.08,0.60,log_height));
	return mix(tone,high,smoothstep(0.60,0.98,log_height));
}

// Requires the existing sourced Antarctic land context. Height modulates
// printing tone only; it never decides snow coverage elsewhere.
vec3 terrain_snow_base(float log_height) {
	return mix(vec3(0.70,0.78,0.81),vec3(0.84,0.88,0.89),smoothstep(0.04,0.82,log_height));
}

float terrain_form(vec2 reference, float weight) {
	// R contains two-light hillshade plus the original 0.28*height lift.
	// Separate those channels; do not turn height itself into a shadow.
	float directional = reference.r*2.0-1.0-0.28*reference.g;
	return clamp(1.0+directional*weight*1.65,0.64,1.22);
}
