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

// Weiche Variante der Kaustiken fuer die Lichtstrahlen: breite Baender statt
// scharfer Linien, damit die Strahlen nicht koernig werden.
fn soft_caustics(world: vec3<f32>) -> f32 {
    let t = frame.time * 0.5;
    let p = world.xz;
    let a = sin(p.x + sin(p.y * 0.7 + t) * 1.3 + t * 0.6);
    let b = sin(p.y * 1.1 + sin(p.x * 0.8 - t * 0.9) * 1.3 - t * 0.5);
    return pow(clamp(1.0 - abs(a + b) * 0.5, 0.0, 1.0), 2.0);
}

// Schwebeteilchen unter Wasser: kleine helle Punkte, fest in der Welt.
fn particles(d: vec3<f32>, max_dist: f32) -> f32 {
    var sum = 0.0;
    let cam = frame.camera_position;
    for (var k = 0; k < 4; k++) {
        let r = 1.5 + f32(k) * 2.2;
        if r > max_dist {
            break;
        }
        let pw = cam + d * r + vec3<f32>(0.0, frame.time * 0.08, 0.0);
        let cell = floor(pw * 1.2);
        let ci = vec3<i32>(cell);
        let spot = (cell + vec3<f32>(hash3(ci), hash3(ci + vec3<i32>(7, 0, 0)), hash3(ci + vec3<i32>(0, 9, 0)))) / 1.2;
        let near = length(pw - spot);
        let size = 0.035 + 0.02 * hash3(ci + vec3<i32>(0, 0, 11));
        sum += smoothstep(size, size * 0.3, near) * step(0.55, hash3(ci + vec3<i32>(3, 5, 1))) / (1.0 + r * 0.25);
    }
    return sum;
}

// Unter Wasser: leuchtend tuerkises, klares Wasser mit kraeftigen Lichtstrahlen durch
// die Wellen, Schwebeteilchen, Wabern, Farbsaum am Rand und tiefer werdendem Blau.
fn underwater(input: PostInput) -> vec4<f32> {
    let t = frame.time;
    let wobble = vec2<f32>(sin(input.uv.y * 30.0 + t * 1.9) + sin(input.uv.y * 71.0 - t * 2.7) * 0.4,
                           cos(input.uv.x * 25.0 + t * 1.5) + cos(input.uv.x * 63.0 + t * 2.3) * 0.4) * 0.0016;
    let uv = clamp(input.uv + wobble, vec2<f32>(0.0), vec2<f32>(1.0));
    // Leichter Farbsaum zum Rand hin (wie durch eine Taucherbrille).
    let edge = (input.uv - 0.5) * 0.0025;
    var col = vec3<f32>(
        textureSampleLevel(previous, linear_sampler, clamp(uv + edge, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).r,
        textureSampleLevel(previous, linear_sampler, uv, 0.0).g,
        textureSampleLevel(previous, linear_sampler, clamp(uv - edge, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).b);
    col = to_linear(col);
    let depth = depth_at(uv);
    let sky_pixel = depth == 0.0;
    let p = view_position(uv, select(1e-4, depth, !sky_pixel));
    let dist = select(length(p), 128.0, sky_pixel);
    let d = normalize(p);
    let l = light_dir();

    let day = daylight();
    let eye_sky = frame.eye_light_smooth.y;
    let bright = mix(0.07, 1.0, day) * mix(0.30, 1.0, smoothstep(0.2, 0.8, eye_sky));
    let depth_below = max(frame.water_plane - frame.camera_position.y, 0.0);
    let deep = exp(-depth_below * 0.03);
    let base_water = mix(vec3<f32>(0.004, 0.045, 0.120), vec3<f32>(0.010, 0.170, 0.200), deep);
    let toward_sun = pow(max(dot(d, l), 0.0), 3.0);
    let vertical = mix(0.45, 1.5, smoothstep(-0.6, 0.7, d.y));
    let water = base_water * bright * vertical * (1.0 + toward_sun * 1.8 * day);

    col *= 1.7;
    let absorb = exp(-vec3<f32>(0.075, 0.020, 0.014) * dist);
    let fog = 1.0 - exp(-max(dist - 3.0, 0.0) * 0.016);
    col = mix(col * absorb, water, fog);

    // Kraeftige Lichtstrahlen durch die Wellen, aus der Schattenkarte.
    if frame.has_shadow == 1u && day > 0.0 {
        let reach = min(dist, 48.0);
        let steps = by_quality(6, 10, 16, 24);
        let jitter = pixel_noise(input.pixel) * 0.5 + 0.25;
        var shafts = 0.0;
        for (var i = 0; i < steps; i++) {
            let u = (f32(i) + jitter) / f32(steps);
            let pv = d * (reach * u * u);
            let sp = shadow_position(pv);
            let lit = textureSampleCompareLevel(shadow_map, shadow_sampler, sp.xy, sp.z);
            let wp = pv + frame.camera_position;
            let up = max(frame.water_plane - wp.y, 0.0);
            let at_surface = wp + l * (up / max(l.y, 0.2));
            let c = soft_caustics(at_surface * 0.35);
            shafts += lit * c * exp(-up * 0.04) * 2.0 * u / f32(steps);
        }
        let phase = 0.5 + toward_sun * 3.0 + pow(max(d.y, 0.0), 2.0) * 1.5;
        col += vec3<f32>(0.20, 0.75, 0.70) * shafts * phase * reach * 0.04 * bright * (1.0 - frame.rain * 0.6);
    }

    // Schwebeteilchen, von der Sonne angeleuchtet (nicht auf Niedrig).
    if quality >= 1u {
        col += vec3<f32>(0.5, 0.8, 0.8) * particles(d, dist) * base_water * 6.0 * bright;
    }

    // Unter Wasser kraeftiger und etwas kontrastreicher.
    let lum = luminance(col);
    col = max(vec3<f32>(lum) + (col - vec3<f32>(lum)) * 1.25, vec3<f32>(0.0));
    let v = length(input.uv - 0.5);
    col *= 1.0 - smoothstep(0.40, 0.9, v) * 0.35;
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
    // Auf Niedrig aus, sonst 8, 12 oder 20 Schritte.
    if quality >= 1u && volumetric_light > 0.0 && frame.has_shadow == 1u && strength > 0.0 {
        let l = light_dir();
        let reach = min(dist, frame.shadow_distance * 0.9);
        // Nah an der Kamera dichter abtasten: dort sieht man die Strahlen am besten.
        let steps = by_quality(8, 8, 12, 20);
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
