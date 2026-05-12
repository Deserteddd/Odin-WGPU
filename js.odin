package odin_wgpu

import "core:sys/wasm/js"
import "vendor:wgpu"
import "base:runtime"

OS :: struct {
	initialized: bool,
    clipboard: [dynamic]byte
}

// Local tracking for touch movement deltas.
@(private = "file")
touch_last_pos: [2]i32
@(private = "file")
touch_last_pos_valid: bool

// Install OS-level hooks (resize listener).
os_init :: proc() {
	ok := js.add_window_event_listener(.Resize, nil, size_callback);        assert(ok)
	ok =  js.add_window_event_listener(.Key_Down, nil, key_down_callback);  assert(ok)
	ok =  js.add_window_event_listener(.Key_Up, nil, key_up_callback);	    assert(ok)
	ok =  js.add_event_listener("playBtn", .Click, nil, pause_callback);    assert(ok)
	ok =  js.add_event_listener("resetBtn", .Click, nil, reset_callback);   assert(ok)
	ok =  js.add_event_listener("rotateBtn", .Click, nil, rotate_callback);    assert(ok)
 
    // Mouse controls
	ok =  js.add_event_listener("wgpu-canvas", .Mouse_Move, nil, mouse_move_callback); assert(ok)
	ok =  js.add_event_listener("wgpu-canvas", .Mouse_Down, nil, mouse_down_callback); assert(ok)
	ok =  js.add_event_listener("wgpu-canvas", .Mouse_Up, nil, mouse_up_callback);     assert(ok)
	ok =  js.add_event_listener("wgpu-canvas", .Wheel, nil, mwheel_callback);          assert(ok)
    // Touch screen
	ok =  js.add_event_listener("wgpu-canvas", .Touch_Start, nil, touch_start_callback);     assert(ok)
	ok =  js.add_event_listener("wgpu-canvas", .Touch_End, nil, touch_end_callback); assert(ok)
	ok =  js.add_event_listener("wgpu-canvas", .Touch_Move, nil, touch_move_callback); assert(ok)
}


// NOTE: frame loop is done by the runtime.js repeatedly calling `step`.
// Mark the OS loop as ready so `step` begins rendering.
os_run :: proc() {
	g.os.initialized = true
}

// Runtime callback: called every tick from JS to drive rendering.
@(private="file", export)
step :: proc(dt: f32) -> bool {
	if !g.os.initialized {
		return true
	}
    g.dt = dt
    update()
	frame()
	return true
}

@(export)
get_running_state :: proc() -> bool {
    return g.running
}

@(export)
get_rotate_state :: proc() -> bool {
    return g.rotate
}

// Query the canvas size in physical pixels (CSS size * device pixel ratio).
os_get_framebuffer_size :: proc() -> (width, height: u32) {
	rect := js.get_bounding_client_rect("body")

	dpi := f32(js.device_pixel_ratio())
	return u32(f32(rect.width) * dpi), u32(f32(rect.height) * dpi)
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
	js.remove_event_listener("wgpu-canvas", .Mouse_Move, nil, mouse_move_callback)
	js.remove_window_event_listener(.Mouse_Down, nil, mouse_down_callback)
	js.remove_window_event_listener(.Mouse_Up, nil, mouse_up_callback)
	finish()
}

// Window resize handler: update surface configuration.
@(private="file")
size_callback :: proc(e: js.Event) {
	context = g.ctx
	r_resize()
}

@(private="file")
mouse_move_callback :: proc(e: js.Event) {
	g.mouse_delta += {i32(e.mouse.movement.x), i32(e.mouse.movement.y)}
}

@(private="file")
mouse_down_callback :: proc(e: js.Event) {
	g.lmb_down = 0 in e.mouse.buttons
}

@(private="file")
mouse_up_callback :: proc(e: js.Event) {
	g.lmb_down = 0 in e.mouse.buttons
}

@(private="file")
touch_start_callback :: proc(e: js.Event) {
    g.lmb_down = true
	touch_last_pos = {i32(e.touch.client.x), i32(e.touch.client.y)}
	touch_last_pos_valid = true
}

@(private="file")
touch_move_callback :: proc(e: js.Event) {
	current := [2]i32{i32(e.touch.client.x), i32(e.touch.client.y)}
	if touch_last_pos_valid {
		g.mouse_delta += {current[0] - touch_last_pos[0], current[1] - touch_last_pos[1]}
	}
	touch_last_pos = current
	touch_last_pos_valid = true
}

@(private="file")
touch_end_callback :: proc(e: js.Event) {
    g.lmb_down = false
	touch_last_pos_valid = false
}

@(private="file")
mwheel_callback :: proc(e: js.Event) {
    if g.shift_down {
        camera.target.y -= f32(e.wheel.delta.y) * camera.zoom_speed
        if camera.target.y < 0 do camera.target.y = 0
    } else {
        camera.distance += f32(e.wheel.delta.y) * camera.zoom_speed
    }
    clamp_camera()
}

@(private="file")
pause_callback :: proc(e: js.Event) {
	g.running = !g.running
}

@(private="file")
rotate_callback :: proc(e: js.Event) {
	g.rotate = !g.rotate
}

@(private="file")
reset_callback :: proc(e: js.Event) {
	g.reset = true
    g.running = false
}

@(private="file")
key_down_callback :: proc(e: js.Event) {
	switch e.key.code {
		case "Space":
			g.running = !g.running
        case "ShiftLeft", "ShiftRight":
            g.shift_down = true
	}
}

@(private="file")
key_up_callback :: proc(e: js.Event) {
	switch e.key.code {
        case "ShiftLeft", "ShiftRight":
            g.shift_down = false
	}
}