struct StrokeVertexInput {
    float3 position : TEXCOORD0;
    float2 auxiliary : TEXCOORD1;
    float4 color : TEXCOORD2;
};

struct StrokeVertexOutput {
    float4 position : SV_Position;
    float2 auxiliary : TEXCOORD0;
    float4 color : TEXCOORD1;
};

cbuffer StrokeVertexUniforms : register(b0, space1) {
    float4x4 clip_from_model;
};

StrokeVertexOutput main(StrokeVertexInput input) {
    StrokeVertexOutput output;
    output.position = mul(clip_from_model, float4(input.position, 1.0));
    output.auxiliary = input.auxiliary;
    output.color = input.color;
    return output;
}