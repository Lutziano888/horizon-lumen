// Gemeinsame Helfer fuer alle Stufen von Lumen.

override soft_clouds: f32 = 1.0;
override cloud_amount: f32 = 0.4;

// Entfernung, die post/shafts.wgsl fuer Himmelspixel speichert.
const SKY_DIST: f32 = 60000.0;

// Grafikstufe: 0 Niedrig, 1 Mittel, 2 Hoch, 3 Ultra. Hoch ist der bisherige Look;
// die anderen Stufen tasten weniger oder mehr ab, das Design bleibt gleich.
override quality: u32 = 2u;

// Waehlt eine Anzahl je Grafikstufe.
fn by_quality(low: i32, mid: i32, high: i32, ultra: i32) -> i32 {
    return select(select(select(low, mid, quality >= 1u), high, quality >= 2u), ultra, quality >= 3u);
}

fn luminance(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn to_linear(c: vec3<f32>) -> vec3<f32> {
    return pow(max(c, vec3<f32>(0.0)), vec3<f32>(2.2));
}

fn to_display(c: vec3<f32>) -> vec3<f32> {
    return pow(max(c, vec3<f32>(0.0)), vec3<f32>(1.0 / 2.2));
}

fn overworld() -> f32 {
    return select(0.0, 1.0, frame.dimension == 0);
}

// 1 bei Tag, blendet am Horizont aus.
fn daylight() -> f32 {
    return smoothstep(-0.08, 0.12, frame.sun_direction.y) * overworld();
}

// 1 wenn die Sonne tief steht (Morgen/Abend).
fn sun_low() -> f32 {
    return 1.0 - smoothstep(0.0, 0.4, frame.sun_direction.y);
}

// Horizon schaltet die Schattenkarte genau bei Sonnenuntergang von der Sonne
// auf den Mond um; das direkte Licht ist dort schon fast weg.
fn sun_visible() -> f32 {
    return smoothstep(0.0, 0.07, frame.sun_direction.y) * overworld();
}

fn moon_visible() -> f32 {
    return smoothstep(0.0, 0.07, frame.moon_direction.y) * overworld();
}

// Relative Rayleigh-Streuung (blau streut am staerksten).
const RAYLEIGH: vec3<f32> = vec3<f32>(0.20, 0.45, 1.0);
// Etwas weicher fuer das Himmelsgewoelbe.
const SKY_RAYLEIGH: vec3<f32> = vec3<f32>(0.26, 0.50, 1.0);

// Farbe des Sonnenlichts nach dem Weg durch die Atmosphaere:
// mittags warm-weiss, beim Sonnenuntergang orange-rot.
fn sun_tint() -> vec3<f32> {
    let h = max(frame.sun_direction.y, 0.0);
    let air = 1.0 / (h + 0.05);
    return exp(-RAYLEIGH * air * 0.20);
}

// Henyey-Greenstein-Phasenfunktion (Mie-Streuung um die Sonne).
fn hg_phase(mu: f32, g: f32) -> f32 {
    let g2 = g * g;
    return (1.0 - g2) / (12.566 * pow(max(1.0 + g2 - 2.0 * g * mu, 1e-4), 1.5));
}

// Direktes Licht (linear): warme Sonne bei Tag, kuehler Mond bei Nacht.
fn direct_light() -> vec3<f32> {
    let low = sun_low();
    let sun = sun_tint() * vec3<f32>(1.0, 0.94, 0.86) * mix(2.1, 2.7, low) * sun_visible();
    let moon = vec3<f32>(0.055, 0.075, 0.13) * moon_visible() * (1.0 - sun_visible());
    let weather = 1.0 - frame.rain * 0.85;
    return (sun + moon) * weather;
}

// Himmelslicht (linear) von oben: blaeulich bei Tag, abends waermer, nachts dunkelblau.
fn sky_light(blue: f32) -> vec3<f32> {
    let day = daylight();
    let low = sun_low();
    let tone = mix(vec3<f32>(0.66, 0.68, 0.72), vec3<f32>(0.44, 0.57, 0.86), blue);
    let evening = mix(tone, vec3<f32>(0.62, 0.52, 0.50), low * 0.55) * mix(1.0, 0.7, low);
    let day_light = evening * 0.72;
    let night_light = vec3<f32>(0.010, 0.014, 0.028);
    let rainy = mix(day_light, vec3<f32>(luminance(day_light)) * 0.75, frame.rain);
    return mix(night_light, rainy, day);
}

// Der Himmel entlang einer Blickrichtung (Oberwelt), in Bildschirmfarben.
fn atmosphere(dir: vec3<f32>) -> vec3<f32> {
    let d = normalize(dir);
    let sun = frame.sun_direction;
    let mu = dot(d, sun);
    let up = max(d.y, 0.0);
    let horizon = 1.0 - up;
    let sun_col = sun_tint();
    let sky_day = min(1.0, max(sun.y, 0.0) * 4.0 + 0.15);

    // Einfachstreuung: mehr Luft = mehr Streuung.
    let view_air = 1.0 / (up + 0.20);
    let scatter = vec3<f32>(1.0) - exp(-SKY_RAYLEIGH * view_air * 0.30);
    var col = scatter * sun_col * 0.85 * (1.0 + 0.4 * mu * mu);

    // Mehrfachstreuung und weisser Dunst: weiches, helles Blau.
    col += SKY_RAYLEIGH * vec3<f32>(0.55, 0.75, 0.95) * 0.42 * sky_day * exp(-SKY_RAYLEIGH * view_air * 0.05);
    col += sun_col * 0.05 * sky_day;

    // Mie: Schein um die Sonne und warmer Dunst am Horizont.
    col += sun_col * hg_phase(mu, 0.78) * (0.35 + 0.65 * horizon) * 0.14;
    col += sun_col * vec3<f32>(1.0, 0.82, 0.6) * pow(horizon, 6.0) * 0.05 * (1.0 + 2.0 * sun_low());
    col *= 1.15;
    col = mix(col, vec3<f32>(luminance(col)), 0.06);

    // Horizont: helles, leicht blaues Weiss statt Ueberstrahlung.
    col = mix(col, vec3<f32>(luminance(col)) * vec3<f32>(0.95, 0.99, 1.08) * 1.1, pow(horizon, 4.0) * 0.4);
    // Unter dem Horizont: dunkleres, blaueres Grau statt einer weissen Wand.
    let below = 1.0 - smoothstep(-0.25, 0.0, d.y);
    col = mix(col, vec3<f32>(luminance(col)) * vec3<f32>(0.55, 0.65, 0.82), below * 0.8);

    // Nacht: dunkles Blau aus Vanillas Farben.
    let night = mix(frame.fog_color, frame.sky_color, smoothstep(-0.1, 0.4, d.y)) * vec3<f32>(0.75, 0.85, 1.15);
    let day = smoothstep(-0.12, 0.10, sun.y);
    let rainy = mix(col, vec3<f32>(luminance(col)) * 0.8, frame.rain);
    return mix(night, rainy, day * mix(1.0, 0.4, frame.rain * 0.85));
}

// Ein fester Zufallswert pro Pixel (Interleaved Gradient Noise).
fn pixel_noise(pixel: vec2<f32>) -> f32 {
    return fract(52.9829189 * fract(dot(floor(pixel), vec2<f32>(0.06711056, 0.00583715))));
}

// --- Wolken (fuer den Wolken-Durchgang und die Wolkenschatten) ---

const C_BOTTOM: f32 = 195.0;
const C_TOP: f32 = 255.0;
const SIGMA: f32 = 0.09;

fn hash3(p: vec3<i32>) -> f32 {
    var h = (bitcast<u32>(p.x) * 73856093u) ^ (bitcast<u32>(p.y) * 19349663u) ^ (bitcast<u32>(p.z) * 83492791u);
    h = (h ^ (h >> 13u)) * 1274126177u;
    h = h ^ (h >> 16u);
    return f32(h & 0xffffffu) / 16777215.0;
}

fn vnoise(p: vec3<f32>) -> f32 {
    let fl = floor(p);
    let i = vec3<i32>(fl);
    let f = p - fl;
    let u = f * f * (3.0 - 2.0 * f);
    let a = hash3(i);
    let b = hash3(i + vec3<i32>(1, 0, 0));
    let c = hash3(i + vec3<i32>(0, 1, 0));
    let d = hash3(i + vec3<i32>(1, 1, 0));
    let e = hash3(i + vec3<i32>(0, 0, 1));
    let g = hash3(i + vec3<i32>(1, 0, 1));
    let h = hash3(i + vec3<i32>(0, 1, 1));
    let k = hash3(i + vec3<i32>(1, 1, 1));
    return mix(mix(mix(a, b, u.x), mix(c, d, u.x), u.y), mix(mix(e, g, u.x), mix(h, k, u.x), u.y), u.z);
}

// Wie vnoise, dazu die Steigung: (Wert, d/dx, d/dy, d/dz). Fuer Wellen, deren
// Neigung so exakt in einem Durchgang herauskommt statt aus drei Auswertungen.
fn vnoise_d(p: vec3<f32>) -> vec4<f32> {
    let fl = floor(p);
    let i = vec3<i32>(fl);
    let f = p - fl;
    let u = f * f * (3.0 - 2.0 * f);
    let du = 6.0 * f * (1.0 - f);
    let a = hash3(i);
    let b = hash3(i + vec3<i32>(1, 0, 0));
    let c = hash3(i + vec3<i32>(0, 1, 0));
    let d = hash3(i + vec3<i32>(1, 1, 0));
    let e = hash3(i + vec3<i32>(0, 0, 1));
    let g = hash3(i + vec3<i32>(1, 0, 1));
    let h = hash3(i + vec3<i32>(0, 1, 1));
    let k = hash3(i + vec3<i32>(1, 1, 1));
    let k1 = b - a;
    let k2 = c - a;
    let k3 = e - a;
    let k4 = a - b - c + d;
    let k5 = a - c - e + h;
    let k6 = a - b - e + g;
    let k7 = -a + b + c - d + e - g - h + k;
    let v = a + k1 * u.x + k2 * u.y + k3 * u.z + k4 * u.x * u.y + k5 * u.y * u.z + k6 * u.z * u.x + k7 * u.x * u.y * u.z;
    let grad = du * vec3<f32>(
        k1 + k4 * u.y + k6 * u.z + k7 * u.y * u.z,
        k2 + k5 * u.z + k4 * u.x + k7 * u.z * u.x,
        k3 + k6 * u.x + k5 * u.y + k7 * u.x * u.y);
    return vec4<f32>(v, grad);
}

// Gradientenrauschen mit Steigung: (Wert, d/dx, d/dy, d/dz), Wert etwa -0,7..0,7.
// Runder und ohne die kantigen Gitterspuren von vnoise, deshalb fuer Wasserwellen.
fn gnoise_corner(i: vec3<i32>, w: vec3<f32>) -> vec4<f32> {
    let h = hash3(i);
    let ang = h * 6.2831853;
    let z = fract(h * 37.0) * 2.0 - 1.0;
    let r = sqrt(max(1.0 - z * z, 0.0));
    let g = vec3<f32>(r * cos(ang), r * sin(ang), z);
    return vec4<f32>(dot(g, w), g);
}

fn gnoise_d(p: vec3<f32>) -> vec4<f32> {
    let fl = floor(p);
    let i = vec3<i32>(fl);
    let w = p - fl;
    let u = w * w * w * (w * (w * 6.0 - 15.0) + 10.0);
    let du = 30.0 * w * w * (w * (w - 2.0) + 1.0);
    let a = gnoise_corner(i, w);
    let b = gnoise_corner(i + vec3<i32>(1, 0, 0), w - vec3<f32>(1.0, 0.0, 0.0));
    let c = gnoise_corner(i + vec3<i32>(0, 1, 0), w - vec3<f32>(0.0, 1.0, 0.0));
    let d = gnoise_corner(i + vec3<i32>(1, 1, 0), w - vec3<f32>(1.0, 1.0, 0.0));
    let e = gnoise_corner(i + vec3<i32>(0, 0, 1), w - vec3<f32>(0.0, 0.0, 1.0));
    let f = gnoise_corner(i + vec3<i32>(1, 0, 1), w - vec3<f32>(1.0, 0.0, 1.0));
    let g = gnoise_corner(i + vec3<i32>(0, 1, 1), w - vec3<f32>(0.0, 1.0, 1.0));
    let h = gnoise_corner(i + vec3<i32>(1, 1, 1), w - vec3<f32>(1.0, 1.0, 1.0));
    // Werte (x) und Gradienten (yzw) gleich trilinear mischen.
    let k1 = b - a;
    let k2 = c - a;
    let k3 = e - a;
    let k4 = a - b - c + d;
    let k5 = a - c - e + g;
    let k6 = a - b - e + f;
    let k7 = -a + b + c - d + e - f - g + h;
    let m = a + k1 * u.x + k2 * u.y + k3 * u.z + k4 * u.x * u.y + k5 * u.y * u.z + k6 * u.z * u.x + k7 * u.x * u.y * u.z;
    let slope = m.yzw + du * vec3<f32>(
        k1.x + k4.x * u.y + k6.x * u.z + k7.x * u.y * u.z,
        k2.x + k5.x * u.z + k4.x * u.x + k7.x * u.z * u.x,
        k3.x + k6.x * u.x + k5.x * u.y + k7.x * u.x * u.y);
    return vec4<f32>(m.x, slope);
}

// Dichte der Wolkenschicht am Weltpunkt `pw`.
fn cloud_density(pw: vec3<f32>, detail: bool) -> f32 {
    let hf = (pw.y - C_BOTTOM) / (C_TOP - C_BOTTOM);
    if hf <= 0.0 || hf >= 1.0 {
        return 0.0;
    }
    let wind = vec3<f32>(frame.time * 4.0, 0.0, frame.time * 1.5);
    let q = (pw + wind) * vec3<f32>(0.0095, 0.0130, 0.0095);
    let base = vnoise(q) * 0.55 + vnoise(q * 2.03 + 3.1) * 0.30 + vnoise(q * 4.07 + 7.7) * 0.15;

    // Flacher Boden, runde Koepfe.
    let profile = smoothstep(0.0, 0.10, hf) * (1.0 - smoothstep(0.30, 1.0, hf));
    let cov = mix(0.30, 0.75, cloud_amount) + frame.rain * 0.2;
    var dens = (base - (1.0 - cov) - (1.0 - profile) * 0.45) * 4.5;
    if dens <= 0.0 {
        return 0.0;
    }
    if detail {
        // Ausgefranste, fluffige Raender.
        let fine = vnoise(q * 9.0) * 0.6 + vnoise(q * 19.0 + 5.3) * 0.4;
        dens -= fine * 0.75 * sqrt(1.0 - clamp(dens, 0.0, 1.0) * 0.9);
    }
    return clamp(dens, 0.0, 1.0);
}

// Richtung zur Lichtquelle der Schattenkarte (Sonne bei Tag, Mond bei Nacht).
fn light_dir() -> vec3<f32> {
    if frame.has_shadow == 1u {
        return frame.light_direction;
    }
    return select(frame.moon_direction, frame.sun_direction, frame.sun_direction.y > 0.0);
}

// Ist die Kamera unter Wasser? `eye_in` meldet das nicht in jeder Horizon-Version,
// deshalb auch ueber die Wasserebene der Spiegelung.
fn camera_underwater() -> bool {
    return frame.eye_in == 1u || frame.in_water > 0.5
        || (frame.has_reflection == 1u && frame.camera_position.y < frame.water_plane - 0.05);
}

// Lichtmuster unter Wasser (Kaustiken): zwei verschobene Schichten, scharfe helle Linien.
fn caustics(world: vec3<f32>) -> f32 {
    let t = frame.time * 0.7;
    var sum = 0.0;
    for (var i = 0; i < 2; i++) {
        let s = 1.1 + f32(i) * 0.73;
        let p = world.xz * s + vec2<f32>(f32(i) * 3.7, f32(i) * 1.3);
        let a = sin(p.x + sin(p.y * 0.7 + t) * 1.3 + t * 0.6);
        let b = sin(p.y * 1.1 + sin(p.x * 0.8 - t * 0.9) * 1.3 - t * 0.5);
        sum += pow(clamp(1.0 - abs(a + b) * 0.5, 0.0, 1.0), 6.0);
    }
    return 0.5 + 0.8 * sum;
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

// Der Himmel im End: tiefer Weltraum mit einem grossen, langsam wabernden Nebel in
// Magenta und Blau, hellen Kernen, dunklen Staubbahnen und vielen Sternen. Unten
// leuchtet die Leere violett. Bildschirmfarben.
fn end_space(d: vec3<f32>) -> vec3<f32> {
    let t = frame.time * 0.004;
    let q = d * 2.2;
    let warp = vec3<f32>(vnoise(q + vec3<f32>(t, 0.0, 0.0)), vnoise(q + vec3<f32>(5.2, 1.3, t)), vnoise(q + vec3<f32>(2.1, 7.7, 3.3))) - 0.5;
    let p = d * 3.0 + warp * 1.6;
    let n = vnoise(p) * 0.5 + vnoise(p * 2.1) * 0.3 + vnoise(p * 4.3) * 0.2;
    let off = dot(d, normalize(vec3<f32>(0.35, 0.2, 0.92)));
    let band = exp(-off * off * 2.0);
    let cloud = smoothstep(0.36, 0.78, n) * (0.4 + 0.6 * band);
    let hue = vnoise(p * 0.7 + 9.0);
    let tint = mix(vec3<f32>(0.5, 0.12, 0.55), vec3<f32>(0.15, 0.25, 0.65), hue);
    let core = smoothstep(0.58, 0.86, n) * band;
    var col = vec3<f32>(0.012, 0.006, 0.025) + tint * cloud * 1.25 + vec3<f32>(0.95, 0.65, 1.0) * core * 0.55;
    col *= 1.0 - smoothstep(0.55, 0.8, vnoise(p * 1.7 + 3.0)) * 0.55 * band;
    col += stars(d, band) * 0.9;
    col += vec3<f32>(0.25, 0.08, 0.35) * smoothstep(0.0, -0.6, d.y) * 0.5;
    return min(col, vec3<f32>(1.0));
}
