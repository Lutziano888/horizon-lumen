// Weicher Bloom um helle Stellen (Sonne, Lava, Fackeln), auf zwei Ringen. Halbe
// Aufloesung, schreibt nur den Schein in glow_tex (post/grade.wgsl addiert).
override bloom: f32 = 0.45;

// Was hier strahlen darf. Material.wgsl merkt sich im Gelaende, wie stark ein Block
// selbst leuchtet (data = 1 + Leuchtkraft): so strahlen Fackeln, Lava und Glowstone,
// aber nicht heller Sand, Schnee oder Quarz, nur weil die Sonne darauf scheint.
fn bright(at: vec2<f32>) -> vec3<f32> {
    let uv = clamp(at, vec2<f32>(0.0), vec2<f32>(1.0));
    let c = textureSampleLevel(previous, linear_sampler, uv, 0.0).rgb;
    let lum = luminance(c);
    if depth_at(uv) == 0.0 {
        // Himmel: Sonne und sonnige Wolkenraender, sanft.
        return c * smoothstep(0.72, 1.0, lum) * 0.3;
    }
    let size = vec2<i32>(frame.resolution);
    let s = surface_at(clamp(vec2<i32>(uv * frame.resolution), vec2<i32>(0), size - 1));
    if s.present {
        // Im End (dunkel) staerker: Endstaebe und Chorus-Blueten gluehen.
        let boost = select(1.0, 1.8, frame.dimension == 1);
        return c * smoothstep(select(0.65, 0.4, frame.dimension == 1), 1.0, lum) * smoothstep(0.0, 0.5, s.data - 1.0) * boost;
    }
    // Wasser (Sonnenglanz), Glas, Mobs und Partikel: nur die ganz hellen Stellen. Im
    // End leuchten auch Enderman-Augen und lila Partikel.
    let start = select(0.85, 0.42, frame.dimension == 1);
    return c * smoothstep(start, start + 0.15, lum) * select(1.0, 1.4, frame.dimension == 1);
}

fn post(input: PostInput) -> vec4<f32> {
    if bloom <= 0.0 {
        return vec4<f32>(0.0);
    }
    let step = frame.resolution.y / 720.0 / frame.resolution;
    // Niedrig 8, Mittel 12, Hoch 16, Ultra 24 Abtastungen, abwechselnd innen und aussen.
    let taps = by_quality(8, 12, 16, 24);
    let turn = 6.2831853 / f32(taps);
    var sum = vec3<f32>(0.0);
    for (var i = 0; i < taps; i++) {
        let odd = (i & 1) == 1;
        let angle = f32(i) * turn + select(0.0, turn * 0.5, odd);
        let radius = select(4.0, 10.0, odd);
        sum += bright(input.uv + vec2<f32>(cos(angle), sin(angle)) * radius * step);
    }
    return vec4<f32>(sum * (bloom / 10.0) * (16.0 / f32(taps)), 1.0);
}
