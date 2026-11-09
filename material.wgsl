// Lumen: Beleuchtung im Photon-Stil.
// - warmes Sonnenlicht mit echten Schatten aus der Schattenkarte (weich gefiltert),
//   farbig durch Wasser (mit Kaustiken) und buntes Glas
// - blaues Himmelslicht in den Schatten, weiche Wolkenschatten
// - Blaetter und Pflanzen mit Durchleuchtung (Subsurface)
// - warmes oder farbiges Blocklicht, leuchtende Bloecke
// - klares Wasser mit Wellen, Brechung, Tiefenfarbe, Spiegelung und Sonnenglanz
// - eigener Nebel, der am Rand der Sichtweite nahtlos in den Himmel uebergeht
// In linearen Farben gerechnet, mit weicher Schulter zurueck in Bildschirmfarben.

override sun_strength: f32 = 1.0;
override ambient_strength: f32 = 1.0;
override ambient_blue: f32 = 0.45;
override torch_warmth: f32 = 0.7;
override colored_lights: bool = true;
override shadow_softness: f32 = 1.0;
override cloud_shadows: f32 = 0.6;
override water_waves: f32 = 1.0;
override water_clarity: f32 = 0.5;
override reflections: bool = true;
// Werden von Horizon selbst gelesen ([shadow] in horizon-shaders.toml).
override shadows: bool = true;
override shadow_quality: u32 = 1u;
override shadow_distance: u32 = 2u;

// --- Hilfen ---

// Vanillas Flaechenschattierung (oben 1, Nord/Sued 0.8, Ost/West 0.6, unten 0.5),
// damit sie nicht doppelt zum eigenen Sonnenlicht dazukommt.
fn vanilla_shade(n: vec3<f32>) -> f32 {
    let a = abs(n);
    if a.y > 0.99 {
        return select(0.5, 1.0, n.y > 0.0);
    }
    if a.z > 0.99 {
        return 0.8;
    }
    if a.x > 0.99 {
        return 0.6;
    }
    return 1.0;
}

// Weiche Schulter: bis 0.6 unveraendert, darueber laeuft es farbtreu auf 1 zu.
fn encode(lit: vec3<f32>) -> vec3<f32> {
    let m = max(max(lit.r, lit.g), lit.b);
    var c = lit;
    if m > 0.6 {
        let k = 0.6 + 0.4 * (1.0 - exp(-(m - 0.6) / 0.4));
        c = lit * (k / m);
    }
    return to_display(c);
}


