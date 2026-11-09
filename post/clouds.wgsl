// Volumetrische Wolken (eigene Umsetzung, inspiriert vom Photon-Look).
// Vanillas Block-Wolken sind aus ([sky] clouds = false); stattdessen wird eine
// Wolkenschicht aus 3D-Rauschen (cloud_density in common.wgsl) durchlaufen:
// weiche Kumuluswolken mit flachem Boden, runden Koepfen, ausgefransten
// Raendern, Selbstschatten, hellem Rand Richtung Sonne und Himmelslicht von oben.

fn post(input: PostInput) -> vec4<f32> {
    if soft_clouds <= 0.0 || frame.dimension != 0 {
        return input.color;
    }
    let p = view_position(input.uv, select(1e-4, input.depth, input.depth > 0.0));
    let d = normalize(p);
    // Gelaende verdeckt die Wolken dahinter.
    let terrain = select(1e9, length(p), input.depth > 0.0);

    // Schnitt mit der Wolkenschicht.
    let cy = frame.camera_position.y;
    if abs(d.y) < 0.002 {
        return input.color;
    }
    let t0 = (C_BOTTOM - cy) / d.y;
    let t1 = (C_TOP - cy) / d.y;
    let t_near = max(min(t0, t1), 0.0);
    let t_far = min(min(max(t0, t1), t_near + 1500.0), terrain);
    if t_far <= t_near || t_near > 6000.0 {
        return input.color;
    }

    // Niedrig 8, Mittel 12, Hoch 16, Ultra 24 Schritte durch die Wolkenschicht.
    let steps = by_quality(8, 12, 16, 24);
    let fine = quality >= 1u;
    let dt = (t_far - t_near) / f32(steps);
    let jitter = pixel_noise(input.pixel);
    let cam = frame.camera_position;

    let day = daylight();
    let low = sun_low();
    let light_dir = select(frame.moon_direction, frame.sun_direction, frame.sun_direction.y > -0.05);
    let mu = dot(d, light_dir);
    let phase = (hg_phase(mu, 0.65) * 0.6 + hg_phase(mu, -0.25) * 0.4) * 12.566;
    let sun_col = sun_tint() * mix(vec3<f32>(1.0, 0.96, 0.9), vec3<f32>(1.0, 0.72, 0.58), low) * (1.35 + 1.0 * low) * day
        + vec3<f32>(0.05, 0.07, 0.12) * (1.0 - day);
    let zen = atmosphere(vec3<f32>(0.0, 1.0, 0.0));
    let sky_up = max(mix(zen, vec3<f32>(luminance(zen)), 0.45), vec3<f32>(0.16, 0.15, 0.17) * day);
    let rain_dim = 1.0 - frame.rain * 0.6;

    var transmit = 1.0;
    var light = vec3<f32>(0.0);
    for (var i = 0; i < steps; i++) {
        let t = t_near + (f32(i) + jitter) * dt;
        let pw = cam + d * t;
        let dens = cloud_density(pw, fine);
        if dens > 0.002 {
            // Licht zur Sonne: wie viel Wolke liegt dazwischen?
            var od = 0.0;
            if fine {
                for (var j = 1; j <= 2; j++) {
                    let s = f32(j * j) * 10.0;
                    od += cloud_density(pw + light_dir * s, false) * f32(2 * j - 1) * 10.0;
                }
            } else {
                // Niedrig: eine Probe fuer die ganze Strecke.
                od = cloud_density(pw + light_dir * 18.0, false) * 40.0;
            }
            // Mehrfachstreuung: Wolken werden innen nie ganz schwarz.
            let light_t = max(exp(-od * SIGMA * 0.9), 0.45 * exp(-od * SIGMA * 0.15));
            let powder = 1.0 - exp(-dens * 2.5);
            let hf = (pw.y - C_BOTTOM) / (C_TOP - C_BOTTOM);
            let direct = sun_col * light_t * mix(1.0, phase, 0.7) * mix(0.6, 1.0, powder);
            let ambient = sky_up * mix(0.5, 1.0, hf) * 1.15;
            let step_t = exp(-dens * SIGMA * dt);
            light += transmit * (direct + ambient) * rain_dim * (1.0 - step_t);
            transmit *= step_t;
            if transmit < 0.03 {
                break;
            }
        }
    }

    // In der Ferne in den Himmel ausblenden (Luftperspektive).
    let fade = exp(-t_near / 2800.0) * smoothstep(0.0, 0.06, d.y + 0.02) * min(soft_clouds, 1.0);
    let horizon_sky = atmosphere(d);
    let clouds = mix(horizon_sky * (1.0 - transmit), light, fade);
    let result = input.color.rgb * mix(1.0, transmit, fade) + clouds * fade;
    return vec4<f32>(result, input.color.a);
}
