shader_type canvas_item;
render_mode unshaded;

// A small padded quad; the original dated flag remains the only texture.
// TIME animates presentation independently of the formal GameClock.
void fragment() {
	float phase = UV.x * 7.5 - TIME * 2.1;
	float wave = sin(phase) * 0.065 * UV.x;
	vec2 sample_uv = vec2(UV.x, (UV.y - 0.1) / 0.8 - wave);
	float edge = max(fwidth(sample_uv.y), 0.001);
	float cloth = smoothstep(-edge, edge, sample_uv.y)
		* (1.0 - smoothstep(1.0 - edge, 1.0 + edge, sample_uv.y));
	vec4 flag = texture(TEXTURE, clamp(sample_uv, vec2(0.0), vec2(1.0)));
	float shade = 1.0 + cos(phase) * 0.055 * UV.x;
	COLOR = vec4(flag.rgb * shade, flag.a * cloth);
}
