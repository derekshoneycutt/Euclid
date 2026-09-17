package shader

STROKE3D_UNIFORM_COUNT :: 32

STROKE3D_UNIFORMS :: []Shader_Uniform_Requirement{
    {.Transform, 0, "mvp", .Mat4, true},
    {.Light_Direction, 0, "uLightDirView", .Vec3, true},
    {.Ambient, 0, "uAmbient", .Float, true},
    {.Diffuse, 0, "uDiffuse", .Float, true},
    {.Material_Roughness, 0, "uMaterialRoughness", .Float, true},
    {.Material_Fresnel0, 0, "uMaterialFresnel0", .Float, true},
    {.Material_Specular_Tint, 0, "uMaterialSpecularTint", .Float, true},
    {.Material_Shadow_Limit, 0, "uMaterialShadowLimit", .Float, true},
    {.Segment_Start, 0, "uP0", .Vec2, true},
    {.Segment_End, 0, "uP1", .Vec2, true},
    {.Segment_Radius, 0, "uRadius", .Float, true},
    {.Viewport, 0, "uViewportHeight", .Float, true},
    {.Stroke_Mode, 0, "uStrokeMode", .Float, true},
    {.Strip_Alpha, 0, "uStripAlpha", .Float, true},
    {.Strip_Color, 0, "uStripColor", .Vec3, true},
    {.Strip_Side_Extent, 0, "uStripSideExtent", .Float, true},
    {.Arc_Intersections_Enabled, 0, "uArcIntersectionsEnabled", .Float, true},
    {.Intersection_Depth_Width, 0, "uIntersectionDepthWidth", .Float, true},
    {.Attachment_Extent, 0, "uAttachmentExtent", .Float, true},
    {.Occluder_Count, 0, "uOccluderCount", .Float, true},
    {.Occluder_Start, 0, "uOccluderP0[0]", .Vec2, true},
    {.Occluder_Start, 1, "uOccluderP0[1]", .Vec2, true},
    {.Occluder_End, 0, "uOccluderP1[0]", .Vec2, true},
    {.Occluder_End, 1, "uOccluderP1[1]", .Vec2, true},
    {.Occluder_Radius, 0, "uOccluderRadius[0]", .Float, true},
    {.Occluder_Radius, 1, "uOccluderRadius[1]", .Float, true},
    {.Occluder_Depth_Start, 0, "uOccluderDepth0[0]", .Float, true},
    {.Occluder_Depth_Start, 1, "uOccluderDepth0[1]", .Float, true},
    {.Occluder_Depth_End, 0, "uOccluderDepth1[0]", .Float, true},
    {.Occluder_Depth_End, 1, "uOccluderDepth1[1]", .Float, true},
    {.Occluder_Tangent, 0, "uOccluderTangent[0]", .Vec3, true},
    {.Occluder_Tangent, 1, "uOccluderTangent[1]", .Vec3, true},
}

STROKE3D_ATTRIBUTES :: []Shader_Attribute_Requirement{
    {.Position, "vertexPosition", 0, 3, 0, 0, .Vertex, true},
    {.Texcoord, "vertexTexCoord", 1, 2, 0, 0, .Vertex, true},
    {.Color, "vertexColor", 3, 4, 0, 0, .Vertex, true},
}

STROKE3D_CONTRACT :: Shader_Program_Contract{
    revision = 1,
    vertex_asset = "shaders/stroke3d.vs",
    fragment_asset = "shaders/stroke3d.fs",
    uniforms = STROKE3D_UNIFORMS,
    attributes = STROKE3D_ATTRIBUTES,
    topology = .Triangles,
    blend = .Straight_Alpha,
    cull = .None,
    target = .Presented_Framebuffer,
    viewport_assumption = .Raylib_Batch_Transform,
    fallback = .Tool_Primitives,
}

DUST_INSTANCED_UNIFORM_COUNT :: 2
DUST_INSTANCE_STRIDE_BYTES :: 32

DUST_INSTANCED_UNIFORMS :: []Shader_Uniform_Requirement{
    {.Viewport, 0, "uViewport", .Vec2, true},
    {.Texture, 0, "texture0", .Sampler, true},
}

DUST_INSTANCED_ATTRIBUTES :: []Shader_Attribute_Requirement{
    {.Position, "vertexPosition", 0, 2, 0, 0, .Vertex, true},
    {.Texcoord, "vertexTexCoord", 1, 2, 0, 0, .Vertex, true},
    {.Instance_Geometry, "instanceCenterDiameter", 2, 3, 0,
        DUST_INSTANCE_STRIDE_BYTES, .Instance, true},
    {.Color, "vertexColor", 3, 4, 12,
        DUST_INSTANCE_STRIDE_BYTES, .Instance, true},
    {.Instance_Variant, "instanceSpriteIndex", 4, 1, 28,
        DUST_INSTANCE_STRIDE_BYTES, .Instance, true},
}

DUST_INSTANCED_CONTRACT :: Shader_Program_Contract{
    revision = 1,
    vertex_asset = "shaders/dust_instanced.vs",
    fragment_asset = "shaders/dust_instanced.fs",
    uniforms = DUST_INSTANCED_UNIFORMS,
    attributes = DUST_INSTANCED_ATTRIBUTES,
    topology = .Triangles,
    blend = .Straight_Alpha,
    cull = .None,
    target = .Presented_Framebuffer,
    viewport_assumption = .Framebuffer_Pixels,
    fallback = .Dust_Immediate_Quads,
}

// uniform_index returns the binding index for one semantic array element.
uniform_index :: proc(
    contract: ^Shader_Program_Contract,
    semantic: Uniform_Semantic, element: u8 = 0) -> (int, bool) {
    for requirement, index in contract^.uniforms {
        if requirement.semantic == semantic && requirement.element == element {
            return index, true
        }
    }
    return 0, false
}

// attribute returns one vertex requirement by semantic identity.
attribute :: proc(
    contract: ^Shader_Program_Contract,
    semantic: Attribute_Semantic) -> (Shader_Attribute_Requirement, bool) {
    for requirement in contract^.attributes {
        if requirement.semantic == semantic {
            return requirement, true
        }
    }
    return {}, false
}