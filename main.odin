package odin_wgpu

import "base:runtime"
import "core:fmt"
import "vendor:wgpu"
import "core:math/linalg"
import "core:math"


PARTICLES :: 1000*3*3

g := struct {
	ctx:                        runtime.Context,
	os:                         OS,
    time_accum:                 f32,
    mouse_delta:                [2]i32,
    lmb_down:                   bool,
    camera:                     Camera,
    r:                          Renderer,
	bg:                         wgpu.Color
}{
	bg = {0.35, 0.37, 0.39, 1.0}
}


// Entry point: initialize OS bindings and kick off async WebGPU setup.
main :: proc() {
	g.ctx = context
	os_init()
	g.r.instance = wgpu.CreateInstance(nil)
	if g.r.instance == nil {
		panic("WebGPU is not supported")
	}
	g.r.surface = os_get_surface(g.r.instance)

	wgpu.InstanceRequestAdapter(g.r.instance, &{ compatibleSurface = g.r.surface }, { callback = on_adapter })
}

frame :: proc(dt: f32) {
    defer free_all(context.temp_allocator)
    g.time_accum += dt

    r_begin_frame() 

    particle_count := u32(wgpu.BufferGetSize(g.r.particle_buffer) / size_of(Particle))
	r_run_compute(particle_count)
    r_draw_scene(particle_count)

    r_present()
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

    r.compute_bind_group = wgpu.DeviceCreateBindGroup(r.device, &{
        label = "Compute bind group",
        layout = wgpu.ComputePipelineGetBindGroupLayout(r.compute_pipeline, 0),
        entryCount = 1,
        entries = raw_data([]wgpu.BindGroupEntry{
            {
                binding = 0,
                offset = 0,
                size = wgpu.BufferGetSize(r.particle_buffer),
                buffer = r.particle_buffer,
            },
        })
    })
}

get_relative_mouse_movement :: proc() -> [2]i32 {
    delta := g.mouse_delta
    g.mouse_delta = 0
    return delta
}

create_grid :: proc(size: int) {
    vertices: [dynamic]Vertex
    defer delete(vertices)
	half := size / 2
	for i in -half..=half {
		x := f32(i)
		z := f32(i)
        append(&vertices, Vertex {pos = {x, 0, f32(-half)}, col = {0.6, 0.6, 0.6}})
        append(&vertices, Vertex {pos = {x, 0, f32(half)},  col = {0.6, 0.6, 0.6}})

        append(&vertices, Vertex {pos = {f32(-half), 0, z}, col = {0.6, 0.6, 0.6}})
        append(&vertices, Vertex {pos = {f32(half), 0, z},  col = {0.6, 0.6, 0.6}})
	}

    g.r.vbo = wgpu.DeviceCreateBufferWithDataSlice(g.r.device, &{
        label = "Triangle buf",
        usage = {.Vertex}
    }, vertices[:]); assert(g.r.vbo != nil)
}


create_particles :: proc() {
	particles := make([]Particle, PARTICLES)
    defer delete(particles)

	hash_u32 :: proc(x: u32) -> u32 {
		y := x
		y ~= y >> 16
		y *= u32(0x7feb352d)
		y ~= y >> 15
		y *= u32(0x846ca68b)
		y ~= y >> 16
		return y
	}

	to_unit :: proc(x: u32) -> f32 {
		return f32(x) * (1.0 / f32(0xffffffff))
	}

	volume_size := f32(4)
	side_f := math.pow_f32(f32(PARTICLES), 1.0/3.0)
	side := int(math.ceil(side_f))
	spacing := volume_size / f32(side)
	jitter := spacing
	half := volume_size * 0.5

	i: int
	for x in 0..<side {
		for y in 0..<side {
			for z in 0..<side {
				if i >= len(particles) do break
				idx := u32(i)
				rx := (to_unit(hash_u32(idx*3 + 0)) - 0.5) * jitter
				ry := (to_unit(hash_u32(idx*3 + 1)) - 0.5) * jitter
				rz := (to_unit(hash_u32(idx*3 + 2)) - 0.5) * jitter

				px := (f32(x)+0.5)*spacing - half + rx
				py := (f32(y)+0.5)*spacing + ry
				pz := (f32(z)+0.5)*spacing - half + rz

				pos := vec3{
					math.clamp(px, -half, half),
					math.clamp(py, 0, volume_size),
					math.clamp(pz, -half, half),
				}

				particles[i] = Particle{pos, 0}
				i += 1
			}
		}
	}

	g.r.particle_buffer = wgpu.DeviceCreateBufferWithDataSlice(g.r.device, &{
		label = "Particle buffer",
		usage = {.Storage, .Vertex, .CopyDst}
	}, particles[:]); assert(g.r.particle_buffer != nil)
}

update :: proc() {
    if g.lmb_down do update_camera()
    g.mouse_delta = 0;
}


// Release all GPU resources in reverse creation order.
finish :: proc() {
    r := &g.r
	wgpu.RenderPipelineRelease(r.gfx_pipeline)
	wgpu.RenderPipelineRelease(r.particle_pipeline)
	wgpu.ComputePipelineRelease(r.compute_pipeline)
	wgpu.PipelineLayoutRelease(r.gfx_pipeline_layout)
	wgpu.PipelineLayoutRelease(r.particle_pipeline_layout)
	wgpu.ShaderModuleRelease(r.gfx_module)
	wgpu.ShaderModuleRelease(r.particle_module)
	wgpu.ShaderModuleRelease(r.compute_module)
	wgpu.QueueRelease(r.queue)
	wgpu.DeviceRelease(r.device)
	wgpu.AdapterRelease(r.adapter)
	wgpu.SurfaceRelease(r.surface)
	wgpu.InstanceRelease(r.instance)

}


