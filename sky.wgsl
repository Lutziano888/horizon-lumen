// Physikalisch inspirierter Himmel (atmosphere() in common.wgsl) mit runder
// Sonne statt Vanillas eckiger. Mond und Sterne bleiben von Vanilla, die
// Wolken zeichnet der Wolken-Durchgang.
fn sky(input: SkyInput) -> vec4<f32> {
    if frame.dimension != 0 {
        return input.color;
    }
    let d = normalize(input.direction);
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

    return vec4<f32>(min(col, vec3<f32>(1.0)), 1.0);
}
