shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_prepass_alpha;

uniform vec4 map_ink_tone : source_color = vec4(0.42,0.50,0.46,1.0);
uniform float map_ink_weight = 0.0;
uniform float local_strength = 1.0;
uniform float cartographic_relief_weight = 0.84;
uniform mat3 normal_to_geographic = mat3(1.0);
uniform bool context_terrain = false;
uniform bool city_overview = false;
uniform bool woodland_enabled = false;
uniform bool local_palette_enabled = false;
uniform vec4 ground_low_tone : source_color = vec4(0.41,0.45,0.37,1.0);
uniform vec4 ground_high_tone : source_color = vec4(0.60,0.57,0.50,1.0);
uniform sampler2D woodland_mask : filter_linear, repeat_disable;
uniform vec4 survey_bounds = vec4(0.0);
uniform bool urban_enabled = false;
uniform vec4 urban_centres[4];
uniform vec4 urban_connections[4];
uniform bool context_water_enabled = false;
uniform sampler2D context_water_mask : filter_linear, repeat_disable;
uniform vec4 context_water_bounds = vec4(0.0);
varying vec3 geographic_normal;
varying float edge_weight;
varying vec3 cover_colour;
varying float cover_kind;
varying vec2 chart_metres;
#include "res://shaders/presentation/map/terrain_palette.gdshaderinc"
#include "res://shaders/presentation/map/france_surface.gdshaderinc"

void vertex() {
	// Native DEM normals, independent of camera movement. A fill direction
	// retains readable valleys without adding any vertical exaggeration.
	geographic_normal = normal_to_geographic*NORMAL;
	edge_weight = COLOR.a;
	cover_colour = COLOR.rgb;
	cover_kind = UV2.y;
	chart_metres = vec2(VERTEX.x,-VERTEX.z);
}

