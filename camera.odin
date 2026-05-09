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
    g.camera = {
        target = {0, 1, 0},
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
    g.camera.yaw   += f32(g.mouse_delta.x) * g.camera.mouse_sense
    g.camera.pitch += f32(g.mouse_delta.y) * g.camera.mouse_sense
    clamp_camera()
}

clamp_camera :: proc() {
    g.camera.distance = math.clamp(g.camera.distance, g.camera.min_distance, g.camera.max_distance)
    g.camera.pitch = math.clamp(g.camera.pitch, g.camera.min_pitch, g.camera.max_pitch)
}

camera_position :: proc() -> vec3 {
    yaw := linalg.to_radians(g.camera.yaw)
    pitch := linalg.to_radians(g.camera.pitch)

    radius_xz := g.camera.distance * math.cos(pitch)
    offset := vec3 {
        radius_xz * math.sin(yaw),
        g.camera.distance * math.sin(pitch),
        radius_xz * math.cos(yaw),
    }
    return g.camera.target + offset
}


camera_view_matrix :: proc() -> linalg.Matrix4f32 {
    distance_matrix := linalg.matrix4_translate_f32(vec3{0, 0, -g.camera.distance})
    pitch_matrix    := linalg.matrix4_rotate_f32(linalg.to_radians(g.camera.pitch), vec3{1, 0, 0})
    yaw_matrix      := linalg.matrix4_rotate_f32(linalg.to_radians(g.camera.yaw), vec3{0, 1, 0})
    target_matrix   := linalg.matrix4_translate_f32(-g.camera.target)
    return distance_matrix * pitch_matrix * yaw_matrix * target_matrix
}

create_proj_matrix :: proc() -> linalg.Matrix4f32 {
    aspect := f32(g.r.config.width) / f32(g.r.config.height)
    return linalg.matrix4_perspective_f32(
        linalg.to_radians(f32(90)), 
        aspect, 
        0.01, 
        1000
    )
}