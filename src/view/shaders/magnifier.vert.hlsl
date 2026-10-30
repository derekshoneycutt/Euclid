struct MagnifierVertexOutput {
    float4 position : SV_Position;
    float2 texcoord : TEXCOORD0;
};

MagnifierVertexOutput main(uint vertex_id : SV_VertexID) {
    float2 coordinate = float2(
        float((vertex_id << 1) & 2),
        float(vertex_id & 2));
    MagnifierVertexOutput output;
    output.position = float4(
        coordinate.x * 2.0 - 1.0,
        1.0 - coordinate.y * 2.0,
        0.0,
        1.0);
    output.texcoord = coordinate;
    return output;
}
