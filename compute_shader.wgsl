const G: f32 = 9.81;
const FRICTION: f32 = 2.0;
const DRAG: f32 = 3;

struct Particle {
    pos: vec3<f32>,
    vel: vec3<f32>,
    life: f32,
};

@group(0) @binding(0) var<storage, read_write> particles: array<Particle>;
@group(0) @binding(1) var<uniform> dt: f32;

// Tells wgpu that this function is a valid compute pipeline entry_point
@compute
// Specifies the "dimension" of this work group
@workgroup_size(64)
fn main(
    // global_invocation_id specifies our position in the invocation grid
    @builtin(global_invocation_id) global_invocation_id: vec3<u32>
) {
    let index = global_invocation_id.x;
    let total = arrayLength(&particles);

    // workgroup_size may not be a multiple of the array size so
    // we need to exit out a thread that would index out of bounds.
    if (index >= total) {
        return;
    }

    let idx = global_invocation_id.x;
    let p = &particles[idx];

    p.life += dt;

    // Gravity
    if p.pos.y > 0.0 || p.vel.y > 0.0 {
        p.vel.y -= G * dt;
    }

    // Apply drag everywhere (air + ground)
    if p.vel.y > 0 {
        let drag = exp(-DRAG * dt);
        p.vel *= drag;
    }

    // Ground collision
    if p.pos.y <= 0.0 {
        p.pos.y = 0.0;

        // Stop downward motion
        if p.vel.y < 0.0 {
            p.vel.y = 0.0;
        }

        // Ground friction only affects horizontal motion
        let friction = exp(-FRICTION * dt);
        p.vel.x *= friction;
        p.vel.z *= friction;
    }

    // Integrate position
    p.pos += p.vel * dt;

    // Final ground clamp
    if p.pos.y < 0.0 {
        p.pos.y = 0.0;
        p.vel.y = 0.0;
    }
}