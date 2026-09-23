struct DustVertexInput {
    float2 position : TEXCOORD0;
    float2 texcoord : TEXCOORD1;
    float3 center_diameter : TEXCOORD2;
    float4 color : TEXCOORD3;
    float sprite_index : TEXCOORD4;
};

struct DustVertexOutput {
    float4 position : SV_Position;
    float2 texcoord : TEXCOORD0;
    float4 color : TEXCOORD1;
    nointerpolation float sprite_index : TEXCOORD2;
};

cbuffer DustVertexUniforms : register(b0, space1) {
    float2 viewport_extent;
    float2 viewport_padding;
};

DustVertexOutput main(DustVertexInput input) {
    DustVertexOutput output;
    float2 pixel = input.center_diameter.xy +
        input.position * input.center_diameter.z;
    float2 normalized = float2(
        pixel.x * 2.0 / viewport_extent.x - 1.0,
        1.0 - pixel.y * 2.0 / viewport_extent.y);
    output.position = float4(normalized, 0.0, 1.0);
    output.texcoord = input.texcoord;
    output.color = input.color;
    output.sprite_index = input.sprite_index;
    return output;
}