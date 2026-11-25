struct Output {
    @builtin(position) position: vec4f,
    @location(0) normal: vec3f,
    @location(1) color: vec4f,
    @location(2) @interpolate(flat) lod_range:vec2f,
    @location(3) model_height: f32,
    @location(4) @interpolate(flat) waterline: f32,
    @location(5) local_metres: vec3f,
    @location(6) @interpolate(flat) city_material: f32,
};

@group(0) @binding(0) var materials: texture_2d_array<f32>;
@group(0) @binding(1) var material_sampler: sampler;

@vertex fn model_vertex(
    @location(0) position: vec3f,
    @location(1) normal: vec3f,
    @location(2) color: vec4f,
    @location(3) column_x: vec4f,
    @location(4) column_y: vec4f,
    @location(5) column_z: vec4f,
    @location(6) origin: vec4f,
    @location(7) style:vec4f,
    @location(8) model_scale:vec3f,
) -> Output {
    let clip_from_model = mat4x4f(column_x, column_y, column_z, origin);
    return Output(clip_from_model * vec4f(position, 1.), normal, color, style.xy, position.y, style.z,
                  position*model_scale, style.w);
}

@fragment fn model_fragment(input: Output) -> @location(0) vec4f {
    let metre_dx=dpdx(input.local_metres);
    let metre_dy=dpdy(input.local_metres);
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
    var linear = clamp(input.color.rgb * light, vec3f(0.), vec3f(1.));
    if input.city_material>0.5 {
        let axis=abs(input.normal);
        let roof=axis.y>.37;
        let side=axis.x>axis.z;
        let wall=vec2f(select(input.local_metres.x,input.local_metres.z,side),input.local_metres.y);
        let wall_dx=vec2f(select(metre_dx.x,metre_dx.z,side),metre_dx.y);
        let wall_dy=vec2f(select(metre_dy.x,metre_dy.z,side),metre_dy.y);
        let uv=select(wall,input.local_metres.xz,roof)/4.;
        let dx=select(wall_dx,metre_dx.xz,roof)/4.;
        let dy=select(wall_dy,metre_dy.xz,roof)/4.;
        let art=textureSampleGrad(materials,material_sampler,uv,select(11,10,roof),dx,dy).rgb;
        let material=pow(art,vec3f(2.2));
        let value=dot(input.color.rgb,vec3f(.33,.50,.17));
        let tint=mix(vec3f(value),input.color.rgb,.17);
        linear=mix(material,tint,.28)*light;
    }
    let srgb = select(linear * 12.92, 1.055 * pow(linear, vec3f(1. / 2.4)) - 0.055, linear > vec3f(0.0031308));
    return vec4f(srgb, input.color.a);
}
