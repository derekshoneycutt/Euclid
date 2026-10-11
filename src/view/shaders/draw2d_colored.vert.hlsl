struct Draw2DVertexInput {
    float2 position : TEXCOORD0;
    float2 texcoord : TEXCOORD1;
    float4 color : TEXCOORD2;
};

struct Draw2DColoredVertexOutput {
    float4 position : SV_Position;
    float4 color : TEXCOORD0;
};

cbuffer Draw2DVertexUniforms : register(b0, space1) {
    float2 viewport_extent;
    float2 viewport_padding;
};

Draw2DColoredVertexOutput main(Draw2DVertexInput input) {
    Draw2DColoredVertexOutput output;
    float2 normalized = float2(
        input.position.x * 2.0 / viewport_extent.x - 1.0,
        1.0 - input.position.y * 2.0 / viewport_extent.y);
    output.position = float4(normalized, 0.0, 1.0);
    output.color = input.color;
    return output;
}
