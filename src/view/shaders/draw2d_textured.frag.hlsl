struct Draw2DTexturedFragmentInput {
    float4 position : SV_Position;
    float2 texcoord : TEXCOORD0;
    float4 color : TEXCOORD1;
};

Texture2D<float4> draw_texture : register(t0, space2);
SamplerState draw_sampler : register(s0, space2);

float4 main(Draw2DTexturedFragmentInput input) : SV_Target0 {
    return draw_texture.Sample(draw_sampler, input.texcoord) * input.color;
}
