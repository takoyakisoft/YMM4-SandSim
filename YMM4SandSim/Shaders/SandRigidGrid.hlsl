#include "SandBehavior.hlsli"

Texture2D<uint> RigidMeta : register(t0);
Texture2D<float4> RigidStateRead : register(t1);
Texture2D<uint> CellularMeta : register(t2);
Texture2D<uint> RigidBodyLabel : register(t3);
RWTexture2D<uint> RigidOccupancy : register(u0);
RWTexture2D<float4> RigidStateWrite : register(u1);
RWTexture2D<uint> RigidBodyContact : register(u2);

static const uint EmptyRigidOwner = 0xffffffffu;
static const uint RigidContactHorizontal = 1u;
static const uint RigidContactVertical = 2u;

uint OwnerFor(uint2 sourceId)
{
    return sourceId.y * StateWidth + sourceId.x + 1u;
}

uint2 DecodeOwner(uint owner)
{
    const uint index = owner - 1u;
    return uint2(index % StateWidth, index / StateWidth);
}

uint2 PositionToCell(float2 position)
{
    const float2 maximumCell = float2(
        max((float)LogicalStateWidth - 1.0f, 0.0f),
        max((float)LogicalStateHeight - 1.0f, 0.0f));
    return (uint2)clamp(floor(position), float2(0.0f, 0.0f), maximumCell);
}

bool IsFixedCell(uint2 target)
{
    return IsFixed(GetMaterial(CellularMeta.Load(int3(target, 0))));
}

bool IsOccupiedByOtherBody(uint2 id, uint2 target)
{
    const uint owner = RigidOccupancy[target];
    if (owner == EmptyRigidOwner || owner == 0u || owner == OwnerFor(id))
        return false;

    const uint selfBody = RigidBodyLabel.Load(int3(id, 0));
    const uint otherBody = RigidBodyLabel.Load(int3(DecodeOwner(owner), 0));
    return selfBody != otherBody;
}

bool HasExternalObstacle(uint2 id, uint2 target)
{
    // Loose powder should be displaced or covered by a moving rigid body rather
    // than stopping the entire connected body.
    return IsFixedCell(target) || IsOccupiedByOtherBody(id, target);
}

uint ExternalContactMask(uint2 id, float4 state)
{
    uint mask = 0u;
    const uint2 horizontalTarget = PositionToCell(float2(state.x, state.w));
    const uint2 verticalTarget = PositionToCell(float2(state.z, state.y));

    if (HasExternalObstacle(id, horizontalTarget))
        mask |= RigidContactHorizontal;
    if (HasExternalObstacle(id, verticalTarget))
        mask |= RigidContactVertical;

    if (mask == 0u)
    {
        const uint2 target = PositionToCell(state.xy);
        if (HasExternalObstacle(id, target))
        {
            // A pure diagonal/corner overlap cannot be assigned safely to one
            // axis from the final-cell broadphase, so stop both components.
            mask = RigidContactHorizontal | RigidContactVertical;
        }
    }

    return mask;
}

void StopRigidAxes(uint2 id, uint contactMask)
{
    float4 state = RigidStateWrite[id];
    if ((contactMask & RigidContactHorizontal) != 0u)
        state.x = state.z;
    if ((contactMask & RigidContactVertical) != 0u)
        state.y = state.w;
    RigidStateWrite[id] = state;
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
        RigidBodyContact[id] = 0u;
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
        const float4 state = RigidStateWrite[id];
        const uint contactMask = ExternalContactMask(id, state);
        if (contactMask != 0u)
        {
            // Share only the blocked axes across the connected rigid body. A floor contact
            // removes vertical velocity while preserving a blast's horizontal
            // momentum; a wall does the inverse. This is closer to a rigid-body
            // contact than the old full rollback, which erased all momentum.
            const uint bodyOwner = RigidBodyLabel.Load(int3(id, 0));
            const uint2 bodyCell = IsValidRigidBodyOwner(bodyOwner) ? RigidBodySource(bodyOwner) : id;
            uint ignored;
            InterlockedOr(RigidBodyContact[bodyCell], contactMask, ignored);
            StopRigidAxes(id, contactMask);
        }
        return;
    }

    if (PhysicsPass == 3u)
    {
        const uint bodyOwner = RigidBodyLabel.Load(int3(id, 0));
        const uint2 bodyCell = IsValidRigidBodyOwner(bodyOwner) ? RigidBodySource(bodyOwner) : id;
        const uint contactMask = RigidBodyContact[bodyCell];
        if (contactMask != 0u)
            StopRigidAxes(id, contactMask);
    }
}
