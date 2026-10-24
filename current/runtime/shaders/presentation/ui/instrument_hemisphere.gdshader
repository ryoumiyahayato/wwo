shader_type canvas_item;
render_mode unshaded;
uniform sampler2D land_mask : filter_linear, repeat_enable;
uniform mat3 view_basis = mat3(1.0);
uniform vec2 instrument_center = vec2(0.0);
uniform float instrument_radius = 60.0;
varying vec2 instrument_pixel;

void vertex() {
	instrument_pixel = VERTEX;
}

void fragment() {
	vec2 xy = (instrument_pixel-instrument_center)/instrument_radius;
	float distance = length(xy);
	if (xy.y>0.0 || distance>0.985) { discard; }
	vec3 view = vec3(xy.x,-xy.y,sqrt(max(0.0,1.0-dot(xy,xy))));
	vec3 earth = normalize(transpose(view_basis)*view);
	float longitude = atan(earth.x,earth.z);
	float latitude = asin(clamp(earth.y,-1.0,1.0));
	vec2 geographic_uv = vec2(longitude/6.28318530718+0.5,clamp(0.5-latitude/3.14159265359,0.0009765625,0.9990234375));
	float land = texture(land_mask,geographic_uv).r;
	vec3 sea = vec3(0.065,0.155,0.165);
	vec3 ground = vec3(0.43,0.48,0.32);
	float light = 0.56+0.44*max(0.0,dot(view,normalize(vec3(-0.30,0.65,1.0))));
	vec3 color = mix(sea,ground,land)*light;
	color *= 1.0-0.24*smoothstep(0.65,0.985,distance);
	// Sparse geographic graticules follow the same earth coordinates as the mask.
	vec2 angle = vec2(longitude,latitude)/0.5235987756;
	vec2 edge = abs(fract(angle+0.5)-0.5);
	vec2 width = max(fwidth(angle)*0.65,vec2(0.00001));
	float grid = max(1.0-smoothstep(width.x,width.x*2.0,edge.x),1.0-smoothstep(width.y,width.y*2.0,edge.y));
	grid *= smoothstep(0.10,0.30,length(earth.xz));
	color = mix(color,vec3(0.63,0.70,0.59),grid*0.27);
	COLOR = vec4(color,1.0);
}
