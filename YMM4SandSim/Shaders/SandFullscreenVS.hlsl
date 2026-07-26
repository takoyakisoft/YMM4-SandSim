struct VertexOutput
{
    float4 Position : SV_Position;
};

VertexOutput main(uint vertexId : SV_VertexID)
{
    const float2 uv = float2((vertexId << 1u) & 2u, vertexId & 2u);
    VertexOutput output;
    output.Position = float4(uv.x * 2.0f - 1.0f, 1.0f - uv.y * 2.0f, 0.0f, 1.0f);
    return output;
}
