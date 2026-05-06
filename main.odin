package odin_wgpu

import "base:runtime"
import "core:fmt"
import "vendor:wgpu"
import "core:math/linalg"
import "core:math"

shader :: #load("shader.wgsl")

state: struct {
	ctx: runtime.Context,
	os:  OS,
    time_accum:      f32,
    mouse_delta:     [2]i32,
    lmb_down:        bool,
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
    camera:          Camera,
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
        create_grid(10)
        create_orbital_camera()
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
                        {format = .Float32x3, offset = 0, shaderLocation = 0},
                        {format = .Float32x3, offset = size_of(vec3), shaderLocation = 1}
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
				topology = .LineList,

			},
			multisample = {
				count = 1,
				mask  = 0xFFFFFFFF,
			},
		})


		os_run()
	}
}

Camera :: struct {
    target:         vec3,
    distance:       f32,
    min_distance:   f32,
    max_distance:   f32,
    yaw:            f32,
    pitch:          f32,
    min_pitch:      f32,
    max_pitch:      f32,
    rotate_speed:   f32,
    zoom_speed:     f32,
    mouse_sense:    f32,
}

create_orbital_camera :: proc() {
    state.camera = {
        target = {0, 0, 0},
        distance = 4,
        min_distance = 6,
        max_distance = 700,
        yaw = 0,
        pitch = 10,
        min_pitch = -85,
        max_pitch = 85,
        rotate_speed = 4.5,
        zoom_speed = 5.0,
        mouse_sense = 0.4,
    }
}

update_camera :: proc() {
    state.camera.yaw   += f32(state.mouse_delta.x) * state.camera.mouse_sense
    state.camera.pitch += f32(state.mouse_delta.y) * state.camera.mouse_sense
    clamp_camera()
}

clamp_camera :: proc() {
    state.camera.distance = math.clamp(state.camera.distance, state.camera.min_distance, state.camera.max_distance)
    state.camera.pitch = math.clamp(state.camera.pitch, state.camera.min_pitch, state.camera.max_pitch)
}

camera_position :: proc() -> vec3 {
    yaw := linalg.to_radians(state.camera.yaw)
    pitch := linalg.to_radians(state.camera.pitch)

    radius_xz := state.camera.distance * math.cos(pitch)
    offset := vec3 {
        radius_xz * math.sin(yaw),
        state.camera.distance * math.sin(pitch),
        radius_xz * math.cos(yaw),
    }
    return state.camera.target + offset
}

get_relative_mouse_movement :: proc() -> [2]i32 {
    delta := state.mouse_delta
    state.mouse_delta = 0
    return delta
}

camera_view_matrix :: proc(camera: Camera) -> linalg.Matrix4f32 {
    distance_matrix := linalg.matrix4_translate_f32(vec3{0, 0, -camera.distance})
    pitch_matrix    := linalg.matrix4_rotate_f32(linalg.to_radians(camera.pitch), vec3{1, 0, 0})
    yaw_matrix      := linalg.matrix4_rotate_f32(linalg.to_radians(camera.yaw), vec3{0, 1, 0})
    target_matrix   := linalg.matrix4_translate_f32(-camera.target)
    return distance_matrix * pitch_matrix * yaw_matrix * target_matrix
}

create_proj_matrix :: proc() -> linalg.Matrix4f32 {
    aspect := f32(state.config.width) / f32(state.config.height)
    return linalg.matrix4_perspective_f32(
        linalg.to_radians(f32(90)), 
        aspect, 
        0.01, 
        1000
    )
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

update :: proc() {
    if state.lmb_down do update_camera()
    state.mouse_delta = 0;
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
				clearValue = { 0.2, 0.2, 0.2, 1 },
			},
		},
	)

	wgpu.RenderPassEncoderSetPipeline(render_pass_encoder, state.pipeline)

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
	wgpu.RenderPipelineRelease(state.pipeline)
	wgpu.PipelineLayoutRelease(state.pipeline_layout)
	wgpu.ShaderModuleRelease(state.module)
	wgpu.QueueRelease(state.queue)
	wgpu.DeviceRelease(state.device)
	wgpu.AdapterRelease(state.adapter)
	wgpu.SurfaceRelease(state.surface)
	wgpu.InstanceRelease(state.instance)
}


