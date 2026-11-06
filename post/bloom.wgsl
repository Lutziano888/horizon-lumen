// Weicher Bloom um helle Stellen (Sonne, Lava, Fackeln), auf zwei Ringen.
override bloom: f32 = 0.45;

fn bright(uv: vec2<f32>) -> vec3<f32> {
    let c = textureSampleLevel(previous, linear_sampler, uv, 0.0).rgb;
    let sky = select(1.0, 0.3, depth_at(uv) == 0.0);
    return c * smoothstep(0.72, 1.0, luminance(c)) * sky;
}

fn post(input: PostInput) -> vec4<f32> {
    if bloom <= 0.0 {
        return input.color;
    }
    let step = frame.resolution.y / 720.0 / frame.resolution;
    var sum = vec3<f32>(0.0);
    for (var i = 0; i < 16; i++) {
        let angle = f32(i) * 0.3926991 + select(0.0, 0.196, (i & 1) == 1);
        let radius = select(4.0, 10.0, (i & 1) == 1);
        sum += bright(input.uv + vec2<f32>(cos(angle), sin(angle)) * radius * step);
    }
    return vec4<f32>(input.color.rgb + sum * (bloom / 10.0), input.color.a);
}
