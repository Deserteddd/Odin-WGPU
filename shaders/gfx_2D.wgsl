struct VertexInput {
    @location(0) position: vec3<f32>,
    @location(1) uv: vec2<f32>,
};

struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
    @location(0) uv: vec2<f32>,
};

@vertex
fn vs_main(model: VertexInput) -> VertexOutput {
    var out: VertexOutput;
    out.uv = model.uv;
    out.clip_position = vec4<f32>(model.position, 1);
    return out;
}

@group(0) @binding(0)
var t_diffuse: texture_depth_2d;

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    let texel = vec2<i32>(in.clip_position.xy);
    let depth = textureLoad(t_diffuse, texel, 0) / 2;
    return vec4<f32>(depth, depth, depth, 1.0);
}

