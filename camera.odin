package odin_wgpu

import "core:math/linalg"
import "core:math"

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
        distance = 10,
        min_distance = 0.2,
        max_distance = 40,
        yaw = 0,
        pitch = 40,
        min_pitch = -85,
        max_pitch = 85,
        rotate_speed = 4.5,
        zoom_speed = 0.01,
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