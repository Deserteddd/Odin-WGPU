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

    particles[idx].pos += particles[idx].vel * dt;
}