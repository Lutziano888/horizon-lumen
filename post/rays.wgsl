// Lichtstrahlen (God Rays): radiale Unschaerfe des sichtbaren Himmels zur Sonne hin.
override rays: f32 = 0.3;

fn sun_uv() -> vec4<f32> {
    let p = frame.projection * frame.view * vec4<f32>(frame.sun_direction * 1000.0, 1.0);
    let ndc = p.xy / max(p.w, 1e-4);
    return vec4<f32>(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5, p.w, 0.0);
}

fn post(input: PostInput) -> vec4<f32> {
    let s = sun_uv();
    let up = daylight() * (1.0 - frame.rain);
    if rays <= 0.0 || s.z <= 0.0 || up <= 0.0 || frame.eye_in != 0u || camera_underwater() {
        return input.color;
    }
    let aspect = frame.resolution.x / frame.resolution.y;
    let to_sun = s.xy - input.uv;
    let dist = length(to_sun * vec2<f32>(aspect, 1.0));
    let steps = by_quality(10, 14, 20, 28);
    let delta = to_sun / f32(steps) * 0.85;
    var uv = input.uv;
    var sum = 0.0;
    for (var i = 0; i < steps; i++) {
        uv += delta;
        let open = select(0.0, 1.0, depth_at(clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0))) == 0.0);
        sum += open;
    }
    sum /= f32(steps);
    let falloff = exp(-dist * 2.2);
    let low = mix(0.6, 1.4, 1.0 - smoothstep(0.0, 0.5, frame.sun_direction.y));
    let shaft = sun_tint() * sum * falloff * rays * 0.35 * up * low;
    return vec4<f32>(input.color.rgb + shaft, input.color.a);
}
