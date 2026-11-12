// Physikalisch inspirierter Himmel (atmosphere() in common.wgsl) mit runder
// Sonne statt Vanillas eckiger, eigenen funkelnden Sternen mit Milchstrasse
// und einem Regenbogen nach dem Regen. Der Mond bleibt von Vanilla, die Wolken
// zeichnet der Wolken-Durchgang. Im End ein leuchtender Nebel.

// Dreht eine Richtung so, dass Sterne fest am Himmel stehen und mit Sonne und Mond
// ueber den Himmel wandern.
fn celestial(d: vec3<f32>) -> vec3<f32> {
    let s = frame.sun_direction;
    let a = atan2(s.y, s.x);
    let c = cos(a);
    let sn = sin(a);
    return vec3<f32>(d.x * c + d.y * sn, -d.x * sn + d.y * c, d.z);
}

// Sterne: einer pro Zelle (wenn ueberhaupt), mit eigener Groesse, Farbe und Funkeln.
fn stars(d: vec3<f32>, crowd: f32) -> vec3<f32> {
    var col = vec3<f32>(0.0);
    for (var layer = 0; layer < 2; layer++) {
        let scale = select(140.0, 200.0, layer == 1);
        let p = d * scale;
        let cell = floor(p);
        let ci = vec3<i32>(cell) + vec3<i32>(layer * 977, 0, 0);
        let pick = hash3(ci);
        // Im Band der Milchstrasse stehen mehr Sterne.
        let rare = select(0.972, 0.985, layer == 1) - crowd * 0.03;
        if pick > rare {
            let spot = cell + vec3<f32>(hash3(ci + vec3<i32>(1, 7, 3)), hash3(ci + vec3<i32>(5, 2, 9)), hash3(ci + vec3<i32>(8, 4, 1))) * 0.4 + 0.3;
            let dist = length(p - spot);
            // Etwa 0,08 bis 0,15 Grad: ein bis zwei Pixel, damit nichts flimmert.
            let size = mix(0.0014, 0.0026, hash3(ci + vec3<i32>(2, 2, 2))) * scale;
            let shine = smoothstep(size, 0.0, dist);
            let bright = pow((pick - rare) / (1.0 - rare), 1.5) * select(1.0, 0.6, layer == 1);
            let twinkle = 0.7 + 0.3 * sin(frame.time * (2.0 + 3.0 * hash3(ci + vec3<i32>(4, 1, 6))) + pick * 40.0);
            let temp = hash3(ci + vec3<i32>(9, 9, 9));
            let tint = mix(vec3<f32>(0.75, 0.85, 1.0), vec3<f32>(1.0, 0.85, 0.65), temp);
            col += tint * shine * bright * twinkle * 2.2;
        }
    }
    return col;
}

// Milchstrasse: ein schwaches, wolkiges Band quer ueber den Himmel.
fn milky_band(d: vec3<f32>) -> f32 {
    let off = dot(d, normalize(vec3<f32>(0.2, 0.25, 0.95)));
    return exp(-off * off * 18.0);
}

fn milky_way(d: vec3<f32>, band: f32) -> vec3<f32> {
    if band < 0.02 {
        return vec3<f32>(0.0);
    }
    let n = vnoise(d * 6.0) * 0.55 + vnoise(d * 15.0) * 0.3 + vnoise(d * 38.0) * 0.15;
    let dust = smoothstep(0.35, 0.75, vnoise(d * 9.0 + vec3<f32>(3.0, 0.0, 0.0)));
    let glow = band * smoothstep(0.3, 0.8, n) * (1.0 - dust * 0.6 * band);
    return mix(vec3<f32>(0.35, 0.4, 0.6), vec3<f32>(0.55, 0.45, 0.5), n) * glow * 0.16;
}

