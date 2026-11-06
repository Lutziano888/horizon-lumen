// Regen und Schnee: feiner und vom Licht abhaengig statt grell weiss.
fn weather(input: WeatherInput) -> vec4<f32> {
    let sky = input.light.y;
    let block = input.light.x;
    let day = daylight();
    let ambient = to_linear(atmosphere(vec3<f32>(0.0, 1.0, 0.0))) * mix(0.25, 1.0, day) + vec3<f32>(0.02);
    let torch = vec3<f32>(1.0, 0.62, 0.32) * pow(block, 3.0) * 1.5;
    let light = ambient * sky * sky + torch + vec3<f32>(0.01);
    let col = to_linear(input.color.rgb) * light * select(1.4, 2.2, input.snow);
    let alpha = input.color.a * select(0.45, 0.8, input.snow);
    return vec4<f32>(min(to_display(col), vec3<f32>(1.0)), alpha);
}
