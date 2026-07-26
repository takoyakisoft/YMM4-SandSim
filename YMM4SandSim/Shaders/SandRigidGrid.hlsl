#include "SandBehavior.hlsli"

Texture2D<uint> RigidMeta : register(t0);
Texture2D<float4> RigidStateRead : register(t1);
Texture2D<uint> CellularMeta : register(t2);
RWTexture2D<uint> RigidOccupancy : register(u0);
RWTexture2D<float4> RigidStateWrite : register(u1);

static const uint EmptyRigidOwner = 0xffffffffu;

uint OwnerFor(uint2 sourceId)
{
    return sourceId.y * StateWidth + sourceId.x + 1u;
}

uint2 PositionToCell(float2 position)
{
    const float2 maximumCell = float2(
        max((float)LogicalStateWidth - 1.0f, 0.0f),
        max((float)LogicalStateHeight - 1.0f, 0.0f));
    return (uint2)clamp(floor(position), float2(0.0f, 0.0f), maximumCell);
}

[numthreads(8, 8, 1)]
void main(uint3 dispatchThreadId : SV_DispatchThreadID)
{
    const uint2 id = dispatchThreadId.xy;
    if (id.x >= StateWidth || id.y >= StateHeight)
        return;

    if (PhysicsPass == 0u)
    {
        RigidOccupancy[id] = EmptyRigidOwner;
        return;
    }

    const uint material = GetMaterial(RigidMeta.Load(int3(id, 0)));
    if (SolidPhysicsMode != 1u || id.x >= LogicalStateWidth || id.y >= LogicalStateHeight ||
        !IsRigidPhysicsMaterial(material))
        return;

    if (PhysicsPass == 1u)
    {
        const uint2 target = PositionToCell(RigidStateRead.Load(int3(id, 0)).xy);
        uint ignored;
        InterlockedMin(RigidOccupancy[target], OwnerFor(id), ignored);
        return;
    }

    if (PhysicsPass == 2u)
    {
        float4 state = RigidStateWrite[id];
        const uint2 target = PositionToCell(state.xy);
        const uint owner = RigidOccupancy[target];
        const uint cellularMaterial = GetMaterial(CellularMeta.Load(int3(target, 0)));
        const bool blockedByCellularSolid = IsPowder(cellularMaterial) || IsFixed(cellularMaterial);
        if (owner != OwnerFor(id) || blockedByCellularSolid)
        {
            // Deterministic cell-grid contact: the smallest immutable particle
            // id owns a contested cell. Powder and CA-created fixed cells also
            // support a rigid chunk. A rejected particle rolls back the current
            // substep and loses velocity. Two resolve/raster rounds in the host
            // remove almost all one-cell overlaps without CPU broadphase.
            state.xy = state.zw;
            state.zw = state.xy;
            RigidStateWrite[id] = state;
        }
    }
}
