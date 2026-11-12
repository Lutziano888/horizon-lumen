// Luft wie bei Photon: sehr duenner, blaeulicher Dunst, der erst in grosser
// Entfernung sichtbar wird, und Licht, das sichtbar durch die Luft faellt
// (Lichtstrahlen zwischen Baeumen, aus der Schattenkarte), morgens und
// abends staerker.
override haze: f32 = 0.5;

// Lichtstrahlen aus post/shafts.wgsl (halbe Aufloesung) hochrechnen: von den vier
// naechsten Werten zaehlen die, deren Entfernung zu diesem Pixel passt. So bleiben
// Kanten von Baeumen und Bergen scharf.
fn shafts_at(uv: vec2<f32>, dist: f32) -> vec3<f32> {
    let size = vec2<f32>(textureDimensions(shaft_tex));
    let hp = uv * size - 0.5;
    let base = floor(hp);
    let f = hp - base;
    let tolerance = 0.06 * min(dist, 4000.0) + 0.3;
    var sum = vec3<f32>(0.0);
    var weight = 0.0;
    for (var i = 0; i < 4; i++) {
        let o = vec2<f32>(f32(i % 2), f32(i / 2));
        let texel = clamp(vec2<i32>(base + o), vec2<i32>(0), vec2<i32>(size) - 1);
        let s = textureLoad(shaft_tex, texel, 0);
        let bilinear = mix(1.0 - f.x, f.x, o.x) * mix(1.0 - f.y, f.y, o.y);
        let same = 1.0 / (1.0 + abs(s.a - dist) / tolerance * 4.0);
        let w = bilinear * same + 1e-4;
        sum += s.rgb * w;
        weight += w;
    }
    return sum / weight;
}

