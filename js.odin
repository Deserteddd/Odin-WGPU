package odin_wgpu

import "core:sys/wasm/js"
import "core:fmt"
import "vendor:wgpu"
import "base:runtime"

OS :: struct {
	initialized: bool,
}

file_buffer_capacity :: 1 << 20
file_buffer: [file_buffer_capacity]u8
last_loaded_file: []u8

// Install OS-level hooks (resize listener).
os_init :: proc() {
	ok := js.add_window_event_listener(.Resize, nil, size_callback)
	assert(ok)
}

@(export)
get_file_buffer_ptr :: proc() -> rawptr {
	return &file_buffer[0]
}

@(export)
get_file_buffer_capacity :: proc() -> int {
	return len(file_buffer)
}

@(export)
on_file_loaded :: proc(length: int) {
	length := length
	if length > len(file_buffer) {
		length = len(file_buffer)
	}
	last_loaded_file = file_buffer[:length]
	fmt.println("Loaded file bytes:", length)
	fmt.println(string(last_loaded_file))
}

// NOTE: frame loop is done by the runtime.js repeatedly calling `step`.
// Mark the OS loop as ready so `step` begins rendering.
os_run :: proc() {
	state.os.initialized = true
}

// Runtime callback: called every tick from JS to drive rendering.
@(private="file", export)
step :: proc(dt: f32) -> bool {
	if !state.os.initialized {
		return true
	}
	draw(dt)
	return true
}

// Query the canvas size in physical pixels (CSS size * device pixel ratio).
os_get_framebuffer_size :: proc() -> (width, height: u32) {
	rect := js.get_bounding_client_rect("body")
	dpi := js.device_pixel_ratio()
	return u32(f64(rect.width) * dpi), u32(f64(rect.height) * dpi)
}

// Create a WebGPU surface bound to the canvas selector.
os_get_surface :: proc(instance: wgpu.Instance) -> wgpu.Surface {
	return wgpu.InstanceCreateSurface(
		instance,
		&wgpu.SurfaceDescriptor{
			nextInChain = &wgpu.SurfaceSourceCanvasHTMLSelector{
				sType = .SurfaceSourceCanvasHTMLSelector,
				selector = "#wgpu-canvas",
			},
		},
	)
}

// Finalizer: remove hooks and release GPU resources.
@(private="file", fini)
os_fini :: proc "contextless" () {
	context = runtime.default_context()
	js.remove_window_event_listener(.Resize, nil, size_callback)
	finish()
}

// Window resize handler: update surface configuration.
@(private="file")
size_callback :: proc(e: js.Event) {
	resize()
}