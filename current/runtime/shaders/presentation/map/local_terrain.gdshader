shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_prepass_alpha;

uniform vec4 map_ink_tone : source_color = vec4(0.42,0.50,0.46,1.0);
uniform float map_ink_weight = 0.0;
uniform float local_strength = 1.0;
uniform float cartographic_relief_weight = 0.84;
uniform mat3 normal_to_geographic = mat3(1.0);
uniform bool woodland_enabled = false;
uniform bool local_palette_enabled = false;
uniform vec4 ground_low_tone : source_color = vec4(0.41,0.45,0.37,1.0);
uniform vec4 ground_high_tone : source_color = vec4(0.60,0.57,0.50,1.0);
uniform sampler2D woodland_mask : filter_linear, repeat_disable;
uniform vec4 survey_bounds = vec4(0.0);
varying vec3 geographic_normal;
varying float edge_weight;
varying vec3 cover_colour;
varying float cover_kind;
#include "res://shaders/presentation/map/terrain_palette.gdshaderinc"
#include "res://shaders/presentation/map/france_surface.gdshaderinc"

void vertex() {
	// Native DEM normals, independent of camera movement. A fill direction
	// retains readable valleys without adding any vertical exaggeration.
	geographic_normal = normal_to_geographic*NORMAL;
	edge_weight = COLOR.a;
	cover_colour = COLOR.rgb;
	cover_kind = UV2.y;
}

void fragment() {
	if (cover_kind < -0.5) {
		// Acquired water retains its hydrographic ink, not ground relief.
		ALBEDO = cover_colour;
	} else {
		vec3 n = normalize(geographic_normal);
		// Same north-facing two-light convention as the ETOPO chart. Actual
		// normals only: no source-window contrast stretch or second valley shadow.
		float key = dot(n,vec3(-0.5,0.70710678,-0.5));
		float fill = dot(n,vec3(0.5,0.70710678,-0.5));
		float directional = (0.45*key+0.55*fill-0.70710678)*1.35;
		// Clamp after interpolation: a clipped vertex brightness must not flatten
		// an entire survey triangle. The fill retains readable shaded slopes.
		float hillshade = clamp(1.0+directional*1.65*cartographic_relief_weight,0.78,1.20);
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
		if (woodland_enabled) {
			float coverage = texture(woodland_mask,UV).r;
			ground = mix(ground,vec3(0.34,0.41,0.33),coverage*0.44);
		}
		// Same geographic material as REGION; preserve the actual native mesh.
		vec2 ll = vec2(mix(survey_bounds.x,survey_bounds.z,UV.x),mix(survey_bounds.w,survey_bounds.y,UV.y));
		float regional_coverage;
		vec4 regional_surface = surface_sample(ll,regional_coverage);
		float inkshade = hillshade;
		// Only colour and illumination rejoin the reference chart at the rim.
		// No source height, normal or water edge is flattened or extended.
		if (regional_coverage>0.0) {
			ground = mix(ground,regional_surface.rgb,regional_coverage);
			float regional_form = mix(1.0,regional_surface.a,clamp(cartographic_relief_weight/0.92,0.0,1.0));
			inkshade = mix(hillshade,mix(regional_form,hillshade,smoothstep(0.0,0.85,edge_weight)),regional_coverage);
			hillshade = mix(hillshade,mix(1.0,hillshade,smoothstep(0.0,0.85,edge_weight)),regional_coverage);
		}
		ALBEDO = mix(ground*hillshade,map_ink_tone.rgb*inkshade,map_ink_weight);
	}
	ALPHA = edge_weight*local_strength;
}
