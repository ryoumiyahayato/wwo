shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform mat3 source_frame = mat3(1.0);
uniform vec4 coverage0 = vec4(0.0);
uniform vec4 coverage1 = vec4(0.0);
uniform vec3 tone = vec3(0.45);
uniform float strength = 1.0;
varying vec2 source_ll;

void vertex() {
	vec2 km=vec2(VERTEX.x,-VERTEX.z)*0.001;
	float distance_km=length(km);
	float angle=distance_km/6371.0088;
	vec3 unit=source_frame*vec3(km*sin(angle)/max(distance_km,0.000001),cos(angle));
	source_ll=degrees(vec2(atan(unit.x,unit.z),asin(clamp(unit.y,-1.0,1.0))));
}

float coverage(vec4 bounds) {
	if (bounds.z<=bounds.x) return 0.0;
	vec2 edge=min(source_ll-bounds.xy,bounds.zw-source_ll)*vec2(111195.0*cos(radians(source_ll.y)),111195.0);
	return smoothstep(0.0,1000.0,min(edge.x,edge.y));
}

void fragment() {
	ALBEDO=tone;
	ALPHA=strength*max(coverage(coverage0),coverage(coverage1));
}
