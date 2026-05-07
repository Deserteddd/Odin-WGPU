package odin_wgpu

import "base:runtime"
import "core:fmt"
import "vendor:wgpu"
import "core:math/linalg"

gfx_shader     :: #load("gfx_shader.wgsl")
compute_shader :: #load("compute_shader.wgsl")

state: struct {
	ctx:                        runtime.Context,
	os:                         OS,
    time_accum:                 f32,
    mouse_delta:                [2]i32,
    lmb_down:                   bool,
    camera:                     Camera,

	instance:                   wgpu.Instance,
	surface:                    wgpu.Surface,
	adapter:                    wgpu.Adapter,
	device:                     wgpu.Device,
	config:                     wgpu.SurfaceConfiguration,
	queue:                      wgpu.Queue,

	gfx_module:                 wgpu.ShaderModule,
	gfx_pipeline_layout:        wgpu.PipelineLayout,
	gfx_pipeline:               wgpu.RenderPipeline,
    vbo:                        wgpu.Buffer,
    ubo:                        wgpu.Buffer,
    ubo_bind_group:             wgpu.BindGroup,

    compute_module:             wgpu.ShaderModule,
    compute_pipeline:           wgpu.ComputePipeline,
    compute_input_buffer:       wgpu.Buffer,
    compute_output_buffer:      wgpu.Buffer,
    compute_temp_buffer:        wgpu.Buffer,
    compute_bind_group:         wgpu.BindGroup,
    compute_readback:           ComputeReadback

}

ComputeReadback :: struct {
    pending: bool,
    ready:   bool,
    status:  wgpu.MapAsyncStatus,
}

vec4 :: [4]f32
vec3 :: [3]f32
vec2 :: [2]f32

Vertex :: struct {
    pos: vec3,
    col: vec3,
}

