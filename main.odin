package odin_wgpu

import "base:runtime"
import "core:fmt"
import "vendor:wgpu"
import "core:math/linalg"

shader :: #load("shader.wgsl")

state: struct {
	ctx: runtime.Context,
	os:  OS,
    time_accum:      f32,
	instance:        wgpu.Instance,
	surface:         wgpu.Surface,
	adapter:         wgpu.Adapter,
	device:          wgpu.Device,
	config:          wgpu.SurfaceConfiguration,
	queue:           wgpu.Queue,
	module:          wgpu.ShaderModule,
	pipeline_layout: wgpu.PipelineLayout,
	pipeline:        wgpu.RenderPipeline,
    vbo:             wgpu.Buffer,
    ubo:             wgpu.Buffer,
    ubo_bind_group:  wgpu.BindGroup,
}

vec4 :: [4]f32
vec3 :: [3]f32
vec2 :: [2]f32

Vertex :: struct {
    pos: vec2,
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
        fmt.println("on_adapter called")
		if status != .Success || adapter == nil {
			fmt.panicf("request adapter failure: [%v] %s", status, message)
		}
		state.adapter = adapter
		wgpu.AdapterRequestDevice(adapter, nil, { callback = on_device })
	}

	on_device :: proc "c" (status: wgpu.RequestDeviceStatus, device: wgpu.Device, message: string, userdata1: rawptr, userdata2: rawptr) {
		context = state.ctx
        fmt.println("on_device called")
		if status != .Success || device == nil {
			fmt.panicf("request device failure: [%v] %s", status, message)
		}
		state.device = device 

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
		wgpu.SurfaceConfigure(state.surface, &state.config)

		state.queue = wgpu.DeviceGetQueue(state.device)

		state.module = wgpu.DeviceCreateShaderModule(state.device, &{
			nextInChain = &wgpu.ShaderSourceWGSL{
				sType = .ShaderSourceWGSL,
				code  = string(shader),
			},
		})

        vertices: []Vertex = {
            {{0.0, 0.5}, {1, 0, 0}},
            {{0.5, -0.5}, {0, 1, 0}},
            {{-0.5, -0.5}, {0, 0, 1}},
        }

        state.vbo = wgpu.DeviceCreateBufferWithDataSlice(state.device, &{
            label = "Triangle buf",
            usage = {.Vertex}
        }, vertices); assert(state.vbo != nil)

        state.ubo = wgpu.DeviceCreateBufferWithDataTyped(state.device, &{
            label = "ubo",
            usage = {.Uniform, .CopyDst}
        }, linalg.matrix4_infinite_perspective(linalg.to_radians(f32(90)), f32(width/height), 0.1)
        ); assert(state.ubo != nil)

        ubo_bind_group_layout := wgpu.DeviceCreateBindGroupLayout(device, &{
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

		state.pipeline_layout = wgpu.DeviceCreatePipelineLayout(state.device, &{
            label = "Render pipeline layout",
            bindGroupLayoutCount = 1,
            bindGroupLayouts = raw_data([]wgpu.BindGroupLayout{ubo_bind_group_layout})
        }); assert(state.ubo_bind_group != nil)

		state.pipeline = wgpu.DeviceCreateRenderPipeline(state.device, &{
			layout = state.pipeline_layout,
			vertex = {
				module     = state.module,
				entryPoint = "vs_main",
                bufferCount = 1,
                buffers = raw_data([]wgpu.VertexBufferLayout{{
                    stepMode = .Vertex,
                    arrayStride = size_of(Vertex),
                    attributeCount = 2,
                    attributes = raw_data([]wgpu.VertexAttribute{
                        {format = .Float32x2, offset = 0, shaderLocation = 0},
                        {format = .Float32x3, offset = size_of(vec2), shaderLocation = 1}
                    })
                }})
			},
			fragment = &{
				module      = state.module,
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


		os_run()
	}
}


// Reconfigure the surface after a resize or swapchain loss.
resize :: proc "c" () {
	context = state.ctx
	state.config.width, state.config.height = os_get_framebuffer_size()
	wgpu.SurfaceConfigure(state.surface, &state.config)
    aspect := f32(state.config.width) / f32(state.config.height)
    proj := linalg.matrix4_infinite_perspective_f32(linalg.to_radians(f32(90)), aspect, 0.01)
    wgpu.QueueWriteBuffer(state.queue, state.ubo, 0, &proj, size_of(proj))
}

// Render one frame: acquire surface texture, encode commands, submit, present.
draw :: proc "c" (dt: f32) {
	context = state.ctx
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
				clearValue = { 0.3, 0.2, 0.2, 1 },
			},
		},
	)
	wgpu.RenderPassEncoderSetPipeline(render_pass_encoder, state.pipeline)
    aspect := f32(state.config.width) / f32(state.config.height)
    proj := linalg.matrix4_infinite_perspective_f32(linalg.to_radians(f32(90)), aspect, 0.01)
    proj *= linalg.matrix4_rotate(state.time_accum, vec3{0, 0, 1})
    wgpu.QueueWriteBuffer(state.queue, state.ubo, 0, &proj, size_of(proj))
    wgpu.RenderPassEncoderSetBindGroup(render_pass_encoder, 0, state.ubo_bind_group)
    wgpu.RenderPassEncoderSetVertexBuffer(render_pass_encoder, 0, state.vbo, 0, wgpu.BufferGetSize(state.vbo))
	wgpu.RenderPassEncoderDraw(render_pass_encoder, vertexCount=3, instanceCount=1, firstVertex=0, firstInstance=0)

	wgpu.RenderPassEncoderEnd(render_pass_encoder)
	wgpu.RenderPassEncoderRelease(render_pass_encoder)

	command_buffer := wgpu.CommandEncoderFinish(command_encoder, nil)
	defer wgpu.CommandBufferRelease(command_buffer)

	wgpu.QueueSubmit(state.queue, { command_buffer })
	wgpu.SurfacePresent(state.surface)
}

// Release all GPU resources in reverse creation order.
finish :: proc() {
	wgpu.RenderPipelineRelease(state.pipeline)
	wgpu.PipelineLayoutRelease(state.pipeline_layout)
	wgpu.ShaderModuleRelease(state.module)
	wgpu.QueueRelease(state.queue)
	wgpu.DeviceRelease(state.device)
	wgpu.AdapterRelease(state.adapter)
	wgpu.SurfaceRelease(state.surface)
	wgpu.InstanceRelease(state.instance)
}


