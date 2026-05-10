struct CameraUniform {
    view: mat4x4<f32>,
    view_proj: mat4x4<f32>,
};

@group(0) @binding(0)
var<uniform> camera: CameraUniform;


struct VertexInput {
    @location(0) offset: vec2<f32>,
    @location(1) pos: vec3<f32>,
    @location(2) vel: vec3<f32>,
    @location(3) life: f32,
};

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) life: f32
};

@vertex
fn vs_main(input: VertexInput) -> VertexOutput {
    var out: VertexOutput;
    let right = vec3<f32>(camera.view[0].x, camera.view[1].x, camera.view[2].x);
    let up    = vec3<f32>(camera.view[0].y, camera.view[1].y, camera.view[2].y);
    let t = clamp(input.life / 6.0, 0.0, 1.0);
    let size = mix(1.0, 0.05, sqrt(t));
    let world = input.pos + right * input.offset.x * size + up * input.offset.y * size;
    out.clip_position = camera.view_proj * vec4<f32>(world, 1);
    out.life = input.life;
    return out;
}

@fragment
fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
let t = clamp(input.life / 6.0, 0.0, 1.0);

// keeps ember phase long
let x = pow(t, 1.6);

var color: vec3<f32>;

if (x < 0.04) {

    // very quick smooth white -> yellow
    let k = smoothstep(0.0, 0.04, x);

    color = mix(
        vec3(4.0, 4.0, 4.0),
        vec3(4.0, 3.2, 0.6),
        k
    );

} else if (x < 0.20) {

    // yellow -> orange
    let k = smoothstep(0.04, 0.20, x);

    color = mix(
        vec3(4.0, 3.2, 0.6),
        vec3(3.0, 1.2, 0.1),
        k
    );

} else if (x < 0.65) {

    // orange -> deep red
    let k = smoothstep(0.20, 0.65, x);

    color = mix(
        vec3(3.0, 1.2, 0.1),
        vec3(1.0, 0.08, 0.0),
        k
    );

} else {

    // red -> ash
    let k = smoothstep(0.65, 1.0, x);

    color = mix(
        vec3(1.0, 0.08, 0.0),
        vec3(0.15, 0.15, 0.15),
        k
    );
}
    return vec4<f32>(normalize(color), 1.0);
}