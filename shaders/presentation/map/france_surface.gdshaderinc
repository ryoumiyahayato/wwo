// Linear-data material on the existing physical triangles / native DEM.
// It never defines coastline, political membership or historical land use.
uniform sampler2D surface_base : filter_linear_mipmap, repeat_disable;
uniform vec4 surface_base_bounds = vec4(0.0);
uniform int surface_base_encoding = 0;
uniform vec4 surface_base_feather = vec4(0.0);
uniform float surface_base_opacity = 1.0;
uniform sampler2D surface_secondary : filter_linear_mipmap, repeat_disable;
uniform vec4 surface_secondary_bounds = vec4(0.0);
uniform int surface_secondary_encoding = 0;
uniform vec4 surface_secondary_feather = vec4(0.0);
uniform float surface_secondary_opacity = 1.0;
uniform float surface_weight = 0.0;
uniform float surface_detail_weight = 0.0;
// Source-aware observed-cover contribution. No extra sampler or map layer.
uniform float surface_cover_base = 1.0;
uniform float surface_cover_secondary = 1.0;
uniform float surface_print_detail = 1.0;
uniform float surface_cover_0 = 1.0;
uniform float surface_cover_1 = 1.0;
uniform float surface_cover_2 = 1.0;
uniform float surface_cover_3 = 1.0;
uniform sampler2D surface_tile_0 : filter_linear_mipmap, repeat_disable;
uniform sampler2D surface_tile_1 : filter_linear_mipmap, repeat_disable;
uniform sampler2D surface_tile_2 : filter_linear_mipmap, repeat_disable;
uniform sampler2D surface_tile_3 : filter_linear_mipmap, repeat_disable;
uniform vec4 surface_bounds_0 = vec4(0.0);
uniform vec4 surface_bounds_1 = vec4(0.0);
uniform vec4 surface_bounds_2 = vec4(0.0);
uniform vec4 surface_bounds_3 = vec4(0.0);
uniform float surface_inset_0 = 0.0;
uniform float surface_inset_1 = 0.0;
uniform float surface_inset_2 = 0.0;
uniform float surface_inset_3 = 0.0;
uniform int surface_encoding_0 = 0;
uniform int surface_encoding_1 = 0;
uniform int surface_encoding_2 = 0;
uniform int surface_encoding_3 = 0;

uniform vec4 surface_core_0 = vec4(0.0);
uniform vec4 surface_edges_0 = vec4(0.0);
uniform vec4 surface_core_1 = vec4(0.0);
uniform vec4 surface_edges_1 = vec4(0.0);
uniform vec4 surface_core_2 = vec4(0.0);
uniform vec4 surface_edges_2 = vec4(0.0);
uniform vec4 surface_core_3 = vec4(0.0);
uniform vec4 surface_edges_3 = vec4(0.0);
uniform float surface_cover_4 = 1.0;
uniform sampler2D surface_tile_4 : filter_linear_mipmap, repeat_disable;
uniform vec4 surface_bounds_4 = vec4(0.0);
uniform float surface_inset_4 = 0.0;
uniform int surface_encoding_4 = 0;
uniform vec4 surface_core_4 = vec4(0.0);
uniform vec4 surface_edges_4 = vec4(0.0);
uniform float surface_cover_5 = 1.0;
uniform sampler2D surface_tile_5 : filter_linear_mipmap, repeat_disable;
uniform vec4 surface_bounds_5 = vec4(0.0);
uniform float surface_inset_5 = 0.0;
uniform int surface_encoding_5 = 0;
uniform vec4 surface_core_5 = vec4(0.0);
uniform vec4 surface_edges_5 = vec4(0.0);

vec2 surface_ll(vec2 ll, vec4 bounds) {
	ll.x += 360.0*floor(((bounds.x+bounds.z)*0.5-ll.x)/360.0+0.5);
	return ll;
}

vec2 surface_uv(vec2 ll, vec4 bounds) {
	ll = surface_ll(ll,bounds);
	return vec2((ll.x-bounds.x)/max(bounds.z-bounds.x,0.000001),
		(bounds.w-ll.y)/max(bounds.w-bounds.y,0.000001));
}