// Wie viel direktes Licht ankommt, farbig wo es durch Wasser oder Glas faellt.
fn sun_shadow(pos: vec3<f32>, offset_dir: vec3<f32>, sky: f32, world: vec3<f32>) -> vec3<f32> {
    // Ohne Karte und in der Ferne: das Himmelslicht des Blocks als Verdeckung.
    let fallback = smoothstep(0.55, 0.93, sky);
    if frame.has_shadow == 0u {
        return vec3<f32>(fallback);
    }
    let clip = frame.shadow_view_proj * vec4<f32>(pos, 1.0);
    let edge = smoothstep(0.80, 0.96, max(abs(clip.x), abs(clip.y)));
    if edge >= 1.0 {
        return vec3<f32>(fallback);
    }
    // Groesse eines Texels der (verzerrten) Karte an dieser Stelle, in Bloecken.
    let k = frame.shadow_distortion;
    let g = length(clip.xy) * k + 1.0 - k;
    let texel = frame.shadow_center_texel * g * g / max((1.0 - k) * (1.0 - k), 1e-4);
    let p = pos + offset_dir * (texel * 1.6 + 0.015);
    let sp = shadow_position(p);
    let m = frame.shadow_view_proj;
    let z_per_block = length(vec3<f32>(m[0].z, m[1].z, m[2].z));
    let z = sp.z - z_per_block * texel * 0.6;

    // NxN Abtastungen mit je 2x2 Filter: weiche Kanten ohne Rauschen.
    // Niedrig 1, Mittel 2x2, Hoch 3x3, Ultra 5x5 (gleich weit, nur feiner).
    let n = by_quality(1, 2, 3, 5);
    let span = 2.0 * shadow_softness / frame.shadow_resolution;
    let step = span * select(2.0 / f32(max(n - 1, 1)), 1.0, n <= 2);
    let first = -0.5 * f32(n - 1);
    var lit = 0.0;
    for (var i = 0; i < n; i++) {
        for (var j = 0; j < n; j++) {
            let o = vec2<f32>(first + f32(i), first + f32(j)) * step;
            lit += textureSampleCompareLevel(shadow_map, shadow_sampler, sp.xy + o, z);
        }
    }
    lit /= f32(n * n);

    var color = vec3<f32>(lit);
    let lit_t = textureSampleCompareLevel(shadow_map_translucent, shadow_sampler, sp.xy, z);
    let through = clamp(lit - lit_t, 0.0, 1.0);
    if through > 0.01 {
        let size = vec2<f32>(textureDimensions(shadow_color));
        let tc = textureLoad(shadow_color, vec2<i32>(clamp(sp.xy * size, vec2<f32>(0.0), size - 1.0)), 0);
        var tint = to_linear(tc.rgb) * (1.0 - tc.a * 0.4);
        if tc.a > 0.995 {
            // Wasser: blaugruen mit tanzenden Kaustiken.
            tint = vec3<f32>(0.45, 0.85, 0.88) * (caustics(world) * 1.35 - 0.2);
        }
        color = vec3<f32>(lit - through) + tint * through;
    }
    return mix(color, vec3<f32>(fallback), edge);
}

// Weiche Schatten der ziehenden Wolken.
fn cloud_shade(world: vec3<f32>, l: vec3<f32>) -> f32 {
    if cloud_shadows <= 0.0 || soft_clouds <= 0.0 || l.y < 0.08 || world.y > C_BOTTOM {
        return 1.0;
    }
    let t1 = (C_BOTTOM + 18.0 - world.y) / l.y;
    let t2 = (C_BOTTOM + 36.0 - world.y) / l.y;
    // Niedrig: eine Probe statt zwei.
    var d = cloud_density(world + l * t1, false);
    if quality >= 1u {
        d += cloud_density(world + l * t2, false);
    } else {
        d *= 2.0;
    }
    let strength = cloud_shadows * min(soft_clouds, 1.0) * smoothstep(0.08, 0.25, l.y);
    return 1.0 - smoothstep(0.0, 0.7, d) * 0.8 * strength;
}

// Eigener Nebel: am Rand der Sichtweite in den Himmel, sonst wie Vanilla.
fn apply_fog(color: vec3<f32>, pos: vec3<f32>, dist: f32) -> vec3<f32> {
    // Unter Wasser macht der Durchgang post/fog.wgsl den Nebel (weicher, blaugruen).
    if frame.dimension == 0 && camera_underwater() && frame.blindness <= 0.0 && frame.darkness <= 0.0 {
        return color;
    }
    if frame.dimension != 0 || frame.eye_in != 0u || frame.blindness > 0.0 || frame.darkness > 0.0 {
        let f = clamp((dist - frame.fog_start) / max(frame.fog_end - frame.fog_start, 1e-3), 0.0, 1.0);
        return mix(color, frame.fog_color, f);
    }
    let flat_dist = max(length(pos.xz), abs(pos.y));
    let end = max(frame.fog_end, 16.0);
    let f = smoothstep(end * 0.86, end * 1.0, flat_dist);
    if f <= 0.0 {
        return color;
    }
    // In Hoehlen dunkel statt himmelblau.
    let outside = smoothstep(0.15, 0.7, frame.eye_light_smooth.y);
    let sky = mix(frame.fog_color * 0.3, atmosphere(pos / max(dist, 1e-3)), outside);
    return mix(color, sky, f);
}

