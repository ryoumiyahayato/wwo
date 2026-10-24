shader_type spatial;
// The existing front-hemisphere mesh uses the opposite winding from Godot's
// clockwise front faces. Keep its geometry; show the physical backdrop on it.
render_mode cull_disabled, unshaded;

uniform mat3 globe_basis = mat3(1.0);
varying vec3 globe_point;
uniform vec4 ocean_tone : source_color = vec4(0.12,0.20,0.23,1.0);
#include "res://shaders/presentation/map/ocean_globe.gdshaderinc"
void vertex() { globe_point = VERTEX; }

void fragment() {
	vec3 view_normal = normalize(globe_point);
	ALBEDO = chart_ocean(ocean_tone.rgb,view_normal,globe_basis);
}
