#include "SandBehavior.hlsli"

Texture2D<uint> RigidMeta : register(t0);
Texture2D<float4> RigidLambda : register(t1);
RWTexture2D<uint> RigidBodyLabel : register(u0);

static const uint EmptyRigidBody = 0xffffffffu;
static const uint MaximumRootHops = 16u;

uint BodyOwnerFor(uint2 sourceId)
{
    return sourceId.y * StateWidth + sourceId.x + 1u;
}

uint2 BodySourceFor(uint owner)
{
    const uint index = owner - 1u;
    return uint2(index % StateWidth, index / StateWidth);
}

uint FindBodyRoot(uint owner)
{
    if (owner == EmptyRigidBody || owner == 0u)
        return EmptyRigidBody;

    uint root = owner;
    [loop]
    for (uint hop = 0u; hop < MaximumRootHops; hop++)
    {
        const uint parent = RigidBodyLabel[BodySourceFor(root)];
        if (parent == EmptyRigidBody || parent == 0u || parent == root)
            break;
        root = parent;
    }
    return root;
}

void UnionBodyEdge(uint2 first, uint2 second, uint material, bool bondIntact)
{
    if (!bondIntact)
        return;
    if (second.x >= LogicalStateWidth || second.y >= LogicalStateHeight)
        return;
    if (GetMaterial(RigidMeta.Load(int3(second, 0))) != material)
        return;

    const uint firstRoot = FindBodyRoot(RigidBodyLabel[first]);
    const uint secondRoot = FindBodyRoot(RigidBodyLabel[second]);
    if (firstRoot == EmptyRigidBody || secondRoot == EmptyRigidBody || firstRoot == secondRoot)
        return;

    const uint lower = min(firstRoot, secondRoot);
    const uint higher = max(firstRoot, secondRoot);
    uint ignored;
    InterlockedMin(RigidBodyLabel[BodySourceFor(higher)], lower, ignored);
}

[numthreads(8, 8, 1)]
void main(uint3 dispatchThreadId : SV_DispatchThreadID)
{
    const uint2 id = dispatchThreadId.xy;
    if (id.x >= StateWidth || id.y >= StateHeight)
        return;

    const uint material = GetMaterial(RigidMeta.Load(int3(id, 0)));
    const bool active = SolidPhysicsMode == 1u &&
        id.x < LogicalStateWidth && id.y < LogicalStateHeight &&
        IsRigidPhysicsMaterial(material);

    if (PhysicsPass == 0u)
    {
        RigidBodyLabel[id] = active ? BodyOwnerFor(id) : EmptyRigidBody;
        return;
    }

    if (!active)
        return;

    if (PhysicsPass == 1u)
    {
        // Four-neighbour connectivity deliberately keeps diagonal-only islands
        // as separate bodies. Different materials never share a body even when
        // their cells touch, matching the user's material-boundary expectation.
        const float4 lambda = RigidLambda.Load(int3(id, 0));
        UnionBodyEdge(id, id + uint2(1u, 0u), material, !IsBrokenRigidBond(lambda.x));
        UnionBodyEdge(id, id + uint2(0u, 1u), material, !IsBrokenRigidBond(lambda.y));
        return;
    }

    if (PhysicsPass == 2u)
    {
        const uint root = FindBodyRoot(RigidBodyLabel[id]);
        if (root != EmptyRigidBody)
            RigidBodyLabel[id] = root;
    }
}
