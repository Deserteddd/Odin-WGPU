struct Particle {
    pos: vec3<f32>,
    _pad: f32,
};

@group(0) @binding(0) var<storage, read_write> particles: array<Particle>;

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
    let angle = 0.003;
    let s = sin(angle);
    let c = cos(angle);
    let x = particles[idx].pos.x;
    let z = particles[idx].pos.z;
    particles[idx].pos.x = x * c - z * s;
    particles[idx].pos.z = x * s + z * c;
}