// Regenbogen um den Punkt gegenueber der Sonne, nach dem Regen.
fn rainbow(d: vec3<f32>) -> vec3<f32> {
    let after = clamp((frame.wetness - frame.rain) * 3.0, 0.0, 1.0) * (1.0 - frame.rain);
    let sun_up = smoothstep(0.02, 0.12, frame.sun_direction.y) * (1.0 - smoothstep(0.55, 0.75, frame.sun_direction.y));
    let strength = after * sun_up;
    if strength <= 0.0 || d.y < 0.0 {
        return vec3<f32>(0.0);
    }
    let angle = degrees(acos(clamp(dot(d, -frame.sun_direction), -1.0, 1.0)));
    // Innen violett (40,5 Grad), aussen rot (42,5 Grad), daneben ein schwacher zweiter Bogen.
    let t = (angle - 40.5) / 2.0;
    let t2 = (53.5 - angle) / 3.0;
    let hue = vec3<f32>(smoothstep(0.45, 0.95, t) * smoothstep(1.2, 0.95, t),
                        smoothstep(0.15, 0.55, t) * smoothstep(0.95, 0.6, t),
                        smoothstep(-0.2, 0.15, t) * smoothstep(0.55, 0.2, t));
    let hue2 = vec3<f32>(smoothstep(0.45, 0.95, t2) * smoothstep(1.2, 0.95, t2),
                         smoothstep(0.15, 0.55, t2) * smoothstep(0.95, 0.6, t2),
                         smoothstep(-0.2, 0.15, t2) * smoothstep(0.55, 0.2, t2));
    let base = smoothstep(0.0, 0.12, d.y);
    return (hue * 0.14 + hue2 * 0.045) * strength * base;
}

// Im End: dunkler, violetter Himmel mit leuchtendem Nebel.
fn end_sky(d: vec3<f32>, base: vec3<f32>) -> vec3<f32> {
    let n = vnoise(d * 3.0 + vec3<f32>(0.0, frame.time * 0.01, 0.0)) * 0.6 + vnoise(d * 8.0) * 0.4;
    let swirl = smoothstep(0.45, 0.85, n);
    let nebula = mix(vec3<f32>(0.10, 0.04, 0.16), vec3<f32>(0.28, 0.12, 0.34), swirl) * (0.6 + 0.4 * swirl);
    return base * 0.7 + nebula + stars(d, 0.0) * 0.6;
}

fn sky(input: SkyInput) -> vec4<f32> {
    let d = normalize(input.direction);
    if frame.dimension == 1 {
        return vec4<f32>(min(end_sky(d, input.color.rgb), vec3<f32>(1.0)), 1.0);
    }
    if frame.dimension != 0 {
        return input.color;
    }
    var col = atmosphere(d);

    // Sonnenscheibe mit Randverdunkelung.
    let mu = dot(d, frame.sun_direction);
    // Etwa 1,6 Grad Radius, etwas groesser als die echte Sonne wie bei Photon.
    let disc = smoothstep(0.99955, 0.99963, mu);
    let limb = sqrt(max(1.0 - (1.0 - mu) / (1.0 - 0.99955), 0.0));
    let sun_col = sun_tint() * vec3<f32>(1.0, 0.95, 0.85);
    let horizon_cut = smoothstep(-0.02, 0.01, d.y);
    let clear = 1.0 - frame.rain * 0.9;
    col += sun_col * disc * mix(0.6, 1.0, limb) * 1.6 * horizon_cut * clear;
    // Weicher Hof direkt um die Sonne.
    col += sun_col * pow(max(mu, 0.0), 900.0) * 0.35 * horizon_cut * clear;

    // Nachts: Sterne und Milchstrasse, am Horizont schwaecher (dickere Luft).
    let night = 1.0 - smoothstep(-0.12, 0.05, frame.sun_direction.y);
    if night > 0.0 && d.y > -0.05 {
        let cd = celestial(d);
        let air = smoothstep(-0.05, 0.25, d.y);
        let band = milky_band(cd);
        col += (stars(cd, band) + milky_way(cd, band)) * night * air * clear;
    }

    col += rainbow(d);
    return vec4<f32>(min(col, vec3<f32>(1.0)), 1.0);
}