void fragment() {
	if (cover_kind < -0.5) {
		// Acquired water retains its hydrographic ink, not ground relief.
		ALBEDO = cover_colour;
	} else {
		vec3 n = normalize(geographic_normal);
		// Fixed geographic key and opposing fill use actual native normals.
		// No source-window contrast stretch or second valley shadow.
		float key = max(0.0,dot(n,vec3(-0.5,0.70710678,-0.5)));
		float fill = max(0.0,dot(n,vec3(0.5,0.70710678,0.5)));
		// Opposing fill preserves back-facing slopes. No shared hard clamp may
		// collapse a whole mountain face to one brightness.
		float illumination = 0.68+0.45*(0.65*key+0.35*fill);
		float hillshade = mix(1.0,illumination,clamp(cartographic_relief_weight/0.92,0.0,1.0));
		float slope_weight = sqrt(max(0.0,1.0-n.y*n.y));
		vec3 ground = terrain_base(UV2.x);
		if (local_palette_enabled) {
			// Explicit cartographic palette, independent of path or biome class.
			ground = mix(ground_low_tone.rgb,ground_high_tone.rgb,smoothstep(0.0,0.45,UV2.x));
		}
		// Slope tint is a printing convention, not a rock/forest cover assertion.
		ground = mix(ground,vec3(0.56,0.53,0.46),smoothstep(0.18,0.78,slope_weight)*0.12);
		// Modern coverage is a bounded colour input on this same DEM surface.
		// Linear sampling softens only the mask texel edge; no invented trees,
		// altitude-based vegetation or extra transparent woodland plane.
		vec2 rim = min(UV,vec2(1.0)-UV);
		float native_weight = smoothstep(0.0,0.12,rim.x)*smoothstep(0.0,0.12,rim.y);
		// Same geographic material as REGION; preserve the actual native mesh.
		vec2 ll = vec2(mix(survey_bounds.x,survey_bounds.z,UV.x),mix(survey_bounds.w,survey_bounds.y,UV.y));
		float regional_coverage = 0.0;
		vec4 regional_surface = vec4(0.0);
		// Reuse the installed geographic colour on the native mesh. Its neutral
		// DEM print is removed before native-normal lighting is applied.
		regional_surface = surface_sample(ll,regional_coverage);
		float inkshade = hillshade;
		// Only colour and illumination rejoin the reference chart at the rim.
		// No source height, normal or water edge is flattened or extended.
		if (regional_coverage>0.0) {
			// The contextual mesh is terrain too. Keep its own normals until
			// the actual outer handover; the native survey rim is not a LOD edge.
			float join_weight = regional_coverage*(1.0-edge_weight);
			vec3 regional_ground = regional_surface.rgb/max(regional_surface.a,0.4);
			// Colour belongs to the same geographic chart on both meshes. Native
			// normals and heights carry the acquired form; a constant DEM palette
			// over the context rectangle would erase the surrounding map's ink.
			ground = mix(ground,regional_ground,local_palette_enabled ? join_weight : regional_coverage);
			float regional_form = mix(1.0,regional_surface.a,clamp(cartographic_relief_weight/0.92,0.0,1.0));
			inkshade = mix(hillshade,regional_form,join_weight);
			hillshade = mix(hillshade,regional_surface.a,join_weight);
		}
		if (woodland_enabled && all(greaterThanEqual(UV,vec2(0.0))) && all(lessThanEqual(UV,vec2(1.0)))) {
			float coverage = texture(woodland_mask,UV).r*native_weight;
			ground = mix(ground,vec3(0.34,0.41,0.33),coverage*0.44);
		}
		if (urban_enabled) {
			// Explicit concept composition around existing known anchors. These
			// blocks and links are not surveyed streets, buildings or land use.
			float urban = 0.0;
			float connection = 0.0;
			for (int i=0;i<4;i++) {
				vec4 hub = urban_centres[i];
				if (hub.z>0.0) { urban=max(urban,1.0-smoothstep(hub.z*0.62,hub.z,length(chart_metres-hub.xy))); }
				vec4 route = urban_connections[i];
				vec2 span = route.zw-route.xy;
				if (dot(span,span)>1.0) {
					float t=clamp(dot(chart_metres-route.xy,span)/dot(span,span),0.0,1.0);
					float distance=length(chart_metres-route.xy-span*t);
					connection=max(connection,1.0-smoothstep(8.0,15.0,distance));
					urban=max(urban,(1.0-smoothstep(250.0,550.0,distance))*0.85);
				}
			}
			// Aggregate engraved block texture, not additional building instances
			// or a street dataset. Staggered parcels avoid a continuous false grid.
			vec2 city_axes=mat2(vec2(0.996,0.087),vec2(-0.087,0.996))*chart_metres;
			float band=floor(city_axes.y/95.0);
			vec2 parcel=vec2(city_axes.x+mod(band,3.0)*37.0,city_axes.y);
			vec2 cell=floor(parcel/vec2(137.0,95.0));
			vec2 within=mod(parcel,vec2(137.0,95.0));
			float variant=fract(sin(dot(cell,vec2(12.9898,78.233)))*43758.5453);
			vec2 half_size=vec2(48.0+variant*9.0,31.0+variant*5.0);
			vec2 margin=half_size-abs(within-vec2(68.5,47.5));
			float block=smoothstep(-max(fwidth(margin.x),fwidth(margin.y)),1.5,min(margin.x,margin.y));
			vec3 city=mix(vec3(0.57,0.55,0.47),vec3(0.38,0.37,0.33)+variant*0.055,block);
			ground=mix(ground,city,urban*0.78);
			// Dashed conceptual links join the known anchors; they are not roads.
			float dash=step(0.45,fract((chart_metres.x+chart_metres.y)/65.0));
			ground=mix(ground,vec3(0.68,0.61,0.46),connection*urban*dash*0.65);
		}
		if (context_water_enabled && !city_overview) {
			vec2 water_uv=vec2((ll.x-context_water_bounds.x)/(context_water_bounds.z-context_water_bounds.x),(context_water_bounds.w-ll.y)/(context_water_bounds.w-context_water_bounds.y));
			if (all(greaterThanEqual(water_uv,vec2(0.0))) && all(lessThanEqual(water_uv,vec2(1.0)))) {
				vec2 metres=(context_water_bounds.zw-context_water_bounds.xy)*vec2(111195.0*cos(radians(ll.y)),111195.0);
				vec2 support=smoothstep(vec2(0.0),vec2(160.0)/metres,min(water_uv,vec2(1.0)-water_uv));
				float water=texture(context_water_mask,water_uv).r*support.x*support.y;
				// Acquired modern water is printed on the same terrain. Fade the
				// data-window cut; never outline it as a river bank or extend it.
				ground=mix(ground,vec3(0.25,0.43,0.48),water);
			}
		}
		if (city_overview) { ground=vec3(0.63,0.62,0.52); hillshade=mix(1.0,hillshade,0.12); inkshade=hillshade; }
		ALBEDO = mix(ground*hillshade,map_ink_tone.rgb*inkshade,map_ink_weight);
	}
	ALPHA = edge_weight*local_strength;
}
