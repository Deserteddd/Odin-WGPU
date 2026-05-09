package odin_wgpu

import "core:fmt"
import "vendor:wgpu"
import "core:math/linalg"


gfx_shader      :: #load("gfx_shader.wgsl")
compute_shader  :: #load("compute_shader.wgsl")
particle_shader :: #load("particle_shader.wgsl")

Renderer :: struct {
	instance:                   wgpu.Instance,
	surface:                    wgpu.Surface,
	adapter:                    wgpu.Adapter,
	device:                     wgpu.Device,
	config:                     wgpu.SurfaceConfiguration,
	queue:                      wgpu.Queue,

	gfx_module:                 wgpu.ShaderModule,
	gfx_pipeline_layout:        wgpu.PipelineLayout,
	gfx_pipeline:               wgpu.RenderPipeline,
	particle_module:            wgpu.ShaderModule,
	particle_pipeline_layout:   wgpu.PipelineLayout,
	particle_pipeline:          wgpu.RenderPipeline,
    vbo:                        wgpu.Buffer,
	quad_vbo:                   wgpu.Buffer,
    ubo:                        wgpu.Buffer,
    ubo_bind_group:             wgpu.BindGroup,

    compute_module:             wgpu.ShaderModule,
    compute_ubo:                wgpu.Buffer,
    compute_pipeline:           wgpu.ComputePipeline,
    compute_bind_group:         wgpu.BindGroup,
    particle_buffer:            wgpu.Buffer,


    curr_pass:                  wgpu.RenderPassEncoder,
    curr_encoder:               wgpu.CommandEncoder,
    curr_texture:               wgpu.SurfaceTexture,
    curr_view:                  wgpu.TextureView
}



vec4 :: [4]f32
vec3 :: [3]f32
vec2 :: [2]f32

CameraUniform :: struct {
	view: linalg.Matrix4x4f32,
	view_proj: linalg.Matrix4x4f32,
}

Particle :: struct {
    pos: vec3,
    _pad: f32,
    vel: vec3,
    life: f32,
}

QuadVertex :: struct {
	offset: vec2,
}

Vertex :: struct {
    pos: vec3,
    col: vec3,
}

on_adapter :: proc "c" (status: wgpu.RequestAdapterStatus, adapter: wgpu.Adapter, message: string, userdata1: rawptr, userdata2: rawptr) {
    context = g.ctx
    if status != .Success || adapter == nil {
        fmt.panicf("request adapter failure: [%v] %s", status, message)
    }
    g.r.adapter = adapter
    wgpu.AdapterRequestDevice(adapter, nil, { callback = on_device })
}

on_device :: proc "c" (status: wgpu.RequestDeviceStatus, device: wgpu.Device, message: string, userdata1: rawptr, userdata2: rawptr) {
    context = g.ctx
    r := &g.r
    if status != .Success || device == nil {
        fmt.panicf("request device failure: [%v] %s", status, message)
    }
    r.device = device 

    r.queue = wgpu.DeviceGetQueue(r.device)

    width, height := os_get_framebuffer_size()

    r.config = wgpu.SurfaceConfiguration {
        device      = r.device,
        usage       = { .RenderAttachment },
        format      = .BGRA8Unorm,
        width       = width,
        height      = height,
        presentMode = .Fifo,
        alphaMode   = .Opaque,
    }
    setup_gfx()
    create_grid(12)
    create_particles()
    setup_compute()
    create_orbital_camera()

    os_run()
}

