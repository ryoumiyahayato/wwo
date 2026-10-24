shader_type canvas_item;
render_mode unshaded;
uniform float motion = 0.012;
void fragment() {
	// One 36-second loop moves the whole painting without distorting objects.
	float phase = TIME*0.1745329252;
	float breath = 0.5-0.5*cos(phase);
	float scale = mix(0.978,0.950,breath);
	vec2 drift = vec2(sin(phase),sin(phase*2.0))*motion*vec2(0.80,0.38);
	COLOR = texture(TEXTURE,(UV-vec2(0.5))*scale+vec2(0.5)+drift);
}
