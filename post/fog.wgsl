// Luft wie bei Photon: sehr duenner, blaeulicher Dunst, der erst in grosser
// Entfernung sichtbar wird, und Licht, das sichtbar durch die Luft faellt
// (Lichtstrahlen zwischen Baeumen, aus der Schattenkarte), morgens und
// abends staerker.
override haze: f32 = 0.5;
override volumetric_light: f32 = 0.5;

// 4x4-Bayer-Muster: ruhiger Versatz der Abtastpunkte ohne flimmerndes Rauschen.
fn bayer4(pixel: vec2<f32>) -> f32 {
    let p = vec2<u32>(pixel) % vec2<u32>(4u);
    var m = array<f32, 16>(0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
    return (m[p.y * 4u + p.x] + 0.5) / 16.0;
}

// Unter Wasser: klares, blaugruenes Wasser mit weichem Nebel, leichtem Wabern,
// Lichtstrahlen von oben und gedaempften Farben in der Tiefe.
fn underwater(input: PostInput) -> vec4<f32> {
    let t = frame.time;
    let wobble = vec2<f32>(sin(input.uv.y * 38.0 + t * 2.1), cos(input.uv.x * 31.0 + t * 1.7)) * 0.0018;
    let uv = clamp(input.uv + wobble, vec2<f32>(0.0), vec2<f32>(1.0));
    var col = to_linear(textureSampleLevel(previous, linear_sampler, uv, 0.0).rgb);
    let depth = depth_at(uv);
    let sky_pixel = depth == 0.0;
    let p = view_position(uv, select(1e-4, depth, !sky_pixel));
    let dist = select(length(p), 96.0, sky_pixel);
    let d = normalize(p);

    let day = daylight();
    let eye_sky = frame.eye_light_smooth.y;
    // Wasserfarbe: helles Tuerkis nah an der Oberflaeche, tiefer und nachts dunkler.
    let bright = mix(0.06, 1.0, day) * mix(0.35, 1.0, smoothstep(0.2, 0.8, eye_sky));
    let water = vec3<f32>(0.010, 0.115, 0.165) * bright;
    // Unter Wasser kommt weniger Licht an: etwas aufhellen, damit man etwas sieht.
    col *= 1.6;
    // Rot verschwindet zuerst, dann Gruen: je weiter, desto blauer.
    let absorb = exp(-vec3<f32>(0.07, 0.022, 0.016) * dist);
    let fog = 1.0 - exp(-max(dist - 4.0, 0.0) * 0.016);
    col = col * absorb;
    col = mix(col, water, fog);
    // Licht von oben, das durchs Wasser faellt.
    let up = smoothstep(-0.2, 1.0, d.y);
    let shafts = 0.5 + 0.5 * sin(d.x * 24.0 + t * 0.6) * sin(d.z * 19.0 - t * 0.5);
    col += water * up * up * shafts * 0.5;
    // Etwas dunkler am Rand.
    let v = length(input.uv - 0.5);
    col *= 1.0 - smoothstep(0.4, 0.85, v) * 0.25;
    // Etwas heller und klarer, wie bei Photon.
    col *= 1.15;
    return vec4<f32>(to_display(col), input.color.a);
}

// Mobs, Tiere und Objekte bekommen Vanillas Licht; nachts ist das viel heller als
// unser Gelaende. Hier passend abdunkeln (nur Pixel, die kein Gelaende sind).
fn calm_entities(input: PostInput, col: vec3<f32>) -> vec3<f32> {
    if input.depth == 0.0 {
        return col;
    }
    let s = surface_at(vec2<i32>(input.pixel));
    if s.present || s.data > 0.5 {
        return col;
    }
    let night = 1.0 - daylight();
    let outside = smoothstep(0.15, 0.7, frame.eye_light_smooth.y);
    let k = mix(1.0, 0.38, night * outside);
    let rain = mix(1.0, 0.8, frame.rain);
    return to_display(to_linear(col) * k * rain);
}

override ambient_blue_fog: f32 = 0.45;

fn post(input: PostInput) -> vec4<f32> {
    if frame.dimension == 0 && camera_underwater() {
        return underwater(input);
    }
    if frame.dimension != 0 || frame.eye_in != 0u {
        return input.color;
    }
    let sky_pixel = input.depth == 0.0;
    let p = view_position(input.uv, select(1e-4, input.depth, !sky_pixel));
    let dist = select(length(p), 1e9, sky_pixel);
    let d = normalize(p);
    var col = calm_entities(input, input.color.rgb);
    let outside = smoothstep(0.15, 0.7, frame.eye_light_smooth.y);

    // Luftperspektive auf dem Gelaende.
    if haze > 0.0 && !sky_pixel {
        let end = max(frame.fog_end, 16.0);
        let flat_dist = max(length(p.xz), abs(p.y));
        // Dort blendet das Material schon selbst in den Himmel.
        let border = smoothstep(end * 0.86, end * 1.0, flat_dist);
        // Ferne wird blaeulich und heller, das gibt Tiefe (wie bei Photon).
        let world_y = p.y + frame.camera_position.y;
        var air = atmosphere(vec3<f32>(d.x, max(d.y, 0.0) * 0.35 + 0.02, d.z));
        air = mix(air, air * vec3<f32>(0.92, 0.97, 1.05), 0.5);
        let low_air = exp(-max(world_y - 70.0, 0.0) / 140.0);
        var amount = 1.0 - exp(-max(dist - 20.0, 0.0) * 0.0042 * haze * mix(0.6, 1.0, low_air));
        amount = min(amount, 0.8) * (1.0 - border) * outside * (1.0 + frame.rain * 0.5);
        col = mix(col, air, clamp(amount, 0.0, 0.9));
    }

    // Volumetrisches Licht durch die Schattenkarte.
    let strength = sun_visible() + moon_visible() * (1.0 - sun_visible()) * 0.4;
    if volumetric_light > 0.0 && frame.has_shadow == 1u && strength > 0.0 {
        let l = light_dir();
        let reach = min(dist, frame.shadow_distance * 0.9);
        // Nah an der Kamera dichter abtasten: dort sieht man die Strahlen am besten.
        let steps = 12;
        let jitter = bayer4(input.pixel);
        var lit = 0.0;
        for (var i = 0; i < steps; i++) {
            let u = (f32(i) + jitter) / f32(steps);
            let sp = shadow_position(d * (reach * u * u));
            lit += textureSampleCompareLevel(shadow_map, shadow_sampler, sp.xy, sp.z) * 2.0 * u * reach / f32(steps);
        }
        let mu = dot(d, l);
        let phase = hg_phase(mu, 0.70) * 12.566 * 0.8 + 0.2;
        let density = 0.0035 * (1.0 + 2.5 * sun_low()) * (1.0 + frame.rain * 1.5) * volumetric_light;
        let amount = (1.0 - exp(-lit * density)) * phase * 0.07 * strength;
        let tint = mix(vec3<f32>(0.35, 0.45, 0.7), sun_tint() * vec3<f32>(1.0, 0.9, 0.75), sun_visible());
        col += tint * amount * mix(0.4, 1.0, outside);
    }
    return vec4<f32>(col, input.color.a);
}
