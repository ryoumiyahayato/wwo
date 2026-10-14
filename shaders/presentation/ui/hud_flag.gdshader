shader_type canvas_item;
render_mode unshaded;

void vertex() {
	// Fixed hoist and gentle cloth displacement, driven by visual time only.
	float free_edge = UV.x * UV.x;
	VERTEX.y += sin(TIME * 0.85 + UV.x * 5.0 + UV.y * 0.6) * 1.15 * free_edge;
}

