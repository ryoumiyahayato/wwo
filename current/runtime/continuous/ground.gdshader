shader_type spatial;
render_mode diffuse_burley, specular_disabled;
uniform sampler2D region_color : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D region_normal : filter_linear_mipmap, repeat_disable;
uniform sampler2D grass_detail : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D land_control : filter_linear_mipmap, repeat_disable;
uniform sampler2D detail_coverage : filter_nearest, repeat_disable;
uniform bool native_terrain = false;
uniform bool far_mesh = false;
varying vec3 world_point;
void vertex() { world_point = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz; }
void fragment() {
    vec2 local_uv=(world_point.xz+vec2(2500.0))/5000.0;
    if(native_terrain && far_mesh && texture(detail_coverage,local_uv).r>.5) { discard; }
    vec2 uv=(world_point.xz+vec2(22500.0))/50000.0;
    vec3 base=texture(region_color,uv).rgb;
    vec2 outside=max(vec2(0.0),max(-uv,uv-vec2(1.0)))*50000.0;
    base=mix(base,vec3(.30,.38,.25),smoothstep(0.0,8000.0,length(outside)));
    vec3 world_normal=normalize(texture(region_normal,uv).rgb*2.0-1.0);
    world_normal=normalize(mix(world_normal,vec3(0.0,1.0,0.0),smoothstep(0.0,8000.0,length(outside))));
    NORMAL=normalize((VIEW_MATRIX*vec4(world_normal,0.0)).xyz);
    float distance_to_eye=length(CAMERA_POSITION_WORLD-world_point);
    vec3 grain=texture(grass_detail,world_point.xz*.3).rgb;
    base*=mix(vec3(.91)+grain*.18,vec3(1.0),smoothstep(60.0,700.0,distance_to_eye));
    if(native_terrain) {
        vec3 control=texture(land_control,local_uv).rgb;
        base=mix(base,base*vec3(1.08,1.02,.85),control.g*.45);
        base=mix(base,vec3(.36,.30,.20),control.r*.5);
        float crater=clamp((COLOR.r-COLOR.g)*4.8,0.0,1.0);
        base=mix(base,vec3(.24,.175,.115),crater);
    }
    ALBEDO=base;
    ROUGHNESS=1.0;
}