setup_gfx :: proc() {
    r := &g.r
    wgpu.SurfaceConfigure(r.surface, &r.config)
    
	r.gfx_module = wgpu.DeviceCreateShaderModule(r.device, &{
		label = "GFX module",
		nextInChain = &wgpu.ShaderSourceWGSL{
			sType = .ShaderSourceWGSL,
			code  = string(gfx_shader),
		},
	})

    r.ubo = wgpu.DeviceCreateBufferWithDataTyped(r.device, &{
        label = "ubo",
        usage = {.Uniform, .CopyDst}
    }, CameraUniform{}
    ); assert(r.ubo != nil)

    ubo_bind_group_layout := wgpu.DeviceCreateBindGroupLayout(r.device, &{
        label = "ubo_bind_group_layout",
        entryCount = 1,
        entries = raw_data([]wgpu.BindGroupLayoutEntry{{
            binding = 0,
            visibility = {.Vertex},
            buffer = {
                type = .Uniform,
            }
        }})
    }); assert(ubo_bind_group_layout != nil)

    r.ubo_bind_group = wgpu.DeviceCreateBindGroup(r.device, &{
        label = "ubo_bind_group",
        layout = ubo_bind_group_layout,
        entryCount = 1,
        entries = raw_data([]wgpu.BindGroupEntry{{
            binding = 0,
            buffer = r.ubo,
            size = wgpu.BufferGetSize(r.ubo)
        }})
    }); assert(r.ubo_bind_group != nil)

    r.gfx_pipeline_layout = wgpu.DeviceCreatePipelineLayout(r.device, &{
        label = "Render pipeline layout",
        bindGroupLayoutCount = 1,
        bindGroupLayouts = raw_data([]wgpu.BindGroupLayout{ubo_bind_group_layout})
    }); assert(r.ubo_bind_group != nil)

    r.gfx_pipeline = wgpu.DeviceCreateRenderPipeline(r.device, &{
        layout = r.gfx_pipeline_layout,
        vertex = {
            module     = r.gfx_module,
            entryPoint = "vs_main",
            bufferCount = 1,
            buffers = raw_data([]wgpu.VertexBufferLayout{{
                stepMode = .Vertex,
                arrayStride = size_of(Vertex),
                attributeCount = 2,
                attributes = raw_data([]wgpu.VertexAttribute{
                    {format = .Float32x3, offset = 0, shaderLocation = 0},
                    {format = .Float32x3, offset = size_of(vec3), shaderLocation = 1}
                })
            }})
        },
        fragment = &{
            module      = r.gfx_module,
            entryPoint  = "fs_main",
            targetCount = 1,
            targets     = &wgpu.ColorTargetState{
                format    = .BGRA8Unorm,
                writeMask = wgpu.ColorWriteMaskFlags_All,
            },
        },
        primitive = {
            topology = .LineList,

        },
        multisample = {
            count = 1,
            mask  = 0xFFFFFFFF,
        },
    })

    r.particle_module = wgpu.DeviceCreateShaderModule(r.device, &{
        label = "Particle module",
        nextInChain = &wgpu.ShaderSourceWGSL{
            sType = .ShaderSourceWGSL,
            code  = string(particle_shader),
        },
    })

    r.particle_pipeline_layout = wgpu.DeviceCreatePipelineLayout(r.device, &{
        label = "Particle pipeline layout",
        bindGroupLayoutCount = 1,
        bindGroupLayouts = raw_data([]wgpu.BindGroupLayout{ubo_bind_group_layout})
    }); assert(r.particle_pipeline_layout != nil)

    r.particle_pipeline = wgpu.DeviceCreateRenderPipeline(r.device, &{
        layout = r.particle_pipeline_layout,
        vertex = {
            module     = r.particle_module,
            entryPoint = "vs_main",
            bufferCount = 2,
            buffers = raw_data([]wgpu.VertexBufferLayout{
                {
                    stepMode = .Vertex,
                    arrayStride = size_of(QuadVertex),
                    attributeCount = 1,
                    attributes = raw_data([]wgpu.VertexAttribute{
                        {format = .Float32x2, offset = 0, shaderLocation = 0},
                    }),
                },
                {
                    stepMode = .Instance,
                    arrayStride = size_of(Particle),
                    attributeCount = 3,
                    attributes = raw_data([]wgpu.VertexAttribute{
                        {format = .Float32x3, offset = 0, shaderLocation = 1},
                        {format = .Float32x3, offset = size_of(vec4), shaderLocation = 2},
                        {format = .Float32,   offset = size_of(vec4)+size_of(vec3), shaderLocation = 3},
                    }),
                },
            }),
        },
        fragment = &{
            module      = r.particle_module,
            entryPoint  = "fs_main",
            targetCount = 1,
            targets     = &wgpu.ColorTargetState{
                format    = .BGRA8Unorm,
                writeMask = wgpu.ColorWriteMaskFlags_All,
            },
        },
        primitive = {
            topology = .TriangleList,
        },
        multisample = {
            count = 1,
            mask  = 0xFFFFFFFF,
        },
    })

    quad_vertices := []QuadVertex{
        {offset = {-0.5, -0.5}},
        {offset = { 0.5, -0.5}},
        {offset = { 0.5,  0.5}},
        {offset = {-0.5, -0.5}},
        {offset = { 0.5,  0.5}},
        {offset = {-0.5,  0.5}},
    }

    r.quad_vbo = wgpu.DeviceCreateBufferWithDataSlice(r.device, &{
        label = "Particle quad buf",
        usage = {.Vertex}
    }, quad_vertices[:]); assert(r.quad_vbo != nil)
}

setup_compute :: proc() {
    r := &g.r
    r.compute_module = wgpu.DeviceCreateShaderModule(r.device, &{
        label = "Compute module",
        nextInChain = &wgpu.ShaderSourceWGSL{
            sType = .ShaderSourceWGSL,
            code  = string(compute_shader),
        },
    })

    r.compute_pipeline = wgpu.DeviceCreateComputePipeline(r.device, &{
        label = "Compute pipeline",
        compute = {
            module = r.compute_module,
            entryPoint = "main"
        }
    })

    r.compute_ubo = wgpu.DeviceCreateBufferWithDataTyped(r.device, &{
        label = "compute_ubo",
        usage = {.Uniform, .CopyDst}
    }, f32(0)); assert(r.compute_ubo != nil)

    r.compute_bind_group = wgpu.DeviceCreateBindGroup(r.device, &{
        label = "Compute bind group",
        layout = wgpu.ComputePipelineGetBindGroupLayout(r.compute_pipeline, 0),
        entryCount = 2,
        entries = raw_data([]wgpu.BindGroupEntry{
            {
                binding = 0,
                offset = 0,
                size = wgpu.BufferGetSize(r.particle_buffer),
                buffer = r.particle_buffer,
            },
            {
                binding = 1,
                offset = 0,
                size = wgpu.BufferGetSize(r.compute_ubo),
                buffer = r.compute_ubo
            }
        })
    }); assert(r.compute_bind_group != nil)
}

