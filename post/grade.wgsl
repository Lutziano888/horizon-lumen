// Farbkorrektur im Photon-Stil: natuerlich statt knallig. Leicht warmer
// Weissabgleich, Gelbgruen etwas gedaempft und Richtung Gruen gedreht (keine
// Limetten-Wiesen), sanft angehobene Schatten, nachts Purkinje und Vignette.
override exposure: f32 = 1.0;
override saturation: f32 = 1.0;
override vignette: bool = true;

fn post(input: PostInput) -> vec4<f32> {
    // Unter Tage passt sich das Auge etwas an (wie bei Photon), langsam ueber eye_light_smooth.
    // Nur langsam heller werden, wenn es dunkel wird; wird es hell (aus der Hoehle
    // oder aus dem Wasser auftauchen), sofort zurueck, sonst blendet es kurz.
    let eye = max(frame.eye_light_smooth.y, frame.eye_light.y);
    var underground = 1.0 - smoothstep(0.05, 0.5, eye);
    // Unter Wasser regelt fog.wgsl die Helligkeit selbst.
    underground *= 1.0 - frame.in_water;
    if camera_underwater() {
        underground = 0.0;
    }
    let adapt = mix(1.0, 1.35, underground * overworld());
    var lin = pow(max(input.color.rgb, vec3<f32>(0.0)), vec3<f32>(2.2)) * exposure * adapt;

    // Leicht warm, morgens und abends waermer.
    lin *= mix(vec3<f32>(1.03, 1.0, 0.95), vec3<f32>(1.10, 1.0, 0.82), sun_low() * daylight());

    // Nachts dunkle Farben leicht blau verschieben.
    let night = (1.0 - daylight()) * overworld();
    let dark = 1.0 - smoothstep(0.0, 0.06, luminance(lin));
    lin = mix(lin, vec3<f32>(luminance(lin)) * vec3<f32>(0.8, 0.95, 1.25), dark * night * 0.5);

    // Gelbgruen erkennen und etwas zuruecknehmen.
    let yg = clamp((min(lin.r, lin.g) - lin.b) / (max(max(lin.r, lin.g), lin.b) + 1e-4), 0.0, 1.0);
    let l = luminance(lin);
    lin = max(vec3<f32>(l) + (lin - vec3<f32>(l)) * saturation * (1.0 - 0.08 * yg), vec3<f32>(0.0));
    lin.r = max(lin.r - yg * 0.03 * lin.g, 0.0);
    lin = mix(lin, lin * lin / (lin + vec3<f32>(0.02)) * 1.02, 0.5);

    // Filmische Schulter: alles bis 0.8 bleibt wie es ist, hellere Stellen
    // (Wolken, Sonne, Bloom) laufen weich auf Weiss zu statt hart abzuschneiden.
    var c = pow(max(lin, vec3<f32>(0.0)), vec3<f32>(1.0 / 2.2));
    let over = max(c - vec3<f32>(0.8), vec3<f32>(0.0));
    c = min(c, vec3<f32>(0.8)) + 0.2 * (vec3<f32>(1.0) - exp(-over / 0.2));
    c = c * 0.98 + 0.02;

    if vignette {
        let aspect = frame.resolution.x / frame.resolution.y;
        let v = length((input.uv - 0.5) * vec2<f32>(aspect, 1.0)) / length(vec2<f32>(aspect, 1.0) * 0.5);
        c *= 1.0 - smoothstep(0.5, 1.2, v) * 0.2;
    }
    return vec4<f32>(clamp(c, vec3<f32>(0.0), vec3<f32>(1.0)), input.color.a);
}
