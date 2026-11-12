// Wehende Pflanzen: Blaetter, Gras, Blumen, Ranken und Wasserpflanzen bewegen
// sich im Wind. Die Bewegung haengt nur von der Weltposition ab, so bleiben
// Ecken, die sich zwei Bloecke teilen, zusammen (keine Luecken in Baumkronen),
// und die Schatten wehen mit.

override waving: f32 = 1.0;

// Material-Ids aus horizon-shaders.toml.
const M_LEAVES: u32 = 1u;
const M_PLANT: u32 = 2u;
const M_TALL_LOWER: u32 = 3u;
const M_TALL_UPPER: u32 = 4u;
const M_HANGING: u32 = 5u;
const M_SEA_PLANT: u32 = 6u;
const M_SEA_UPPER: u32 = 7u;
const M_KELP: u32 = 8u;
const M_LILY: u32 = 9u;
// Glaenzende Bloecke (nur material.wgsl).
const M_ICE: u32 = 10u;
const M_METAL: u32 = 11u;
const M_SNOW: u32 = 12u;
const M_POLISHED: u32 = 13u;
const M_GLASS: u32 = 14u;

fn wind_offset(world: vec3<f32>, speed: f32) -> vec3<f32> {
    let t = frame.time * speed;
    // Langsame Boeen, die ueber die Landschaft ziehen, plus schnelles Zittern.
    let gust = 0.65 + 0.35 * sin(t * 0.35 + world.x * 0.045 + world.z * 0.03);
    let x = sin(t * 1.30 + world.x * 0.55 + world.z * 0.20) * 0.70 + sin(t * 2.90 + world.z * 1.10 + world.y * 0.4) * 0.30;
    let z = sin(t * 1.10 + world.z * 0.50 - world.x * 0.25 + 1.7) * 0.60 + sin(t * 3.30 + world.x * 0.90) * 0.25;
    let y = sin(t * 2.20 + world.x * 0.70 + world.z * 0.70) * 0.20;
    return vec3<f32>(x, y, z) * gust;
}

fn vertex(input: VertexInput) -> vec3<f32> {
    if waving <= 0.0 || input.material == 0u || input.material > M_LILY {
        return input.position;
    }
    let world = input.position + frame.camera_position;
    // Unter freiem Himmel staerker, in Hoehlen und Haeusern kaum. Blaetter
    // immer gleich, damit sich die Ecken benachbarter Bloecke nicht trennen.
    let sheltered = mix(0.25, 1.0, smoothstep(0.4, 0.9, input.light.y));
    let open_air = select(sheltered, 1.0, input.material == M_LEAVES);
    let storm = 1.0 + frame.rain * 0.5 + frame.thunder * 0.6;
    let strength = waving * open_air * storm;
    // 0 an der Unterkante des Sprites, 1 an der Oberkante.
    let top = clamp(1.0 - input.uv.y, 0.0, 1.0);

    var amount = 0.0;
    var speed = 1.0;
    switch input.material {
        case 1u: { amount = 0.045; }
        case 2u: { amount = 0.12 * top; }
        case 3u: { amount = 0.10 * top; }
        case 4u: { amount = 0.10 * (1.0 + top); }
        case 5u: { amount = 0.05; }
        case 6u: { amount = 0.10 * top; speed = 0.6; }
        case 7u: { amount = 0.10 * (1.0 + top); speed = 0.6; }
        case 8u: { amount = 0.07; speed = 0.6; }
        default: {
            // Seerosen schaukeln nur leicht auf und ab.
            let bob = sin(frame.time * 1.4 + world.x * 0.8 + world.z * 0.6) * 0.015 * waving;
            return input.position + vec3<f32>(0.0, bob, 0.0);
        }
    }
    return input.position + wind_offset(world, speed) * amount * strength;
}