// Wolken aus post/clouds.wgsl darueberlegen: auf dem Himmel und auf Gelaende, das
// hinter dem Anfang der Wolkenschicht liegt.
fn add_clouds(col: vec3<f32>, uv: vec2<f32>, d: vec3<f32>, dist: f32, sky_pixel: bool) -> vec3<f32> {
    if soft_clouds <= 0.0 {
        return col;
    }
    var show = 1.0;
    if !sky_pixel {
        let cy = frame.camera_position.y;
        if abs(d.y) < 0.002 {
            return col;
        }
        let t0 = (C_BOTTOM - cy) / d.y;
        let t1 = (C_TOP - cy) / d.y;
        let t_near = max(min(t0, t1), 0.0);
        if max(t0, t1) <= 0.0 {
            return col;
        }
        show = smoothstep(t_near, t_near + 40.0, dist);
        if show <= 0.0 {
            return col;
        }
    }
    let c = textureSampleLevel(cloud_tex, linear_sampler, uv, 0.0);
    return mix(col, col * c.a + c.rgb, show);
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

    // Kraeftige Lichtstrahlen durch die Wellen (post/shafts.wgsl).
    let key = select(length(view_position(input.uv, max(input.depth, 1e-6))), SKY_DIST, input.depth == 0.0);
    col += shafts_at(input.uv, key);

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

// Schwebende Funken: im Nether gluehende Glut, die aufsteigt und flackert, im End
// violette Lichtpunkte, die langsam treiben.
fn motes(d: vec3<f32>, max_dist: f32, rise: f32, rarity: f32) -> f32 {
    var sum = 0.0;
    let cam = frame.camera_position;
    for (var k = 0; k < 5; k++) {
        let r = 2.0 + f32(k) * 3.5;
        if r > max_dist {
            break;
        }
        let pw = cam + d * r - vec3<f32>(frame.time * 0.15, -frame.time * rise, frame.time * 0.05);
        let cell = floor(pw * 0.5);
        let ci = vec3<i32>(cell) + vec3<i32>(0, 0, k * 31);
        let spot = (cell + vec3<f32>(hash3(ci), hash3(ci + vec3<i32>(7, 0, 0)), hash3(ci + vec3<i32>(0, 9, 0)))) / 0.5;
        let near = length(pw - spot);
        let flicker = 0.6 + 0.4 * sin(frame.time * 6.0 + hash3(ci + vec3<i32>(2, 3, 4)) * 30.0);
        let size = 0.03 + 0.03 * hash3(ci + vec3<i32>(0, 0, 11));
        sum += smoothstep(size, 0.0, near) * step(rarity, hash3(ci + vec3<i32>(3, 5, 1))) * flicker / (1.0 + r * 0.15);
    }
    return sum;
}

// Nether: roter Dunst, der durch die Luft treibt (drei Proben entlang des Blicks),
// und Glut. End: der Weltraum als Himmel, violetter Dunst, der sich unten ueber der
// Leere sammelt, das Gelaende blendet in der Ferne in den Weltraum, dazu Lichtpunkte.
fn other_air(input: PostInput, d: vec3<f32>, dist: f32) -> vec3<f32> {
    var col = input.color.rgb;
    if frame.eye_in != 0u || frame.blindness > 0.0 || frame.darkness > 0.0 {
        return col;
    }
    let nether = frame.dimension == -1;
    let sky_pixel = input.depth == 0.0;
    if !nether && sky_pixel {
        return end_space(d);
    }
    let reach = min(dist, 64.0);
    let cam = frame.camera_position;
    var thick = 0.0;
    var low = 0.0;
    for (var i = 0; i < 3; i++) {
        let pw = cam + d * (reach * (f32(i) + 0.5) / 3.0);
        thick += vnoise(pw * 0.045 + vec3<f32>(frame.time * 0.03, frame.time * 0.05, 0.0)) / 3.0;
        low += exp(-max(pw.y - 45.0, 0.0) / 18.0) / 3.0;
    }
    if nether {
        let density = 0.009 * haze * 2.0 * mix(0.4, 1.6, thick);
        let amount = (1.0 - exp(-min(dist, 400.0) * density)) * 0.75;
        col = mix(col, to_display(to_linear(frame.fog_color) * 1.8), amount);
        if quality >= 1u {
            col += vec3<f32>(1.0, 0.42, 0.10) * motes(d, dist, 0.45, 0.7) * 0.9;
        }
        return col;
    }
    // End: in der Ferne in den Weltraum uebergehen.
    let flat_dist = max(length(d.xz * dist), abs(d.y * dist));
    let end = max(frame.fog_end, 16.0);
    let edge = smoothstep(end * 0.6, end * 0.98, flat_dist);
    let density = (0.003 + low * 0.010) * haze * 2.0 * mix(0.5, 1.5, thick);
    let amount = (1.0 - exp(-min(dist, 400.0) * density)) * 0.8;
    // Dunst in der Farbe des Horizonts, ueber der Leere dichter und rosa.
    let mist = mix(vec3<f32>(0.50, 0.34, 0.70), vec3<f32>(0.70, 0.42, 0.78), low);
    col = mix(col, mist, amount);
    col = mix(col, end_space(d), edge);
    if quality >= 1u {
        col += vec3<f32>(0.75, 0.55, 1.0) * motes(d, dist, 0.08, 0.8) * 0.8;
    }
    return col;
}

fn post(input: PostInput) -> vec4<f32> {
    if frame.dimension == 0 && camera_underwater() {
        return underwater(input);
    }
    let sky_pixel = input.depth == 0.0;
    let p = view_position(input.uv, select(1e-4, input.depth, !sky_pixel));
    let dist = select(length(p), 1e9, sky_pixel);
    let d = normalize(p);
    if frame.dimension == -1 || frame.dimension == 1 {
        return vec4<f32>(other_air(input, d, dist), input.color.a);
    }
    if frame.dimension != 0 {
        return input.color;
    }
    var col = add_clouds(input.color.rgb, input.uv, d, dist, sky_pixel);
    if frame.eye_in != 0u {
        return vec4<f32>(col, input.color.a);
    }
    col = calm_entities(input, col);
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

    // Volumetrisches Licht (post/shafts.wgsl, halbe Aufloesung).
    col += shafts_at(input.uv, select(dist, SKY_DIST, sky_pixel));
    return vec4<f32>(col, input.color.a);
}
