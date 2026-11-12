// Lichtstrahlen durch die Luft (aus der Schattenkarte) und unter Wasser durch die
// Wellen. Weich und unscharf, deshalb in halber Aufloesung: ein Viertel der Pixel.
// Schreibt in shaft_tex: rgb das Licht, a die Entfernung des Pixels, damit
// post/fog.wgsl beim Hochrechnen an Kanten (Baeume, Berge) nichts verschmiert.
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

// Unter Wasser: kraeftige Strahlen durch die Wellen (lineares Licht).
fn underwater_shafts(d: vec3<f32>, dist: f32, pixel: vec2<f32>) -> vec3<f32> {
    let day = daylight();
    if frame.has_shadow != 1u || day <= 0.0 {
        return vec3<f32>(0.0);
    }
    let l = light_dir();
    let eye_sky = frame.eye_light_smooth.y;
    let bright = mix(0.07, 1.0, day) * mix(0.30, 1.0, smoothstep(0.2, 0.8, eye_sky));
    let toward_sun = pow(max(dot(d, l), 0.0), 3.0);
    let reach = min(dist, 48.0);
    let steps = by_quality(6, 10, 16, 24);
    let jitter = bayer4(pixel) * 0.5 + 0.25;
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
    return vec3<f32>(0.20, 0.75, 0.70) * shafts * phase * reach * 0.04 * bright * (1.0 - frame.rain * 0.6);
}

// An Land: Licht, das sichtbar durch die Luft faellt (Bildschirmfarben, wird addiert).
fn air_shafts(d: vec3<f32>, dist: f32, pixel: vec2<f32>) -> vec3<f32> {
    let strength = sun_visible() + moon_visible() * (1.0 - sun_visible()) * 0.4;
    if quality < 1u || volumetric_light <= 0.0 || frame.has_shadow != 1u || strength <= 0.0 {
        return vec3<f32>(0.0);
    }
    let l = light_dir();
    let outside = smoothstep(0.15, 0.7, frame.eye_light_smooth.y);
    let reach = min(dist, frame.shadow_distance * 0.9);
    // Nah an der Kamera dichter abtasten: dort sieht man die Strahlen am besten.
    let steps = by_quality(8, 8, 14, 22);
    let jitter = bayer4(pixel);
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
    return tint * amount * mix(0.4, 1.0, outside);
}

fn post(input: PostInput) -> vec4<f32> {
    let sky_pixel = input.depth == 0.0;
    let p = view_position(input.uv, select(1e-4, input.depth, !sky_pixel));
    let d = normalize(p);
    let dist = select(length(p), SKY_DIST, sky_pixel);
    if frame.dimension != 0 {
        return vec4<f32>(0.0, 0.0, 0.0, dist);
    }
    if camera_underwater() {
        return vec4<f32>(underwater_shafts(d, select(dist, 128.0, sky_pixel), input.pixel), dist);
    }
    if frame.eye_in != 0u {
        return vec4<f32>(0.0, 0.0, 0.0, dist);
    }
    return vec4<f32>(air_shafts(d, dist, input.pixel), dist);
}
