#include "SandLighting.hlsli"

Texture2D<uint> SourceLight : register(t0);
RWTexture2D<uint> DestinationLight : register(u0);

// One-cell halo around an 8x8 output group. Loading 100 packed cells once per
// group replaces repeated global texture reads for every cardinal/diagonal
// neighbour while preserving the same deterministic propagation rule.
groupshared uint LightTile[100];

uint TileIndex(int2 p)
{
    return (uint)(p.y * 10 + p.x);
}

uint PackedLightAt(int2 p)
{
    return LightTile[TileIndex(p)];
}

float LightTransmissionAt(int2 p)
{
    return UnpackLightTransmission(PackedLightAt(p));
}

void Consider(int2 center, int2 offset, float distance, inout float3 best)
{
    const int2 source = center + offset;
    const uint packedSource = PackedLightAt(source);
    const float3 sourceLight = UnpackLight(packedSource);
    if (max(sourceLight.r, max(sourceLight.g, sourceLight.b)) <= 0.0f)
        return;

    float transmission = UnpackLightTransmission(packedSource);
    if (offset.x != 0 && offset.y != 0)
    {
        const int2 sideA = int2(source.x, center.y);
        const int2 sideB = int2(center.x, source.y);
        transmission *= max(LightTransmissionAt(sideA), LightTransmissionAt(sideB));
    }

    const float attenuation = distance / max(LightingRadius, 1.0f);
    const float3 candidate = max(float3(0.0f, 0.0f, 0.0f), sourceLight * transmission - attenuation.xxx);
    best = max(best, candidate);
}

[numthreads(8, 8, 1)]
void main(
    uint3 dispatchThreadId : SV_DispatchThreadID,
    uint3 groupId : SV_GroupID,
    uint3 groupThreadId : SV_GroupThreadID,
    uint groupIndex : SV_GroupIndex)
{
    const int2 groupOrigin = int2(groupId.xy * 8u) - 1;
    for (uint tileIndex = groupIndex; tileIndex < 100u; tileIndex += 64u)
    {
        const int2 tilePosition = int2((int)(tileIndex % 10u), (int)(tileIndex / 10u));
        const int2 sourcePosition = groupOrigin + tilePosition;
        uint packed = 0u;
        if (sourcePosition.x >= 0 && sourcePosition.y >= 0 &&
            sourcePosition.x < (int)LogicalStateWidth && sourcePosition.y < (int)LogicalStateHeight)
        {
            packed = SourceLight.Load(int3(sourcePosition, 0));
        }
        LightTile[tileIndex] = packed;
    }

    GroupMemoryBarrierWithGroupSync();

    const uint2 id = dispatchThreadId.xy;
    if (id.x >= StateWidth || id.y >= StateHeight)
        return;
    if (id.x >= LogicalStateWidth || id.y >= LogicalStateHeight)
    {
        DestinationLight[id] = 0u;
        return;
    }

    const int2 center = int2(groupThreadId.xy) + 1;
    const uint packedCurrent = PackedLightAt(center);
    float3 best = UnpackLight(packedCurrent);
    Consider(center, int2(-1,  0), 1.0f, best);
    Consider(center, int2( 1,  0), 1.0f, best);
    Consider(center, int2( 0, -1), 1.0f, best);
    Consider(center, int2( 0,  1), 1.0f, best);
    Consider(center, int2(-1, -1), 1.41421356f, best);
    Consider(center, int2( 1, -1), 1.41421356f, best);
    Consider(center, int2(-1,  1), 1.41421356f, best);
    Consider(center, int2( 1,  1), 1.41421356f, best);
    DestinationLight[id] = PackLight(best, UnpackLightTransmission(packedCurrent));
}
