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
    let size = 0.03;
    let world = input.pos + right * input.offset.x * size + up * input.offset.y * size;
    out.clip_position = camera.view_proj * vec4<f32>(world, 1);
    out.life = input.life;
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    return vec4<f32>(in.life, 0.0, 0.0, 1.0);
}