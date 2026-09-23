struct DustFragmentInput {
    float4 position : SV_Position;
    float2 texcoord : TEXCOORD0;
    float4 color : TEXCOORD1;
    nointerpolation float sprite_index : TEXCOORD2;
};

Texture2D<float4> dust_texture : register(t0, space2);
SamplerState dust_sampler : register(s0, space2);

float4 main(DustFragmentInput input) : SV_Target0 {
    static const float atlas_columns = 3.0;
    static const float atlas_rows = 3.0;
    float sprite_index = clamp(input.sprite_index, 0.0, 8.0);
    float tile_x = fmod(sprite_index, atlas_columns);
    float tile_y = floor(sprite_index / atlas_columns);
    float2 tile_uv = (input.texcoord + float2(tile_x, tile_y)) /
        float2(atlas_columns, atlas_rows);
    return dust_texture.Sample(dust_sampler, tile_uv) * input.color;
}