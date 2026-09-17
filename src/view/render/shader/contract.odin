package shader

// Uniform_Value_Kind identifies the value shape required by one shader uniform.
Uniform_Value_Kind :: enum u8 {
    Float,
    Vec2,
    Vec3,
    Mat4,
    Sampler,
}

// Uniform_Semantic identifies one application meaning independently of source names.
Uniform_Semantic :: enum u8 {
    Transform,
    Light_Direction,
    Ambient,
    Diffuse,
    Material_Roughness,
    Material_Fresnel0,
    Material_Specular_Tint,
    Material_Shadow_Limit,
    Segment_Start,
    Segment_End,
    Segment_Radius,
    Viewport,
    Stroke_Mode,
    Strip_Alpha,
    Strip_Color,
    Strip_Side_Extent,
    Arc_Intersections_Enabled,
    Intersection_Depth_Width,
    Attachment_Extent,
    Occluder_Count,
    Occluder_Start,
    Occluder_End,
    Occluder_Radius,
    Occluder_Depth_Start,
    Occluder_Depth_End,
    Occluder_Tangent,
    Texture,
}

// Shader_Uniform_Requirement describes one source-level uniform binding.
Shader_Uniform_Requirement :: struct {
    semantic: Uniform_Semantic,
    element:  u8,
    name:     cstring,
    kind:     Uniform_Value_Kind,
    required: bool,
}

// Attribute_Semantic identifies one vertex input independently of source names.
Attribute_Semantic :: enum u8 {
    Position,
    Texcoord,
    Color,
    Instance_Geometry,
    Instance_Variant,
}

// Attribute_Input_Rate identifies whether an input advances per vertex or instance.
Attribute_Input_Rate :: enum u8 {
    Vertex,
    Instance,
}

// Shader_Attribute_Requirement describes one shader vertex input and memory layout.
Shader_Attribute_Requirement :: struct {
    semantic:       Attribute_Semantic,
    name:           string,
    location:       u8,
    component_count: u8,
    offset_bytes:   u16,
    stride_bytes:   u16,
    input_rate:     Attribute_Input_Rate,
    required:       bool,
}

// Render_Topology identifies the primitive assembly expected by a shader program.
Render_Topology :: enum u8 {
    Triangles,
}

// Render_Blend_Mode identifies the framebuffer blend contract.
Render_Blend_Mode :: enum u8 {
    Straight_Alpha,
}

// Render_Cull_Mode identifies the face-culling contract.
Render_Cull_Mode :: enum u8 {
    None,
}

// Render_Target identifies the destination assumed by a shader program.
Render_Target :: enum u8 {
    Presented_Framebuffer,
}

// Viewport_Assumption identifies the coordinate extent supplied to a shader.
Viewport_Assumption :: enum u8 {
    Raylib_Batch_Transform,
    Framebuffer_Pixels,
}

// Shader_Fallback_Kind identifies behavior selected when a program is unavailable.
Shader_Fallback_Kind :: enum u8 {
    Tool_Primitives,
    Dust_Immediate_Quads,
}

// Shader_Program_Contract owns one complete application shader ABI description.
Shader_Program_Contract :: struct {
    revision:            u32,
    vertex_asset:        string,
    fragment_asset:      string,
    uniforms:            []Shader_Uniform_Requirement,
    attributes:          []Shader_Attribute_Requirement,
    topology:            Render_Topology,
    blend:               Render_Blend_Mode,
    cull:                Render_Cull_Mode,
    target:              Render_Target,
    viewport_assumption: Viewport_Assumption,
    fallback:            Shader_Fallback_Kind,
}

// Validation_Failure identifies why a loaded program does not satisfy its contract.
Validation_Failure :: enum u8 {
    None,
    Location_Count,
    Missing_Uniform,
}

// Validation_Result reports one deterministic shader contract validation outcome.
Validation_Result :: struct {
    failure:          Validation_Failure,
    requirement_index: int,
}

// validate_uniform_locations checks every required uniform resolved by a backend.
validate_uniform_locations :: proc(
    contract: ^Shader_Program_Contract, locations: []i32) -> Validation_Result {
    if len(locations) != len(contract^.uniforms) {
        return {failure = .Location_Count, requirement_index = -1}
    }
    for requirement, index in contract^.uniforms {
        if requirement.required && locations[index] < 0 {
            return {failure = .Missing_Uniform, requirement_index = index}
        }
    }
    return {requirement_index = -1}
}

// fallback_for_validation returns the declared fallback for an invalid program.
fallback_for_validation :: proc(
    contract: ^Shader_Program_Contract,
    validation: Validation_Result) -> (Shader_Fallback_Kind, bool) {
    return contract^.fallback, validation.failure != .None
}