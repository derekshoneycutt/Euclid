struct LeaperLightFragmentInput {
    float4 position : SV_Position;
    float2 texcoord : TEXCOORD0;
    float4 color : TEXCOORD1;
    nointerpolation float sprite_index : TEXCOORD2;
};

// sprite_index carries extra Gaussian sharpness for each light instance.
float4 main(LeaperLightFragmentInput input) : SV_Target0 {
    float2 offset = input.texcoord * 2.0 - 1.0;
    float sharpness = 4.0 + max(input.sprite_index, 0.0);
    float falloff = exp(-sharpness * dot(offset, offset)) *
        saturate(1.0 - dot(offset, offset));
    return float4(input.color.rgb * (input.color.a * falloff), 0.0);
}
