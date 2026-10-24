// One admitted native-60s geographic window. Never supplies land/sea identity.
uniform sampler2D relief_window : filter_linear, repeat_disable;
uniform vec4 relief_window_bounds = vec4(0.0,0.0,1.0,1.0);
uniform float relief_window_weight = 0.0;
uniform float relief_window_edge = 0.12;

vec2 bounded_relief(vec2 global_uv, vec2 coarse) {
	if (relief_window_weight<=0.001) { return coarse; }
	vec2 lon_lat = vec2((global_uv.x-0.5)*360.0,(0.5-global_uv.y)*180.0);
	vec2 uv = vec2((lon_lat.x-relief_window_bounds.x)/(relief_window_bounds.z-relief_window_bounds.x),
		(relief_window_bounds.w-lon_lat.y)/(relief_window_bounds.w-relief_window_bounds.y));
	if (any(lessThan(uv,vec2(0.0))) || any(greaterThan(uv,vec2(1.0)))) { return coarse; }
	vec2 rim = min(uv,vec2(1.0)-uv);
	float feather = smoothstep(0.0,relief_window_edge,rim.x)*smoothstep(0.0,relief_window_edge,rim.y);
	// Preserve the continuous regional base. Only a source-derived short
	// wavelength residual enters; a window never replaces the whole palette.
	float detail = (texture(relief_window,uv).r*255.0-128.0)/127.0*0.10;
	// Only R's directional term receives native detail. G continues to define
	// the same absolute-height palette on both sides of every window boundary.
	return vec2(clamp(coarse.r+0.5*detail*feather*relief_window_weight,0.0,1.0),coarse.g);
}
