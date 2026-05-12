struct CameraUniform {
    view: mat4x4<f32>,
    view_proj: mat4x4<f32>,
    cam_pos: vec3<f32>,
    _pad: f32,
};

@group(0) @binding(0)
var<uniform> camera: CameraUniform;


struct VertexInput {
    @location(0) offset: vec3<f32>,
    @location(1) normal: vec3<f32>,
    @location(2) pos: vec3<f32>,
    @location(3) vel: vec3<f32>,
    @location(4) life: f32,
};

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) life: f32,
    @location(1) v_pos: vec3<f32>,
    @location(2) v_normal: vec3<f32>,
};

@vertex
fn vs_main(input: VertexInput) -> VertexOutput {
    var out: VertexOutput;
    let world = input.pos + input.offset;
    out.clip_position = camera.view_proj * vec4<f32>(world, 1);
    out.life = input.life;
    out.v_pos = world;
    out.v_normal = input.normal;
    return out;
}

@fragment
fn fs_main(input: VertexOutput) -> @location(0) vec4<f32> {
    let p = normalize(input.v_pos);

    let color = vec3<f32>(
        0.5 + 0.5 * sin(p.x * 2.0),
        0.5 + 0.5 * sin(p.y * 2.0 + 2.0),
        0.5 + 0.5 * sin(p.z * 2.0 + 4.0)
    );

    return vec4<f32>(color, 1.0);
}