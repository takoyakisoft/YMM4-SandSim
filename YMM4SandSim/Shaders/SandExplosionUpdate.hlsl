#include "SandBehavior.hlsli"

Texture2D<float> PreviousPressure : register(t0);
Texture2D<uint> RigidOccupancy : register(t1);
Texture2D<uint> RigidMeta : register(t2);
RWTexture2D<uint> CellularMeta : register(u0);
RWTexture2D<float> NextPressure : register(u1);

static const uint EmptyRigidOwner = 0xffffffffu;

groupshared float PressureTile[100];
groupshared float TransmissionTile[100];

uint MaterialAt(uint2 cell)
{
    // Initialize first so FXC /WX can prove the return value is assigned.
    uint material = GetMaterial(CellularMeta[cell]);
    if (SolidPhysicsMode == 1u)
    {
        const uint owner = RigidOccupancy.Load(int3(cell, 0));
        if (owner != EmptyRigidOwner && owner != 0u)
        {
            const uint index = owner - 1u;
            const uint2 rigidCell = uint2(index % StateWidth, index / StateWidth);
            material = GetMaterial(RigidMeta.Load(int3(rigidCell, 0)));
        }
    }
    return material;
}

uint TileIndex(int2 p)
{
    return (uint)(p.y * 10 + p.x);
}

float PressureAt(int2 p)
{
    return PressureTile[TileIndex(p)];
}

float TransmissionAt(int2 p)
{
    return TransmissionTile[TileIndex(p)];
}

float ReadDiagonalPressure(int2 center, int2 offset)
{
    const int2 source = center + offset;
    const float pressure = PressureAt(source);
    if (pressure <= 0.0f)
        return 0.0f;

    const int2 sideA = int2(source.x, center.y);
    const int2 sideB = int2(center.x, source.y);
    return pressure * max(TransmissionAt(sideA), TransmissionAt(sideB));
}

float ManualExplosionSeed(uint2 cell)
{
    if (ManualExplosionEnabled == 0u)
        return 0.0f;

    const int2 center = int2(ManualExplosionCellX, ManualExplosionCellY);
    const int2 delta = int2(cell) - center;
    const float distance = length((float2)delta);
    const float radius = max(ExplosionRadius, 1.0f);
    if (distance >= radius)
        return 0.0f;

    // Seed the controller blast across its configured radius immediately.
    // The old center-only seed could expand by at most one cell per simulation
    // iteration, so changing Radius barely changed the visible blast at the
    // default four iterations per frame. Sampling the ray keeps the one-shot
    // radial seed consistent with the material shielding used by propagation.
    float transmission = 1.0f;
    const uint sampleCount = (uint)ceil(distance);
    [loop]
    for (uint sampleIndex = 1u; sampleIndex <= sampleCount; sampleIndex++)
    {
        const float progress = (float)sampleIndex / max((float)sampleCount, 1.0f);
        const int2 samplePosition = center + (int2)round((float2)delta * progress);
        if (samplePosition.x < 0 || samplePosition.y < 0 ||
            samplePosition.x >= (int)LogicalStateWidth || samplePosition.y >= (int)LogicalStateHeight)
            return 0.0f;

        transmission *= ExplosionPressureTransmission(MaterialAt((uint2)samplePosition));
        if (transmission < 0.01f)
            return 0.0f;
    }

    return saturate(1.0f - distance / radius) * transmission;
}

[numthreads(8, 8, 1)]
void main(
    uint3 dispatchThreadId : SV_DispatchThreadID,
    uint3 groupId : SV_GroupID,
    uint3 groupThreadId : SV_GroupThreadID,
    uint groupIndex : SV_GroupIndex)
{
    // PhysicsPass 0 is the clear path. It must not touch optional rigid SRVs,
    // and it does not need a synchronization barrier.
    const uint2 id = dispatchThreadId.xy;
    if (PhysicsPass == 0u)
    {
        if (id.x < StateWidth && id.y < StateHeight)
            NextPressure[id] = 0.0f;
        return;
    }
    if (PhysicsPass == 2u)
    {
        if (id.x < StateWidth && id.y < StateHeight)
        {
            if (id.x < LogicalStateWidth && id.y < LogicalStateHeight)
            {
                const uint meta = CellularMeta[id];
                if (HasExplosionEvent(meta))
                    CellularMeta[id] = ClearExplosionEvent(meta);
            }
            NextPressure[id] = 0.0f;
        }
        return;
    }

    const int2 groupOrigin = int2(groupId.xy * 8u) - 1;
    for (uint tileIndex = groupIndex; tileIndex < 100u; tileIndex += 64u)
    {
        const int2 tilePosition = int2((int)(tileIndex % 10u), (int)(tileIndex / 10u));
        const int2 sourcePosition = groupOrigin + tilePosition;
        float pressure = 0.0f;
        float transmission = 0.0f;
        if (sourcePosition.x >= 0 && sourcePosition.y >= 0 &&
            sourcePosition.x < (int)LogicalStateWidth && sourcePosition.y < (int)LogicalStateHeight)
        {
            pressure = PreviousPressure.Load(int3(sourcePosition, 0));
            transmission = ExplosionPressureTransmission(MaterialAt((uint2)sourcePosition));
        }
        PressureTile[tileIndex] = pressure;
        TransmissionTile[tileIndex] = transmission;
    }

    GroupMemoryBarrierWithGroupSync();

    if (id.x >= StateWidth || id.y >= StateHeight)
        return;
    if (id.x >= LogicalStateWidth || id.y >= LogicalStateHeight)
    {
        NextPressure[id] = 0.0f;
        return;
    }

    uint meta = CellularMeta[id];
    const bool explosion = HasExplosionEvent(meta);
    if (explosion)
    {
        meta = ClearExplosionEvent(meta);
        CellularMeta[id] = meta;
    }

    if (ExplosionStrength <= 0.0f)
    {
        NextPressure[id] = 0.0f;
        return;
    }

    const int2 center = int2(groupThreadId.xy) + 1;
    float neighbour = 0.0f;
    neighbour = max(neighbour, PressureAt(center + int2(-1,  0)));
    neighbour = max(neighbour, PressureAt(center + int2( 1,  0)));
    neighbour = max(neighbour, PressureAt(center + int2( 0, -1)));
    neighbour = max(neighbour, PressureAt(center + int2( 0,  1)));
    neighbour = max(neighbour, max(0.0f, ReadDiagonalPressure(center, int2(-1, -1)) - ExplosionFalloff * 0.41421356f));
    neighbour = max(neighbour, max(0.0f, ReadDiagonalPressure(center, int2( 1, -1)) - ExplosionFalloff * 0.41421356f));
    neighbour = max(neighbour, max(0.0f, ReadDiagonalPressure(center, int2(-1,  1)) - ExplosionFalloff * 0.41421356f));
    neighbour = max(neighbour, max(0.0f, ReadDiagonalPressure(center, int2( 1,  1)) - ExplosionFalloff * 0.41421356f));

    const float propagated = max(0.0f, neighbour - ExplosionFalloff) * TransmissionAt(center);
    const float retained = PressureAt(center) * ExplosionDecay;
    const float eventSeed = explosion ? 1.0f : 0.0f;
    const float manualSeed = ManualExplosionSeed(id);
    const float pressure = max(max(eventSeed, manualSeed), max(propagated, retained));
    NextPressure[id] = pressure < 0.001f ? 0.0f : pressure;
}
