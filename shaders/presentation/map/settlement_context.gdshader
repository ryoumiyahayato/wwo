shader_type canvas_item;
render_mode unshaded;
uniform float strength = 1.0;
uniform mat3 globe_basis = mat3(1.0);
uniform vec2 globe_center = vec2(0.0);
uniform float region_km_per_pixel = 1.0;
uniform vec2 region_bearing = vec2(1.0,0.0);
uniform vec4 detail_bounds0 = vec4(0.0);
uniform vec4 detail_bounds1 = vec4(0.0);
uniform vec4 detail_bounds2 = vec4(0.0);
uniform vec3 detail_weights = vec3(0.0);
uniform vec4 print_coverage0 = vec4(0.0);
uniform vec4 print_coverage1 = vec4(0.0);
uniform vec4 print_coverage2 = vec4(0.0);
uniform vec4 metropolitan0 = vec4(0.0);
uniform vec4 metropolitan1 = vec4(0.0);
uniform vec4 metropolitan2 = vec4(0.0);
uniform bool building_print = false;
uniform bool street_print = false;
uniform bool window_baked = false;
uniform bool coverage_mask = false;
uniform bool woodland_mask = false;
uniform float generalisation_opacity = 1.0;
uniform float ground_continuity = 0.0;
uniform float detailed_weight = 0.0;
uniform sampler2D building_mask : filter_linear_mipmap, repeat_disable;
varying vec2 source_ll;
void vertex() {
	source_ll=VERTEX;
	vec2 ll=radians(VERTEX);
	vec3 p=globe_basis*vec3(cos(ll.y)*sin(ll.x),sin(ll.y),cos(ll.y)*cos(ll.x));
	float sine=length(p.xy);
	vec2 km=p.xy*(6371.0088*atan(sine,p.z)/max(sine,0.000001));
	VERTEX=globe_center+vec2(km.x*region_bearing.x+km.y*region_bearing.y,km.x*region_bearing.y-km.y*region_bearing.x)/region_km_per_pixel;
}
float detail(vec4 bounds) {
	if (bounds.z<=bounds.x) return 0.0;
	vec2 metres_per_degree=vec2(111195.0*cos(radians(source_ll.y)),111195.0);
	vec2 edge=min(source_ll-bounds.xy,bounds.zw-source_ll)*metres_per_degree;
	return smoothstep(0.0,1000.0,min(edge.x,edge.y));
}
float print_coverage(vec4 window) {
	if (window.z<=0.0) return 0.0;
	vec2 km=(source_ll-window.xy)*vec2(111.195*cos(radians(window.y)),111.195);
	return 1.0-smoothstep(max(0.0,window.z-window.w),window.z,length(km));
}
float metropolitan(vec4 window) {
	if (window.w<=window.z) return 0.0;
	vec2 km=(source_ll-window.xy)*vec2(111.195*cos(radians(window.y)),111.195);
	return 1.0-smoothstep(window.z,window.w,length(km));
}

// A cartographic fill clipped to mapped built-up ground. Its marks represent
// blocks at this scale, not individual buildings or surveyed street lines.
float town_blocks() {
	vec2 metres=source_ll*vec2(111195.0*cos(radians(source_ll.y)),111195.0);
	metres+=vec2(58.0*sin(metres.y*0.002),45.0*sin(metres.x*0.0017));
	vec2 blocks=metres/vec2(320.0,235.0);
	blocks.x+=0.5*mod(floor(blocks.y),2.0);
	vec2 edge=abs(fract(blocks)-vec2(0.5));
	vec2 pixel=clamp(vec2(region_km_per_pixel*1000.0)/vec2(320.0,235.0),vec2(0.015),vec2(0.26));
	vec2 inside=1.0-smoothstep(vec2(0.34,0.31)-pixel*0.5,vec2(0.34,0.31)+pixel*0.5,edge);
	return inside.x*inside.y*(1.0-smoothstep(0.065,0.155,region_km_per_pixel));
}

