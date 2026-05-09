package odin_wgpu

import "base:runtime"
import "core:fmt"
import "vendor:wgpu"
import "core:math/linalg"
import "core:math"


PARTICLES :: 100000

g: struct {
	ctx:                        runtime.Context,
	os:                         OS,
    time_accum:                 f32,
    mouse_delta:                [2]i32,
    lmb_down:                   bool,
    camera:                     Camera,
    r:                          Renderer,
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

	r_run_compute(dt)
    r_draw_scene()

    r_present()
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

import "core:math/rand"

create_particles :: proc() {
	particles := make([]Particle, PARTICLES)
    defer delete(particles)

    for i in 0..<PARTICLES {
        rx := rand.float32()*10 - 5
        ry := rand.float32()*2
        rz := rand.float32()*10 - 5
        particles[i] = Particle{
            pos = {rx, ry, rz},
            vel = {0, 0.2, 0},
            life = 0
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