r_run_compute :: proc(dt: f32) {
	r := &g.r
    dt := dt
    particle_count := u32(wgpu.BufferGetSize(g.r.particle_buffer) / size_of(Particle))
	workgroup_count := (particle_count + 63) / 64

	compute_pass := wgpu.CommandEncoderBeginComputePass(r.curr_encoder)

	wgpu.ComputePassEncoderSetPipeline(compute_pass, r.compute_pipeline)
	wgpu.QueueWriteBuffer(r.queue, r.compute_ubo, 0, &dt, size_of(f32))
	wgpu.ComputePassEncoderSetBindGroup(compute_pass, 0, r.compute_bind_group)
	wgpu.ComputePassEncoderDispatchWorkgroups(compute_pass, workgroup_count, 1, 1)

	wgpu.ComputePassEncoderEnd(compute_pass)
}



r_begin_frame :: proc() -> bool {
	r := &g.r

	r.curr_texture = wgpu.SurfaceGetCurrentTexture(r.surface)

	switch r.curr_texture.status {
        case .SuccessOptimal, .SuccessSuboptimal:
        // All good, could handle suboptimal here.
        case .Timeout, .Outdated, .Lost:
            if r.curr_texture.texture != nil {
                wgpu.TextureRelease(r.curr_texture.texture)
            }
            r_resize()
            return false
        case .OutOfMemory, .DeviceLost:
            // Window is occluded (e.g. minimized), skip this frame.
            return false
        case .Error:
            fmt.panicf("get_current_texture status=%v", r.curr_texture.status)
	}

	r.curr_view = wgpu.TextureCreateView(r.curr_texture.texture, nil)
	r.curr_encoder = wgpu.DeviceCreateCommandEncoder(r.device, nil)

	return true
}

r_resize :: proc() {
	r := &g.r

	width, height := os_get_framebuffer_size()
	r.config.width, r.config.height = width, height
	wgpu.SurfaceConfigure(r.surface, &r.config)
}


r_present :: proc() {
	r := &g.r

    wgpu.RenderPassEncoderEnd(r.curr_pass)
	wgpu.RenderPassEncoderRelease(r.curr_pass)

	command_buffer := wgpu.CommandEncoderFinish(r.curr_encoder, nil)
	defer wgpu.CommandBufferRelease(command_buffer)

    wgpu.CommandEncoderRelease(r.curr_encoder)

	wgpu.QueueSubmit(r.queue, { command_buffer })
	wgpu.SurfacePresent(r.surface)

	wgpu.TextureViewRelease(r.curr_view)
	wgpu.TextureRelease(r.curr_texture.texture)

}

r_draw_scene :: proc() {
	r := &g.r

	r.curr_pass = wgpu.CommandEncoderBeginRenderPass(r.curr_encoder, &{
		colorAttachmentCount = 1,
		colorAttachments = raw_data([]wgpu.RenderPassColorAttachment{
			{
				view = r.curr_view,
				loadOp = .Clear,
				storeOp = .Store,
				clearValue = {0.2, 0.2, 0.2, 1},
				depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
			},
		}),
	})

	wgpu.RenderPassEncoderSetPipeline(r.curr_pass, r.gfx_pipeline)

	proj := create_proj_matrix()
	view := camera_view_matrix()
	vp := proj * view
	ubo := CameraUniform{view = view, view_proj = vp}
	wgpu.QueueWriteBuffer(r.queue, r.ubo, 0, &ubo, size_of(ubo))

	wgpu.RenderPassEncoderSetBindGroup(r.curr_pass, 0, r.ubo_bind_group)
	wgpu.RenderPassEncoderSetVertexBuffer(r.curr_pass, 0, r.vbo, 0, wgpu.BufferGetSize(r.vbo))

	grid_vertex_count := u32(wgpu.BufferGetSize(r.vbo) / size_of(Vertex))
	wgpu.RenderPassEncoderDraw(r.curr_pass, grid_vertex_count, instanceCount=1, firstVertex=0, firstInstance=0)

    particle_count := u32(wgpu.BufferGetSize(g.r.particle_buffer) / size_of(Particle))
	wgpu.RenderPassEncoderSetPipeline(r.curr_pass, r.particle_pipeline)
	wgpu.RenderPassEncoderSetVertexBuffer(r.curr_pass, 0, r.quad_vbo, 0, wgpu.BufferGetSize(r.quad_vbo))
	wgpu.RenderPassEncoderSetVertexBuffer(r.curr_pass, 1, r.particle_buffer, 0, wgpu.BufferGetSize(r.particle_buffer))
	wgpu.RenderPassEncoderDraw(r.curr_pass, 6, instanceCount=particle_count, firstVertex=0, firstInstance=0)
}