void fragment() {
	float keep=(1.0-detail(detail_bounds0)*detail_weights.x)*(1.0-detail(detail_bounds1)*detail_weights.y)*(1.0-detail(detail_bounds2)*detail_weights.z);
	if (coverage_mask && !woodland_mask) {
		// The broad raster is a settlement cue. Close roofs and mapped
		// features carry the geometry when its cells are oversampled.
		float coverage=texture(building_mask,UV).r;
		float ink=mix(0.09,0.37,smoothstep(0.35,1.0,generalisation_opacity));
		COLOR=vec4(0.58,0.47,0.36,smoothstep(0.09,0.58,coverage)*ink);
	}
	if (building_print) {
		float extent=window_baked ? 1.0 : max(print_coverage(print_coverage0),max(print_coverage(print_coverage1),print_coverage(print_coverage2)));
		vec2 print_ink=texture(building_mask,UV).rg;
		// A regional pixel covers several roofs and streets. Preserve their
		// fractional coverage so the network survives texture minification.
		float overview=smoothstep(0.035,0.13,region_km_per_pixel);
		float roof=pow(print_ink.r,mix(0.70,0.54,overview))*0.93;
		float street=street_print ? pow(print_ink.g,mix(1.0,0.60,overview))*mix(0.64,0.88,overview)
			*(1.0-smoothstep(0.14,0.23,region_km_per_pixel))*(1.0-roof) : 0.0;
		float edge=clamp(0.45+(dFdx(print_ink.r)-dFdy(print_ink.r))*0.42,0.0,1.0);
		vec3 roof_tone=mix(vec3(0.28,0.23,0.18),vec3(0.49,0.36,0.26),edge);
		vec3 street_tone=vec3(0.85,0.76,0.59);
		COLOR=vec4((roof_tone*roof+street_tone*street)/max(roof+street,0.001),(roof+street)*strength*keep*extent);
	} else if (coverage_mask && woodland_mask) {
		vec2 coverage=texture(building_mask,UV).rg;
		// The fallback stores area, not individual buildings. Keep sparse
		// cells faint while the district polygons and roof prints load.
		float built=smoothstep(0.10,0.55,coverage.r)*0.49;
		float wood=coverage.g*0.22*(1.0-built);
		vec3 tone=vec3(0.58,0.47,0.36)*built+vec3(0.27,0.39,0.29)*wood;
		COLOR=vec4(tone/max(built+wood,0.001),(built+wood)*strength*generalisation_opacity);
	} else if (COLOR.b>COLOR.r+0.05) {
		// Sourced river faces share this canvas and projection. Ground-cover
		// opacity must not turn a real water polygon into translucent land.
		COLOR.a*=strength;
	// The detailed source window is not a land-cover boundary. Keep the same
	// generalised ground beneath and beyond it; only duplicate roofs give way.
	} else {
		// Small sourced built-up polygons must remain readable when the player
		// approaches them. Woodland keeps its lighter map tint.
		bool settlement=COLOR.r>COLOR.g || COLOR.b>COLOR.r;
		float metro=max(metropolitan(metropolitan0),max(metropolitan(metropolitan1),metropolitan(metropolitan2)))*detailed_weight;
		if (settlement) {
			float schematic=(1.0-metro)*keep;
			float block=town_blocks()*schematic;
			vec3 town=mix(vec3(0.65,0.55,0.43),vec3(0.37,0.29,0.22),block*0.86);
			COLOR.rgb=mix(town,COLOR.rgb,metro);
			float town_ink=mix(1.38,2.32,block);
			float existing_ink=mix(generalisation_opacity,0.24,ground_continuity);
			COLOR.a*=strength*mix(town_ink,existing_ink,1.0-schematic);
		} else if (COLOR.g>COLOR.r+0.035 && COLOR.g>COLOR.b+0.035) {
			// A mapped woodland outline stays readable when oversampled cover
			// colour fades. This is the same polygon, with no added tree mesh.
			COLOR.rgb=mix(COLOR.rgb,vec3(0.27,0.39,0.29),0.60);
			COLOR.a*=strength*mix(max(generalisation_opacity,0.85),1.55,ground_continuity);
		} else {
			COLOR.a*=strength*generalisation_opacity;
		}
	}
}