// --- Wasser ---

// Hoehe der Wellen an einer Stelle (0..1): mehrere Wellenzuege mit weichem Profil
// (quadrierter Sinus: runde Kaemme, flache Taeler), jeder etwas gedreht und laenger,
// und jeder mit einer eigenen, langsam wandernden Rausch-Verschiebung der Phase. So
// gibt es keine geraden Linien und kein Muster, das sich wiederholt. Dazu ruhige und
// bewegte Zonen ueber grosse Flaechen.
fn wave_train(xz: vec2<f32>, t: f32, detail: f32, start: vec2<f32>, seed: f32) -> f32 {
    var dir = start;
    let turn = mat2x2<f32>(-0.7374, 0.6755, -0.6755, -0.7374);
    var amp = 1.0;
    var wl = 3.5;
    var sum = 0.0;
    var norm = 0.0;
    // Feineres Rauschen: biegt auch die grossen Wellen, so entstehen keine geraden,
    // parallelen Linien quer uebers Wasser.
    var noise_pos = (xz + vec2<f32>(0.0, t * 0.25)) * 0.12;
    // Niedrig 3, Mittel 4, sonst 5 Wellen (die feinsten zuerst weg).
    let count = by_quality(3, 4, 5, 5);
    for (var i = 0; i < count; i++) {
        let n = vnoise(vec3<f32>(noise_pos, f32(i) * 7.3 + seed)) * 1.6;
        let k = 6.2832 / wl;
        let x = sqrt(9.8 * k) * t - k * (dot(dir, xz) + n);
        let s = sin(x) * 0.5 + 0.5;
        let fade = select(1.0, detail, i >= 2);
        // Die laengste Welle nicht dominieren lassen.
        let a = amp * select(1.0, 0.55, i == 0);
        sum += s * s * a * fade;
        norm += a;
        amp *= 0.62;
        wl /= 1.7;
        dir = turn * dir;
        noise_pos *= 1.6;
    }
    return sum / norm;
}

fn wave_height(xz: vec2<f32>, t: f32, detail: f32) -> f32 {
    // Zwei Wellenfelder aus verschiedenen Richtungen, ueber die Flaeche gemischt,
    // dazu ruhige und bewegte Zonen.
    let zones = max(0.35, vnoise(vec3<f32>(xz * 0.012 + vec2<f32>(0.0, t * 0.0012), 3.0)) * 2.0 - 0.4);
    let a = wave_train(xz, t, detail, vec2<f32>(0.866, 0.5), 0.0);
    // Niedrig: nur ein Wellenfeld.
    if quality == 0u {
        return a * zones;
    }
    let m = clamp((vnoise(vec3<f32>(xz * 0.008 + vec2<f32>(0.0, t * 0.01), 11.0)) - 0.5) * 3.0 + 0.5, 0.0, 1.0);
    let b = wave_train(xz, t, detail, vec2<f32>(-0.34, 0.94), 40.0);
    return mix(a, b, m) * zones;
}

