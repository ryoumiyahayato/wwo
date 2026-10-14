shader_type canvas_item;
render_mode unshaded;
void fragment() {
	float shade = mix(0.90, 0.18, smoothstep(0.0, 0.80, UV.x));
	COLOR = vec4(0.015, 0.018, 0.019, shade);
}
