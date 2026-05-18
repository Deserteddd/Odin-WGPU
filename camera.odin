package odin_wgpu

import "core:math/linalg"
import "core:math"

camera := struct {
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
    fov:            f32
} {
    target = {0, 100, 0},
    distance = 220,
    min_distance = 1,
    max_distance = 800,
    yaw = 0,
    pitch = -10,
    min_pitch = -85,
    max_pitch = 85,
    rotate_speed = 4.5,
    zoom_speed = 0.1,
    mouse_sense = 0.4,
    fov = 90
}

update_camera :: proc() {
    camera.yaw   += f32(g.mouse_delta.x) * camera.mouse_sense
    camera.pitch += f32(g.mouse_delta.y) * camera.mouse_sense
    clamp_camera()
}

clamp_camera :: proc() {
    camera.distance = math.clamp(camera.distance, camera.min_distance, camera.max_distance)
    camera.pitch = math.clamp(camera.pitch, camera.min_pitch, camera.max_pitch)
}

camera_position :: proc() -> vec3 {
    yaw := linalg.to_radians(camera.yaw)
    pitch := linalg.to_radians(camera.pitch)

    radius_xz := camera.distance * math.cos(pitch)
    offset := vec3 {
        radius_xz * math.sin(yaw),
        camera.distance * math.sin(pitch),
        radius_xz * math.cos(yaw),
    }
    return camera.target + offset

}

camera_view_matrix :: proc() -> linalg.Matrix4f32 {
    distance_matrix := linalg.matrix4_translate_f32(vec3{0, 0, -camera.distance})
    pitch_matrix    := linalg.matrix4_rotate_f32(linalg.to_radians(camera.pitch), vec3{1, 0, 0})
    yaw_matrix      := linalg.matrix4_rotate_f32(linalg.to_radians(camera.yaw), vec3{0, 1, 0})
    target_matrix   := linalg.matrix4_translate_f32(-camera.target)
    return distance_matrix * pitch_matrix * yaw_matrix * target_matrix
}

create_proj_matrix :: proc() -> linalg.Matrix4f32 {
    aspect := f32(g.r.config.width) / f32(g.r.config.height)
    return linalg.matrix4_perspective_f32(
        linalg.to_radians(f32(camera.fov)), 
        aspect, 
        0.01, 
        1000
    )
}