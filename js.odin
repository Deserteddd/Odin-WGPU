package odin_wgpu

import "core:sys/wasm/js"
import "core:fmt"
import "vendor:wgpu"
import "base:runtime"

OS :: struct {
	initialized: bool,
}

// Install OS-level hooks (resize listener).
os_init :: proc() {
	ok := js.add_window_event_listener(.Resize, nil, size_callback)
	assert(ok)
    ok = js.add_event_listener("button", .Click, nil, btn_callback)
    assert(ok)
    ok = js.add_window_event_listener(.Mouse_Move, nil, mouse_callback)
    assert(ok)
}
@(private="file")
btn_callback :: proc(e: js.Event) {
    fmt.println("BANANA!")
}

mouse_callback :: proc(e: js.Event) {
    
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
    js.remove_event_listener("button", .Click, nil, btn_callback)
    js.remove_window_event_listener(.Mouse_Move, nil, mouse_callback)
	finish()
}

// Window resize handler: update surface configuration.
@(private="file")
size_callback :: proc(e: js.Event) {
	resize()
}