float surface_tile_weight(vec2 ll, vec4 bounds, float inset) {
	if (inset<=0.0) { return 0.0; }
	ll = surface_ll(ll,bounds);
	vec2 rim = min(ll-bounds.xy,bounds.zw-ll);
	return smoothstep(0.0,inset,rim.x)*smoothstep(0.0,inset,rim.y)*surface_detail_weight;
}

vec3 surface_palette(vec4 data) {
	// Neutral hypsometric printing tones, not inferred grassland or rock type.
	vec3 tone = mix(vec3(0.57,0.57,0.46),vec3(0.70,0.68,0.62),smoothstep(0.2,0.95,data.r));
	// ESA WorldCover 2021 class 10, including plantations. Not 1900 forest.
	return mix(tone,vec3(0.27,0.38,0.27),data.b*0.78);
}

bool surface_contains(vec2 ll, vec4 bounds) {
	ll = surface_ll(ll,bounds);
	return bounds.z>bounds.x && bounds.w>bounds.y && all(greaterThanEqual(ll,bounds.xy)) && all(lessThanEqual(ll,bounds.zw));
}

// Canonical value: linear terrain colour + fixed DEM hillshade. Coverage is
// separate so the unchanged French height/tree data and R43 observed cover
// use the same material slots without averaging incompatible channel meanings.
vec4 surface_cartography(vec3 observed, float form, float resolved) {
	// Keep the DEM's landform even after coarse cover colour yields to map
	// geometry. Both sides of a source handoff use the same relief palette.
	float relief = mix(1.0,form,0.78);
	vec3 ground = vec3(0.60,0.588,0.512)*relief;
	return vec4(mix(ground,observed,resolved*surface_print_detail),relief);
}

vec4 surface_decode(vec4 value, int encoding, float cover_weight, out float coverage) {
	if (encoding==6) {
		// RGB retains observed classes; A is independent metric DEM print.
		// Coarse class samples cannot supply near-view land-use boundaries.
		// A / .57 is the independent neutral DEM print relative to its lowland
		// reference tone. RGB already carries illumination; ink consumes A.
		coverage = smoothstep(0.01,0.075,value.a);
		return surface_cartography(value.rgb,value.a/0.57,cover_weight);
	}
	if (encoding==5) {
		coverage = value.a;
		// This legacy format bakes relief and land cover together into RGB.
		// Keep some of that signal at close scales, where a separate hillshade
		// cannot be recovered and a zero cover weight flattens the landscape.
		return surface_cartography(value.rgb,1.0,mix(0.45,1.0,cover_weight));
	}
	if (encoding>=1) {
		// All legacy material writers reserve zero for outside-source support;
		// valid fixed shade is at least.48, encoded as at least.08 here.
		coverage = smoothstep(0.01,0.075,value.a);
		return surface_cartography(value.rgb*(0.4+value.a),0.4+value.a,cover_weight);
	}
	coverage = value.a;
	return surface_cartography(surface_palette(value)*(0.4+value.g),0.4+value.g,cover_weight);
}

float surface_source_edge(vec2 ll, vec4 core, vec4 edges) {
	ll = surface_ll(ll,core);
	vec4 rim = vec4(ll-core.xy,core.zw-ll);
	float w = 1.0;
	if (edges.x>0.0) { w*=smoothstep(0.0,edges.x,rim.x); }
	if (edges.y>0.0) { w*=smoothstep(0.0,edges.y,rim.y); }
	if (edges.z>0.0) { w*=smoothstep(0.0,edges.z,rim.z); }
	if (edges.w>0.0) { w*=smoothstep(0.0,edges.w,rim.w); }
	return w;
}

