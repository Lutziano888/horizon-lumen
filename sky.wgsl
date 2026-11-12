// Physikalisch inspirierter Himmel (atmosphere() in common.wgsl) mit runder
// Sonne statt Vanillas eckiger, eigenen funkelnden Sternen mit Milchstrasse
// und einem Regenbogen nach dem Regen. Der Mond bleibt von Vanilla, die Wolken
// zeichnet der Wolken-Durchgang. Im End der Weltraum aus common.wgsl.

// Dreht eine Richtung so, dass Sterne fest am Himmel stehen und mit Sonne und Mond
// ueber den Himmel wandern.
fn celestial(d: vec3<f32>) -> vec3<f32> {
    let s = frame.sun_direction;
    let a = atan2(s.y, s.x);
    let c = cos(a);
    let sn = sin(a);
    return vec3<f32>(d.x * c + d.y * sn, -d.x * sn + d.y * c, d.z);
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

fn sky(input: SkyInput) -> vec4<f32> {
    let d = normalize(input.direction);
    if frame.dimension == 1 {
        return vec4<f32>(end_space(d), 1.0);
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
