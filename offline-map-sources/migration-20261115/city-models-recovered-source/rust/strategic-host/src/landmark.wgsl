struct Output {
    @builtin(position) position: vec4f,
    @location(0) normal: vec3f,
    @location(1) color: vec4f,
};

@vertex fn model_vertex(
    @location(0) position: vec3f,
    @location(1) normal: vec3f,
    @location(2) color: vec4f,
    @location(3) column_x: vec4f,
    @location(4) column_y: vec4f,
    @location(5) column_z: vec4f,
    @location(6) origin: vec4f,
) -> Output {
    let clip_from_model = mat4x4f(column_x, column_y, column_z, origin);
    return Output(clip_from_model * vec4f(position, 1.), normal, color);
}

@fragment fn model_fragment(input: Output) -> @location(0) vec4f {
    let sun = normalize(vec3f(-0.38, 0.84, 0.39));
    let light = 0.46 + 0.54 * max(0., dot(normalize(input.normal), sun));
    let linear = clamp(input.color.rgb * light, vec3f(0.), vec3f(1.));
    let srgb = select(linear * 12.92, 1.055 * pow(linear, vec3f(1. / 2.4)) - 0.055, linear > vec3f(0.0031308));
    return vec4f(srgb, input.color.a);
}
