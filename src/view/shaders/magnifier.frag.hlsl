struct MagnifierFragmentInput {
    float4 position : SV_Position;
    float2 texcoord : TEXCOORD0;
};

Texture2D<float4> scene_texture : register(t0, space2);
Texture2D<float4> magnified_texture : register(t1, space2);
SamplerState scene_sampler : register(s0, space2);
SamplerState magnified_sampler : register(s1, space2);

cbuffer MagnifierUniforms : register(b0, space3) {
    float4 lens_rect;
    float2 source_center;
    float2 output_extent;
    float zoom;
    float corner_radius;
    float border_width;
    float source_border_width;
};

float rectangle_distance(float2 sample_position, float2 half_extent) {
    float2 offset = abs(sample_position) - half_extent;
    return max(offset.x, offset.y);
}

float rounded_rectangle_distance(
    float2 sample_position, float2 half_extent, float radius) {
    float2 offset = abs(sample_position) - half_extent + radius;
    return length(max(offset, 0.0)) +
        min(max(offset.x, offset.y), 0.0) - radius;
}

float4 main(MagnifierFragmentInput input) : SV_Target0 {
    float2 pixel = input.position.xy;
    float4 color = scene_texture.Sample(scene_sampler, input.texcoord);

    float2 source_half_extent = lens_rect.zw / (2.0 * zoom);
    float source_distance = rectangle_distance(
        pixel - source_center, source_half_extent);
    float source_width = max(fwidth(source_distance), 0.5);
    float source_outline = 1.0 - smoothstep(
        source_border_width - source_width,
        source_border_width + source_width,
        abs(source_distance));
    float source_inner_outline = 1.0 - smoothstep(
        source_border_width * 0.35 - source_width,
        source_border_width * 0.35 + source_width,
        abs(source_distance));
    color = lerp(color, float4(0.0, 0.0, 0.0, 1.0),
        saturate(source_outline - source_inner_outline));
    color = lerp(color, float4(1.0, 1.0, 1.0, 1.0),
        saturate(source_inner_outline));

    float2 lens_center = lens_rect.xy + lens_rect.zw * 0.5;
    float2 lens_local = pixel - lens_center;
    float2 lens_half_extent = lens_rect.zw * 0.5;
    float lens_distance = rounded_rectangle_distance(
        lens_local, lens_half_extent, corner_radius);
    float lens_width = max(fwidth(lens_distance), 0.5);
    float lens_outer = 1.0 - smoothstep(
        -lens_width, lens_width, lens_distance);
    float lens_inner = 1.0 - smoothstep(
        -border_width - lens_width,
        -border_width + lens_width,
        lens_distance);
    float lens_content = 1.0 - smoothstep(
        -border_width * 0.45 - lens_width,
        -border_width * 0.45 + lens_width,
        lens_distance);

    float2 magnified_pixel = source_center + lens_local / zoom;
    float2 magnified_uv = magnified_pixel / output_extent;
    float4 magnified = magnified_texture.Sample(
        magnified_sampler, magnified_uv);
    color = lerp(color, float4(0.0, 0.0, 0.0, 1.0),
        saturate(lens_outer - lens_inner));
    color = lerp(color, float4(1.0, 1.0, 1.0, 1.0),
        saturate(lens_inner - lens_content));
    return lerp(color, magnified, saturate(lens_content));
}
