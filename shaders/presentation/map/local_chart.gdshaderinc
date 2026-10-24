// Shared LOCAL sampling for the existing 2D chart shaders. Coordinates and
// triangle interpolation are identical to RegionView's displayed DEM mesh.
uniform vec4 local_bounds = vec4(0.0);
uniform vec2 local_edge = vec2(0.12);
uniform sampler2D local_water : filter_nearest, repeat_disable;
uniform sampler2D local_height : filter_nearest, repeat_disable;
uniform float local_projection = 0.0;
uniform float local_vertical_pixels = 0.0;
uniform float local_cover_strength = 0.0;
uniform bool local_line_owner = false;

vec2 local_uv(vec3 view_unit) {
	vec3 earth = transpose(globe_basis)*normalize(view_unit);
	vec2 ll = vec2(degrees(atan(earth.x,earth.z)),degrees(asin(clamp(earth.y,-1.0,1.0))));
	return vec2((ll.x-local_bounds.x)/max(local_bounds.z-local_bounds.x,0.000001),
		(local_bounds.w-ll.y)/max(local_bounds.w-local_bounds.y,0.000001));
}

float local_displacement(vec3 view_unit) {
	if (!region_mode || local_projection<0.5) { return 0.0; }
	vec2 uv = local_uv(view_unit);
	if (any(lessThan(uv,vec2(0.0))) || any(greaterThan(uv,vec2(1.0)))) { return 0.0; }
	ivec2 dimensions = textureSize(local_height,0);
	vec2 grid = uv*vec2(dimensions-ivec2(1));
	ivec2 cell = clamp(ivec2(floor(grid)),ivec2(0),dimensions-ivec2(2));
	vec2 t = grid-vec2(cell);
	float a = texelFetch(local_height,cell,0).r;
	float b = texelFetch(local_height,cell+ivec2(1,0),0).r;
	float c = texelFetch(local_height,cell+ivec2(0,1),0).r;
	float d = texelFetch(local_height,cell+ivec2(1),0).r;
	float height = t.x+t.y<=1.0 ? a+(b-a)*t.x+(c-a)*t.y : d+(c-d)*(1.0-t.x)+(b-d)*(1.0-t.y);
	// Annotation projection returns to the flat chart where the native
	// surface stops contributing. This does not flatten the 3D DEM itself.
	vec2 rim = smoothstep(vec2(0.0),local_edge,min(uv,vec2(1.0)-uv));
	return height*local_vertical_pixels*rim.x*rim.y;
}

vec3 local_view_at_pixel(vec2 flat_pixel) {
	vec2 xy = (flat_pixel-globe_center)*region_km_per_pixel;
	vec2 km = vec2(xy.x*region_bearing.x+xy.y*region_bearing.y,xy.x*region_bearing.y-xy.y*region_bearing.x);
	float distance = length(km);
	float angle = distance/6371.0088;
	return vec3(km*sin(angle)/max(distance,0.000001),cos(angle));
}

float local_cover_unit(vec3 view_unit) {
	if (!region_mode || local_cover_strength<=0.0) { return 0.0; }
	vec2 uv = local_uv(view_unit);
	if (any(lessThan(uv,vec2(0.0))) || any(greaterThan(uv,vec2(1.0)))) { return 0.0; }
	vec2 rim = smoothstep(vec2(0.0),local_edge,min(uv,vec2(1.0)-uv));
	float ownership = local_line_owner ? 1.0 : texture(local_water,uv).r;
	return ownership*rim.x*rim.y*local_cover_strength;
}

float local_cover(vec2 flat_pixel) {
	if (!region_mode || local_cover_strength<=0.0) { return 0.0; }
	return local_cover_unit(local_view_at_pixel(flat_pixel));
}
