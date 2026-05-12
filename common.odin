package odin_wgpu

CUBE_VERTICES :: []QuadVertex{
    // +Z face
    {offset = {-0.5, -0.5,  0.5}, normal = {0, 0, 1}},
    {offset = { 0.5, -0.5,  0.5}, normal = {0, 0, 1}},
    {offset = { 0.5,  0.5,  0.5}, normal = {0, 0, 1}},
    {offset = {-0.5, -0.5,  0.5}, normal = {0, 0, 1}},
    {offset = { 0.5,  0.5,  0.5}, normal = {0, 0, 1}},
    {offset = {-0.5,  0.5,  0.5}, normal = {0, 0, 1}},

    // -Z face
    {offset = { 0.5, -0.5, -0.5}, normal = {0, 0, -1}},
    {offset = {-0.5, -0.5, -0.5}, normal = {0, 0, -1}},
    {offset = {-0.5,  0.5, -0.5}, normal = {0, 0, -1}},
    {offset = { 0.5, -0.5, -0.5}, normal = {0, 0, -1}},
    {offset = {-0.5,  0.5, -0.5}, normal = {0, 0, -1}},
    {offset = { 0.5,  0.5, -0.5}, normal = {0, 0, -1}},

    // +X face
    {offset = { 0.5, -0.5,  0.5}, normal = {1, 0, 0}},
    {offset = { 0.5, -0.5, -0.5}, normal = {1, 0, 0}},
    {offset = { 0.5,  0.5, -0.5}, normal = {1, 0, 0}},
    {offset = { 0.5, -0.5,  0.5}, normal = {1, 0, 0}},
    {offset = { 0.5,  0.5, -0.5}, normal = {1, 0, 0}},
    {offset = { 0.5,  0.5,  0.5}, normal = {1, 0, 0}},

    // -X face
    {offset = {-0.5, -0.5, -0.5}, normal = {-1, 0, 0}},
    {offset = {-0.5, -0.5,  0.5}, normal = {-1, 0, 0}},
    {offset = {-0.5,  0.5,  0.5}, normal = {-1, 0, 0}},
    {offset = {-0.5, -0.5, -0.5}, normal = {-1, 0, 0}},
    {offset = {-0.5,  0.5,  0.5}, normal = {-1, 0, 0}},
    {offset = {-0.5,  0.5, -0.5}, normal = {-1, 0, 0}},

    // +Y face
    {offset = {-0.5,  0.5,  0.5}, normal = {0, 1, 0}},
    {offset = { 0.5,  0.5,  0.5}, normal = {0, 1, 0}},
    {offset = { 0.5,  0.5, -0.5}, normal = {0, 1, 0}},
    {offset = {-0.5,  0.5,  0.5}, normal = {0, 1, 0}},
    {offset = { 0.5,  0.5, -0.5}, normal = {0, 1, 0}},
    {offset = {-0.5,  0.5, -0.5}, normal = {0, 1, 0}},

    // -Y face
    {offset = {-0.5, -0.5, -0.5}, normal = {0, -1, 0}},
    {offset = { 0.5, -0.5, -0.5}, normal = {0, -1, 0}},
    {offset = { 0.5, -0.5,  0.5}, normal = {0, -1, 0}},
    {offset = {-0.5, -0.5, -0.5}, normal = {0, -1, 0}},
    {offset = { 0.5, -0.5,  0.5}, normal = {0, -1, 0}},
    {offset = {-0.5, -0.5,  0.5}, normal = {0, -1, 0}},
}

QUAD_VERTICES :: []Vertex{
    {pos = {-0.5, -0.5,  0.5}, uv = {}},
    {pos = { 0.5, -0.5,  0.5}, uv = {}},
    {pos = { 0.5,  0.5,  0.5}, uv = {}},
    {pos = {-0.5, -0.5,  0.5}, uv = {}},
    {pos = { 0.5,  0.5,  0.5}, uv = {}},
    {pos = {-0.5,  0.5,  0.5}, uv = {}},
}