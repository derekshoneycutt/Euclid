struct Draw2DVertexInput {
    float2 position : TEXCOORD0;
    float2 texcoord : TEXCOORD1;
    float4 color : TEXCOORD2;
};

struct Draw2DTexturedVertexOutput {
    float4 position : SV_Position;
    float2 texcoord : TEXCOORD0;
    float4 color : TEXCOORD1;
};

cbuffer Draw2DVertexUniforms : register(b0, space1) {
    float2 viewport_extent;
    float2 viewport_padding;
};

Draw2DTexturedVertexOutput main(Draw2DVertexInput input) {
    Draw2DTexturedVertexOutput output;
    float2 normalized = float2(
        input.position.x * 2.0 / viewport_extent.x - 1.0,
        1.0 - input.position.y * 2.0 / viewport_extent.y);
    output.position = float4(normalized, 0.0, 1.0);
    output.texcoord = input.texcoord;
    output.color = input.color;
    return output;
}