// Steigung der Wellen (dh/dx, dh/dz) aus der Hoehe, dazu Kraeuseln und Regenringe.
fn wave_slope(xz: vec2<f32>, detail: f32) -> vec2<f32> {
    let t = frame.time * 0.5 * (1.0 + frame.rain * 0.4 + frame.thunder * 0.4);
    let e = 0.1;
    let h0 = wave_height(xz, t, detail);
    let hx = wave_height(xz + vec2<f32>(e, 0.0), t, detail);
    let hz = wave_height(xz + vec2<f32>(0.0, e), t, detail);
    let strength = 0.11 * (1.0 + frame.rain * 0.6);
    var g = vec2<f32>(hx - h0, hz - h0) / e * strength;
    // Kraeuseln.
    let q = vec3<f32>(xz.x * 2.3 + t * 0.8, t * 0.6, xz.y * 2.3 - t * 0.7);
    let n0 = vnoise(q);
    g += vec2<f32>(vnoise(q + vec3<f32>(0.12, 0.0, 0.0)) - n0, vnoise(q + vec3<f32>(0.0, 0.0, 0.12)) - n0) / 0.12 * 0.012 * detail;
    // Regentropfen: Ringe, die sich ausbreiten.
    if quality >= 1u && frame.rain > 0.05 && detail > 0.2 {
        let cell = floor(xz * 1.5);
        for (var j = 0; j < 4; j++) {
            let off = vec2<f32>(f32(j % 2), f32(j / 2));
            let c = cell + off;
            let h = hash3(vec3<i32>(vec2<i32>(c), 7));
            let life = fract(frame.time * 0.9 + h);
            let center = (c + vec2<f32>(hash3(vec3<i32>(vec2<i32>(c), 3)), hash3(vec3<i32>(vec2<i32>(c), 5)))) / 1.5;
            let dv = xz - center;
            let r = length(dv);
            let ring = sin((r - life * 0.6) * 40.0) * smoothstep(0.12, 0.0, abs(r - life * 0.6)) * (1.0 - life);
            g += dv / max(r, 1e-3) * ring * 0.08 * frame.rain * detail;
        }
    }
    return g;
}

// Abstand von `c` zur Strecke zwischen Vanillas Nebel- und Himmelsfarbe:
// so erkennt man den Himmel im Spiegelbild.
fn sky_distance(c: vec3<f32>) -> f32 {
    let a = frame.fog_color;
    let ab = frame.sky_color - a;
    let t = clamp(dot(c - a, ab) / max(dot(ab, ab), 1e-5), 0.0, 1.0);
    return length(c - (a + ab * t));
}

