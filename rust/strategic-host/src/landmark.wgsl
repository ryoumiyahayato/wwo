struct Output {
    @builtin(position) position: vec4f,
    @location(0) normal: vec3f,
    @location(1) color: vec4f,
    @location(2) @interpolate(flat) lod_range:vec2f,
    @location(3) model_height: f32,
    @location(4) @interpolate(flat) waterline: f32,
};

@vertex fn model_vertex(
    @location(0) position: vec3f,
    @location(1) normal: vec3f,
    @location(2) color: vec4f,
    @location(3) column_x: vec4f,
    @location(4) column_y: vec4f,
    @location(5) column_z: vec4f,
    @location(6) origin: vec4f,
    @location(7) style:vec3f,
) -> Output {
    let clip_from_model = mat4x4f(column_x, column_y, column_z, origin);
    return Output(clip_from_model * vec4f(position, 1.), normal, color, style.xy, position.y, style.z);
}

@fragment fn model_fragment(input: Output) -> @location(0) vec4f {
    if input.waterline > 0.5 && input.model_height < 0.0 { discard; }
    if input.lod_range.x>0. || input.lod_range.y<1. {
        // Complementary coverage lets both opaque LODs share the depth buffer.
        let p=vec2u(input.position.xy)%4u;
        let bayer=array<u32,16>(0u,8u,2u,10u,12u,4u,14u,6u,3u,11u,1u,9u,15u,7u,13u,5u);
        let rank=(f32(bayer[p.y*4u+p.x])+.5)/16.;
        if rank<input.lod_range.x || rank>=input.lod_range.y {discard;}
    }
    let sun = normalize(vec3f(-0.38, 0.84, 0.39));
    let light = 0.46 + 0.54 * max(0., dot(normalize(input.normal), sun));
    let linear = clamp(input.color.rgb * light, vec3f(0.), vec3f(1.));
    let srgb = select(linear * 12.92, 1.055 * pow(linear, vec3f(1. / 2.4)) - 0.055, linear > vec3f(0.0031308));
    return vec4f(srgb, input.color.a);
}