vec4 surface_detail(vec4 value, vec2 ll) {
	// Decode each source before blending. National catalogues do not own pixels.
	vec4 total = vec4(0.0);
	float sum = 0.0;
	float coverage;
	float strength = 0.0;
	float w = surface_tile_weight(ll,surface_bounds_0,surface_inset_0)*surface_source_edge(ll,surface_core_0,surface_edges_0);
	if (w>0.0) { vec4 v=surface_decode(texture(surface_tile_0,surface_uv(ll,surface_bounds_0)),surface_encoding_0,surface_cover_0,coverage); w*=coverage; total+=v*w; sum+=w; strength=max(strength,w); }
	w = surface_tile_weight(ll,surface_bounds_1,surface_inset_1)*surface_source_edge(ll,surface_core_1,surface_edges_1);
	if (w>0.0) { vec4 v=surface_decode(texture(surface_tile_1,surface_uv(ll,surface_bounds_1)),surface_encoding_1,surface_cover_1,coverage); w*=coverage; total+=v*w; sum+=w; strength=max(strength,w); }
	w = surface_tile_weight(ll,surface_bounds_2,surface_inset_2)*surface_source_edge(ll,surface_core_2,surface_edges_2);
	if (w>0.0) { vec4 v=surface_decode(texture(surface_tile_2,surface_uv(ll,surface_bounds_2)),surface_encoding_2,surface_cover_2,coverage); w*=coverage; total+=v*w; sum+=w; strength=max(strength,w); }
	w = surface_tile_weight(ll,surface_bounds_3,surface_inset_3)*surface_source_edge(ll,surface_core_3,surface_edges_3);
	if (w>0.0) { vec4 v=surface_decode(texture(surface_tile_3,surface_uv(ll,surface_bounds_3)),surface_encoding_3,surface_cover_3,coverage); w*=coverage; total+=v*w; sum+=w; strength=max(strength,w); }
	w = surface_tile_weight(ll,surface_bounds_4,surface_inset_4)*surface_source_edge(ll,surface_core_4,surface_edges_4);
	if (w>0.0) { vec4 v=surface_decode(texture(surface_tile_4,surface_uv(ll,surface_bounds_4)),surface_encoding_4,surface_cover_4,coverage); w*=coverage; total+=v*w; sum+=w; strength=max(strength,w); }
	w = surface_tile_weight(ll,surface_bounds_5,surface_inset_5)*surface_source_edge(ll,surface_core_5,surface_edges_5);
	if (w>0.0) { vec4 v=surface_decode(texture(surface_tile_5,surface_uv(ll,surface_bounds_5)),surface_encoding_5,surface_cover_5,coverage); w*=coverage; total+=v*w; sum+=w; strength=max(strength,w); }
	// Fade each exposed source/LOD edge. A merged rectangle cannot describe
	// gaps, non-rectangular selections or a GLO90-to-ETOPO transition.
	// Complementary overlap weights describe coverage together. Taking only
	// their maximum leaked the coarse base between two installed neighbours.
	return sum>0.0 ? mix(value,total/max(sum,0.000001),min(sum,1.0)) : value;
}

float surface_extent_weight(vec2 ll, vec4 bounds, vec4 feather) {
	ll = surface_ll(ll,bounds);
	float w = 1.0;
	if (feather.x>0.0) { w*=smoothstep(bounds.x,bounds.x+feather.x,ll.x); }
	if (feather.y>0.0) { w*=smoothstep(bounds.y,bounds.y+feather.y,ll.y); }
	if (feather.z>0.0) { w*=1.0-smoothstep(bounds.z-feather.z,bounds.z,ll.x); }
	if (feather.w>0.0) { w*=1.0-smoothstep(bounds.w-feather.w,bounds.w,ll.y); }
	return w;
}

vec4 surface_sample(vec2 ll, out float coverage) {
	coverage = 0.0;
	vec4 value = vec4(0.0,0.0,0.0,1.0);
	if (surface_weight<=0.0) { return value; }
	if (surface_contains(ll,surface_base_bounds)) {
		value = surface_decode(texture(surface_base,surface_uv(ll,surface_base_bounds)),surface_base_encoding,surface_cover_base,coverage);
		coverage *= surface_extent_weight(ll,surface_base_bounds,surface_base_feather)*surface_base_opacity;
	}
	if (surface_contains(ll,surface_secondary_bounds)) {
		float second_coverage;
		vec4 second = surface_decode(texture(surface_secondary,surface_uv(ll,surface_secondary_bounds)),surface_secondary_encoding,surface_cover_secondary,second_coverage);
		second_coverage *= surface_extent_weight(ll,surface_secondary_bounds,surface_secondary_feather)*surface_secondary_opacity;
		float combined = coverage+second_coverage*(1.0-coverage);
		value = mix(value,second,second_coverage/max(combined,0.000001));
		coverage = combined;
	}
	value = surface_detail(value,ll);
	coverage *= surface_weight;
	return value;
}