fn shade_water(input: MaterialInput, pos: vec3<f32>, dist: f32, view: vec3<f32>, world: vec3<f32>) -> vec3<f32> {
    let below = camera_underwater();
    let top = input.face == 1u;
    let l = light_dir();
    var n = input.normal;
    if top && water_waves > 0.0 {
        let detail = exp(-dist / 24.0);
        // In der Ferne flacher: sonst werden die Wellen dort zu duennen hellen Linien.
        let fade = water_waves * mix(0.12, 1.0, exp(-dist / 35.0));
        let g = wave_slope(world.xz, detail) * fade;
        // Von unten gesehen zeigt die Normale nach unten.
        n = normalize(vec3<f32>(-g.x, 1.0, -g.y)) * select(1.0, -1.0, below);
    }
    let nv = max(dot(n, -view), 0.0);
    let fresnel = 0.02 + 0.98 * pow(1.0 - nv, 5.0);

    // Was hinter der Oberflaeche liegt, leicht gebrochen.
    let size = vec2<f32>(textureDimensions(opaque_depth));
    // Nur die Wellen verschieben das Bild, nicht die Neigung der Flaeche selbst.
    let vn = (frame.view * vec4<f32>(n - input.normal, 0.0)).xyz;
    var bend = vec2<f32>(vn.x, -vn.y) * 0.025 * exp(-dist / 64.0);
    let clip = frame.projection * frame.view * vec4<f32>(pos, 1.0);
    let surface_depth = clip.z / clip.w;
    let p0 = vec2<i32>(clamp(input.screen * size, vec2<f32>(0.0), size - 1.0));
    let p1 = vec2<i32>(clamp((input.screen + bend) * size, vec2<f32>(0.0), size - 1.0));
    let d0 = textureLoad(opaque_depth, p0, 0);
    let d1 = textureLoad(opaque_depth, p1, 0);
    // Nur brechen, wenn auch dort etwas hinter dem Wasser liegt.
    let use_bent = d1 < surface_depth;
    let behind_depth = select(d0, d1, use_bent);
    let behind = to_linear(textureLoad(opaque_color, select(p0, p1, use_bent), 0).rgb);

    let direct = direct_light() * sun_strength * cloud_shade(world, l);
    let shadow = sun_shadow(pos, vec3<f32>(0.0, 1.0, 0.0), input.light.y, world);
    let sky_amount = input.light.y * input.light.y;

    if below {
        // Von unten: Snells Fenster nach oben (der Himmel, leicht gewellt und hell),
        // ausserhalb davon spiegelt die Oberflaeche das Wasser darunter.
        let window = smoothstep(0.60, 0.74, nv);
        let deep = vec3<f32>(0.010, 0.085, 0.120) * (luminance(direct) * 0.25 + sky_light(ambient_blue) * 0.9 + 0.02) * mix(0.3, 1.0, sky_amount);
        let rim = (1.0 - smoothstep(0.60, 0.68, nv)) * smoothstep(0.52, 0.60, nv);
        let sky_seen = behind * vec3<f32>(0.80, 0.95, 1.0) * 1.15 + direct * shadow * pow(max(dot(-view, l), 0.0), 60.0) * 2.0;
        return mix(deep, sky_seen, window) + vec3<f32>(0.10, 0.20, 0.22) * rim * sky_amount;
    }

    // Wassertiefe entlang des Blicks.
    var thickness = 48.0;
    if behind_depth > 0.0 {
        let ndc = vec4<f32>(input.screen.x * 2.0 - 1.0, 1.0 - input.screen.y * 2.0, behind_depth, 1.0);
        let v = frame.projection_inverse * ndc;
        thickness = max(length(v.xyz / v.w) - dist, 0.0);
    }
    let absorb = vec3<f32>(0.30, 0.085, 0.055) * mix(1.8, 0.45, water_clarity);
    let transmit = exp(-absorb * thickness);
    let biome = to_linear(input.tint.rgb);
    let scatter = mix(vec3<f32>(0.004, 0.022, 0.035), biome * 0.04, 0.4);
    let light_in = sky_light(ambient_blue) * sky_amount + direct * max(l.y, 0.0) * 0.35 * shadow;
    var inside = behind * transmit + scatter * light_in * (1.0 - transmit) * 2.2;
    // Durchleuchtete Wellen: gegen die Sonne leuchten die Kaemme tuerkis.
    let back = pow(max(dot(view, l), 0.0), 4.0) * max(n.y - 0.0, 0.0) * (1.0 - nv);
    inside += vec3<f32>(0.02, 0.16, 0.14) * direct * shadow * back * 0.6;
    // Schaum am Ufer: duenne, weiche, wandernde Linie im ganz flachen Wasser.
    if top && thickness < 0.6 {
        let foam_noise = vnoise(vec3<f32>(world.xz * 3.0, frame.time * 0.6));
        let foam = (1.0 - smoothstep(0.02, 0.25, thickness + foam_noise * 0.2)) * 0.18;
        inside = mix(inside, (sky_light(ambient_blue) * sky_amount + direct * max(l.y, 0.0) * shadow) * 0.75, foam);
    }

    // Spiegelung: eigener Himmel, Gelaende aus Horizons Wasserspiegel.
    let r = reflect(view, n);
    var refl = to_linear(atmosphere(vec3<f32>(r.x, max(r.y, 0.01), r.z)));
    // Wolken im Spiegelbild (grob, eine Probe in der Wolkenschicht).
    if quality >= 1u && soft_clouds > 0.0 && r.y > 0.03 {
        let tc = (C_BOTTOM + 20.0 - world.y) / r.y;
        let cd = cloud_density(world + r * tc, false);
        let cloud_col = to_linear(atmosphere(vec3<f32>(0.0, 1.0, 0.0))) * 0.6 + direct * 0.25;
        refl = mix(refl, cloud_col + vec3<f32>(0.25) * daylight(), smoothstep(0.0, 0.6, cd) * 0.75 * exp(-tc / 3000.0));
    }
    refl *= mix(0.12, 1.0, smoothstep(0.5, 0.95, input.light.y));
    if reflections && frame.has_reflection == 1u && top && abs(world.y - frame.water_plane) < 0.6 {
        let uv = clamp(input.screen + bend * 0.35, vec2<f32>(0.0), vec2<f32>(1.0));
        let mirror = textureSampleLevel(reflection, reflection_sampler, uv, 0.0).rgb;
        // Himmel-Erkennung an der ungestoerten Stelle und weich: sonst springen die Wellen
        // zwischen Spiegelbild und Himmel hin und her (fleckig, wie ein Oelfilm).
        let plain = textureSampleLevel(reflection, reflection_sampler, input.screen, 0.0).rgb;
        let is_sky = 1.0 - smoothstep(0.02, 0.20, min(sky_distance(mirror), sky_distance(plain)) * 0.5 + sky_distance(plain) * 0.5);
        refl = mix(to_linear(mirror) * 0.8, refl, is_sky);
    }

    // Sonnenglanz.
    let h = normalize(l - view);
    let nh = max(dot(n, h), 0.0);
    var glint = (pow(nh, 2400.0) * 18.0 + pow(nh, 300.0) * 0.15) * fresnel * 4.0;
    // Glitzern: einzelne Funken auf den Wellen in Richtung Sonne.
    if quality >= 1u {
        let sparkle_cell = vec3<i32>(vec3<f32>(floor(world.x * 6.0), floor(frame.time * 4.0), floor(world.z * 6.0)));
        glint += step(0.993, hash3(sparkle_cell)) * pow(nh, 200.0) * 18.0 * exp(-dist / 40.0);
    }
    let spec = direct * shadow * glint;

    return mix(inside, refl, fresnel) + spec;
}