// Entry point: initialize OS bindings and kick off async WebGPU setup.
main :: proc() {
	state.ctx = context

	os_init()
	state.instance = wgpu.CreateInstance(nil)
	if state.instance == nil {
		panic("WebGPU is not supported")
	}
	state.surface = os_get_surface(state.instance)

	wgpu.InstanceRequestAdapter(state.instance, &{ compatibleSurface = state.surface }, { callback = on_adapter })

	on_adapter :: proc "c" (status: wgpu.RequestAdapterStatus, adapter: wgpu.Adapter, message: string, userdata1: rawptr, userdata2: rawptr) {
		context = state.ctx
		if status != .Success || adapter == nil {
			fmt.panicf("request adapter failure: [%v] %s", status, message)
		}
		state.adapter = adapter
		wgpu.AdapterRequestDevice(adapter, nil, { callback = on_device })
	}

	on_device :: proc "c" (status: wgpu.RequestDeviceStatus, device: wgpu.Device, message: string, userdata1: rawptr, userdata2: rawptr) {
		context = state.ctx
		if status != .Success || device == nil {
			fmt.panicf("request device failure: [%v] %s", status, message)
		}
		state.device = device 

		state.queue = wgpu.DeviceGetQueue(state.device)

		width, height := os_get_framebuffer_size()

		state.config = wgpu.SurfaceConfiguration {
			device      = state.device,
			usage       = { .RenderAttachment },
			format      = .BGRA8Unorm,
			width       = width,
			height      = height,
			presentMode = .Fifo,
			alphaMode   = .Opaque,
		}
        setup_gfx()
        setup_compute()
        create_grid(10)
        create_orbital_camera()




        run_compute()
		os_run()
	}

    setup_gfx :: proc() {
		wgpu.SurfaceConfigure(state.surface, &state.config)

		state.gfx_module = wgpu.DeviceCreateShaderModule(state.device, &{
            label = "GFX module",
			nextInChain = &wgpu.ShaderSourceWGSL{
				sType = .ShaderSourceWGSL,
				code  = string(gfx_shader),
			},
		})

        state.ubo = wgpu.DeviceCreateBufferWithDataTyped(state.device, &{
            label = "ubo",
            usage = {.Uniform, .CopyDst}
        }, linalg.matrix4_infinite_perspective(linalg.to_radians(f32(90)), f32(state.config.width/state.config.height), 0.1)
        ); assert(state.ubo != nil)

        ubo_bind_group_layout := wgpu.DeviceCreateBindGroupLayout(state.device, &{
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

        state.ubo_bind_group = wgpu.DeviceCreateBindGroup(state.device, &{
            label = "ubo_bind_group",
            layout = ubo_bind_group_layout,
			entryCount = 1,
			entries = raw_data([]wgpu.BindGroupEntry{{
                binding = 0,
                buffer = state.ubo,
                size = wgpu.BufferGetSize(state.ubo)
            }})
        }); assert(state.ubo_bind_group != nil)

		state.gfx_pipeline_layout = wgpu.DeviceCreatePipelineLayout(state.device, &{
            label = "Render pipeline layout",
            bindGroupLayoutCount = 1,
            bindGroupLayouts = raw_data([]wgpu.BindGroupLayout{ubo_bind_group_layout})
        }); assert(state.ubo_bind_group != nil)

		state.gfx_pipeline = wgpu.DeviceCreateRenderPipeline(state.device, &{
			layout = state.gfx_pipeline_layout,
			vertex = {
				module     = state.gfx_module,
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
				module      = state.gfx_module,
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
    }

    setup_compute :: proc() {
        state.compute_module = wgpu.DeviceCreateShaderModule(state.device, &{
            label = "Compute module",
            nextInChain = &wgpu.ShaderSourceWGSL{
				sType = .ShaderSourceWGSL,
				code  = string(compute_shader),
			},
        })

        state.compute_pipeline = wgpu.DeviceCreateComputePipeline(state.device, &{
            label = "Compute pipeline",
            compute = {
                module = state.compute_module,
                entryPoint = "main"
            }
        })

        input_data := []u32 {1, 2, 3, 4}
        state.compute_input_buffer = wgpu.DeviceCreateBufferWithDataSlice(state.device, &{
            label = "Input buffer",
            usage = {.CopyDst, .Storage}
        }, input_data)

        state.compute_output_buffer = wgpu.DeviceCreateBuffer(state.device, &{
            label = "Output buffer",
            size = wgpu.BufferGetSize(state.compute_input_buffer),
            usage = {.CopySrc, .Storage}
        })

        state.compute_temp_buffer = wgpu.DeviceCreateBuffer(state.device, &{
            label = "Temp buffer",
            size = wgpu.BufferGetSize(state.compute_input_buffer),
            usage = {.CopyDst, .MapRead}
        })

        state.compute_bind_group = wgpu.DeviceCreateBindGroup(state.device, &{
            label = "Compute bind group",
            layout = wgpu.ComputePipelineGetBindGroupLayout(state.compute_pipeline, 0),
            entryCount = 2,
            entries = raw_data([]wgpu.BindGroupEntry{
                {
                    binding = 0, 
                    offset = 0, 
                    size = wgpu.BufferGetSize(state.compute_input_buffer), 
                    buffer = state.compute_input_buffer
                },
                {
                    binding = 1, 
					offset = 0, 
                    size = wgpu.BufferGetSize(state.compute_output_buffer), 
                    buffer = state.compute_output_buffer
                },
            })
        })
    }
}

get_relative_mouse_movement :: proc() -> [2]i32 {
    delta := state.mouse_delta
    state.mouse_delta = 0
    return delta
}

create_grid :: proc(size: int) {
    vertices: [dynamic]Vertex
	half := size / 2
	for i in -half..=half {
		x := f32(i)
		z := f32(i)
		append(&vertices, Vertex {pos = {x, 0, f32(-half)}, col = {0.6, 0.6, 0.6}})
		append(&vertices, Vertex {pos = {x, 0, f32(half)},  col = {0.6, 0.6, 0.6}})

		append(&vertices, Vertex {pos = {f32(-half), 0, z}, col = {0.6, 0.6, 0.6}})
		append(&vertices, Vertex {pos = {f32(half), 0, z},  col = {0.6, 0.6, 0.6}})
	}

    state.vbo = wgpu.DeviceCreateBufferWithDataSlice(state.device, &{
        label = "Triangle buf",
        usage = {.Vertex}
    }, vertices[:]); assert(state.vbo != nil)
}

// Reconfigure the surface after a resize or swapchain loss.
resize :: proc "c" () {
	context = state.ctx
	state.config.width, state.config.height = os_get_framebuffer_size()
	wgpu.SurfaceConfigure(state.surface, &state.config)
}

run_compute :: proc() {
	state.ctx = context

	command_encoder := wgpu.DeviceCreateCommandEncoder(state.device, nil)
	defer wgpu.CommandEncoderRelease(command_encoder)

    compute_pass := wgpu.CommandEncoderBeginComputePass(command_encoder)

    wgpu.ComputePassEncoderSetPipeline(compute_pass, state.compute_pipeline)
    wgpu.ComputePassEncoderSetBindGroup(compute_pass, 0, state.compute_bind_group)
    wgpu.ComputePassEncoderDispatchWorkgroups(compute_pass, 4, 1, 1)


    wgpu.ComputePassEncoderEnd(compute_pass)
    wgpu.CommandEncoderCopyBufferToBuffer(
        command_encoder, 
        state.compute_output_buffer, 
        0, 
        state.compute_temp_buffer, 
        0,
        wgpu.BufferGetSize(state.compute_output_buffer)
    )
    cmd_buf := wgpu.CommandEncoderFinish(command_encoder)
    wgpu.QueueSubmit(state.queue, {cmd_buf})
    state.compute_readback.pending = true
    state.compute_readback.ready = false
    wgpu.QueueOnSubmittedWorkDone(state.queue, { callback = queue_done_callback })
}

map_callback :: proc "c" (status: wgpu.MapAsyncStatus, message: wgpu.StringView, userdata1: rawptr, userdata2: rawptr) {
    state.compute_readback.status = status
    state.compute_readback.ready = true
}

maybe_consume_compute_result :: proc() -> bool {
    if !state.compute_readback.ready do return false
    state.compute_readback.ready = false

    if state.compute_readback.status != .Success {
        fmt.eprintfln("map failed: %v", state.compute_readback.status)
        return true
    }

    size := wgpu.BufferGetSize(state.compute_temp_buffer)
    ptr := wgpu.RawBufferGetConstMappedRange(state.compute_temp_buffer, 0, uint(size))
    count := int(size / size_of(u32))
    output := ([^]u32)(ptr)[:count]

    fmt.println(output) // or validate
    wgpu.BufferUnmap(state.compute_temp_buffer)
    state.compute_readback.pending = false
    return true
}
queue_done_callback :: proc "c" (status: wgpu.QueueWorkDoneStatus, userdata1: rawptr, userdata2: rawptr) {
    if status != .Success {
        state.compute_readback.status = .Error
        state.compute_readback.ready = true
        return
    }

    // Map after the GPU finished writing.
    wgpu.BufferMapAsync(
        state.compute_temp_buffer,
        { .Read },
        0,
        uint(wgpu.BufferGetSize(state.compute_temp_buffer)),
        {
            mode = .AllowProcessEvents, // Mode is ignored in wgpu.js, but ok to set.
            callback = map_callback,
        },
    )
}

update :: proc() {
    maybe_consume_compute_result()
    if state.lmb_down do update_camera()
    state.mouse_delta = 0;
}

// Render one frame: acquire surface texture, encode commands, submit, present.
draw :: proc(dt: f32) {
    state.time_accum += dt
	surface_texture := wgpu.SurfaceGetCurrentTexture(state.surface)
	switch surface_texture.status {
	case .SuccessOptimal, .SuccessSuboptimal:
		// All good, could handle suboptimal here.
	case .Timeout, .Outdated, .Lost:
		// Skip this frame, and re-configure surface.
		if surface_texture.texture != nil {
			wgpu.TextureRelease(surface_texture.texture)
		}
		resize()
		return
	case .Error, .OutOfMemory, .DeviceLost:
		// Fatal error
		fmt.panicf("[triangle] get_current_texture status=%v", surface_texture.status)
	}
	defer wgpu.TextureRelease(surface_texture.texture)

	frame := wgpu.TextureCreateView(surface_texture.texture, nil)
	defer wgpu.TextureViewRelease(frame)

	command_encoder := wgpu.DeviceCreateCommandEncoder(state.device, nil)
	defer wgpu.CommandEncoderRelease(command_encoder)

	render_pass_encoder := wgpu.CommandEncoderBeginRenderPass(
		command_encoder, &{
			colorAttachmentCount = 1,
			colorAttachments     = &wgpu.RenderPassColorAttachment{
				view       = frame,
				loadOp     = .Clear,
				storeOp    = .Store,
				depthSlice = wgpu.DEPTH_SLICE_UNDEFINED,
				clearValue = { 0.2, 0.2, 0.2, 1 },
			},
		},
	)

	wgpu.RenderPassEncoderSetPipeline(render_pass_encoder, state.gfx_pipeline)

    proj := create_proj_matrix()
    view := camera_view_matrix(state.camera)
    vp := proj * view
    wgpu.QueueWriteBuffer(state.queue, state.ubo, 0, &vp, size_of(vp))

    wgpu.RenderPassEncoderSetBindGroup(render_pass_encoder, 0, state.ubo_bind_group)
    wgpu.RenderPassEncoderSetVertexBuffer(render_pass_encoder, 0, state.vbo, 0, wgpu.BufferGetSize(state.vbo))

    vertex_count := u32(wgpu.BufferGetSize(state.vbo) / size_of(Vertex))
	wgpu.RenderPassEncoderDraw(render_pass_encoder, vertex_count, instanceCount=1, firstVertex=0, firstInstance=0)

	wgpu.RenderPassEncoderEnd(render_pass_encoder)
	wgpu.RenderPassEncoderRelease(render_pass_encoder)

	command_buffer := wgpu.CommandEncoderFinish(command_encoder, nil)
	defer wgpu.CommandBufferRelease(command_buffer)

	wgpu.QueueSubmit(state.queue, { command_buffer })
	wgpu.SurfacePresent(state.surface)
}

// Release all GPU resources in reverse creation order.
finish :: proc() {
	wgpu.RenderPipelineRelease(state.gfx_pipeline)
	wgpu.ComputePipelineRelease(state.compute_pipeline)
	wgpu.PipelineLayoutRelease(state.gfx_pipeline_layout)
	wgpu.ShaderModuleRelease(state.gfx_module)
	wgpu.ShaderModuleRelease(state.compute_module)
	wgpu.QueueRelease(state.queue)
	wgpu.DeviceRelease(state.device)
	wgpu.AdapterRelease(state.adapter)
	wgpu.SurfaceRelease(state.surface)
	wgpu.InstanceRelease(state.instance)
}


