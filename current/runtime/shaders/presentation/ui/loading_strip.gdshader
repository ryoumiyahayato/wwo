shader_type canvas_item;
render_mode unshaded;
void fragment() {
	float sweep = fract(TIME*0.24)*1.45-0.25;
	float light = smoothstep(sweep-0.20,sweep,UV.x)*(1.0-smoothstep(sweep,sweep+0.20,UV.x));
	COLOR = vec4(mix(vec3(0.21,0.24,0.21),vec3(0.72,0.61,0.38),light),0.82);
}