// --- Andere Dimensionen: Vanilla mit etwas mehr Kontrast ---

fn other_dimension(input: MaterialInput, base: vec4<f32>, dist: f32) -> Surface {
    var light = pow(input.lightmap, vec3<f32>(1.15));
    if colored_lights {
        let c = block_light_color(input.position);
        if c.a > 0.001 {
            let col = c.rgb / max(max(max(c.r, c.g), c.b), 1e-3);
            light = mix(light, light * col * 1.2, clamp(c.a * 2.0, 0.0, 1.0) * input.light.x);
        }
    }
    let glow = base.rgb * input.emission * 0.6;
    let lit = to_linear(base.rgb * light + glow) + input.colored_light * to_linear(base.rgb) * 1.5;
    // Fuer post/bloom.wgsl: Gelaende, und wie stark es selbst leuchtet.
    set_surface(input.normal, 0.0, 1.0 + clamp(input.emission, 0.0, 1.0));
    let color = apply_fog(encode(lit), input.position, dist);
    return Surface(vec4<f32>(color, base.a));
}

// --- Oberwelt ---

fn material(input: MaterialInput) -> Surface {
    let base = input.albedo * input.tint;
    let pos = input.position;
    let dist = length(pos);
    if frame.dimension != 0 {
        return other_dimension(input, base, dist);
    }
    let view = pos / max(dist, 1e-4);
    let world = pos + frame.camera_position;

    if input.fluid == 1u {
        let water = shade_water(input, pos, dist, view, world);
        return Surface(vec4<f32>(apply_fog(encode(water), pos, dist), 1.0));
    }
    if input.fluid == 2u {
        // Lava leuchtet selbst.
        let lava = to_linear(base.rgb) * 2.4;
        set_surface(input.normal, 0.0, 2.0);
        return Surface(vec4<f32>(apply_fog(encode(lava), pos, dist), base.a));
    }

    let id = input.material;
    let foliage = id >= M_LEAVES && id <= M_KELP;
    let plant = foliage && id != M_LEAVES;
    let n = input.normal;

    var tint = input.tint.rgb;
    if !foliage && id != M_LILY {
        tint *= mix(1.0, 1.0 / vanilla_shade(n), 0.8);
    }
    // Nach Regen: Boden unter freiem Himmel wird dunkler und glaenzt leicht.
    let wet = frame.wetness * smoothstep(0.85, 0.97, input.light.y) * smoothstep(0.5, 0.9, n.y) * select(1.0, 0.0, foliage);
    let albedo = to_linear(input.albedo.rgb) * to_linear(tint) * mix(1.0, 0.65, wet);

    let l = light_dir();
    let sky = input.light.y;
    let block = input.light.x;

    // Direktes Licht.
    var ndl = max(dot(n, l), 0.0);
    if id == M_LEAVES {
        ndl = ndl * 0.6 + 0.4;
    }
    if plant {
        // Pflanzen werden wie der Boden darunter beleuchtet.
        ndl = 0.3 + 0.32 * max(l.y, 0.0);
    }
    // Pflanzen: ein Stueck zur Sonne hin pruefen, sonst beschatten sie sich selbst.
    let shadow_point = pos + select(select(vec3<f32>(0.0), l * 0.35, id == M_LEAVES), l * 0.2, plant);
    let shadow = sun_shadow(shadow_point, select(n, l, foliage), sky, world);
    let sun = direct_light() * sun_strength * cloud_shade(world, l) * shadow;
    var direct = sun * ndl;
    if foliage {
        // Durchleuchtung: gegen die Sonne gesehen gluehen Blaetter warm.
        let through = pow(max(dot(view, l), 0.0), 6.0) * 0.9 + select(0.0, 0.3, id == M_LEAVES);
        direct += sun * through * vec3<f32>(1.0, 0.95, 0.7) * 0.6;
    }

    // Himmelslicht: von oben am meisten, unten am wenigsten.
    let up = select(n.y, 1.0, plant);
    let facing = mix(0.55, 1.0, up * 0.5 + 0.5);
    let ambient = sky_light(ambient_blue) * ambient_strength * facing * sky * sky * select(select(1.0, 0.85, plant), 1.6, id == M_LEAVES);

    // Blocklicht: warm oder in der Farbe der Lichtquellen in der Naehe.
    // (Erst deklarieren, dann zuweisen: naga stolpert sonst ueber die Option im Startwert.)
    var torch_col: vec3<f32>;
    torch_col = mix(vec3<f32>(1.0), vec3<f32>(1.0, 0.58, 0.28), torch_warmth);
    if colored_lights {
        let c = block_light_color(pos);
        if c.a > 0.001 {
            let col = c.rgb / max(max(max(c.r, c.g), c.b), 1e-3);
            torch_col = mix(torch_col, col, clamp(c.a * 2.0, 0.0, 1.0));
        }
    }
    let torch = torch_col * (pow(block, 3.0) * 1.9 + block * 0.02);
    let held = input.colored_light * 1.6;

    // Ein Rest Licht in dunklen Hoehlen, Helligkeit und Nachtsicht aus den Optionen.
    let minimum = vec3<f32>(0.0035 + frame.brightness * 0.010) * vec3<f32>(0.85, 0.9, 1.1) + vec3<f32>(frame.night_vision * 0.35);

    // Leuchtende Bloecke: helle Texel strahlen.
    let glow = albedo * input.emission * (1.0 + 3.0 * smoothstep(0.3, 0.9, luminance(input.albedo.rgb)));

    var lit = albedo * (direct + ambient + torch + held + minimum) + glow;
    // Fuer post/fog.wgsl und post/bloom.wgsl: hier ist Gelaende (Mobs und Objekte haben
    // das nicht), und wie stark es selbst leuchtet.
    set_surface(n, 0.0, 1.0 + clamp(input.emission, 0.0, 1.0));
    if wet > 0.01 {
        let r = reflect(view, n);
        let f = 0.02 + 0.98 * pow(1.0 - max(dot(n, -view), 0.0), 5.0);
        lit += to_linear(atmosphere(vec3<f32>(r.x, max(r.y, 0.01), r.z))) * f * wet * 0.6;
    }
    return Surface(vec4<f32>(apply_fog(encode(lit), pos, dist), base.a));
}
