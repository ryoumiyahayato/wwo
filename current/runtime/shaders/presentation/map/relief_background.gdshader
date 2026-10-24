shader_type canvas_item;
render_mode unshaded;
// Water backdrop only. Independent physical polygons own every land edge.
uniform vec4 ocean_tone = vec4(0.12,0.20,0.23,1.0);
void fragment() { COLOR = ocean_tone; }
