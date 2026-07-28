#include "SandBehavior.hlsli"

Texture2D<uint> RigidOccupancy : register(t0);
Texture2D<uint> PreviousCellularMeta : register(t1);
RWTexture2D<float4> RigidState : register(u0);
RWTexture2D<uint> RigidColor : register(u1);
RWTexture2D<uint> RigidMeta : register(u2);
RWTexture2D<float4> RigidLambda : register(u3);
RWTexture2D<uint> CellularColor : register(u4);
RWTexture2D<uint> CellularMeta : register(u5);

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

uint ReactionSalt(uint baseSalt)
{
    // HashCell already mixes FrameIndex, but a video frame can execute several
    // CA/XPBD iterations. Include StepIndex so each iteration gets an independent
    // deterministic trial instead of repeating the same hit/miss all frame.
    return baseSalt + StepIndex * 0x9e3779b9u;
}

uint ReadPreviousMaterial(int2 position)
{
    if (position.x < 0 || position.y < 0 ||
        position.x >= (int)LogicalStateWidth || position.y >= (int)LogicalStateHeight)
        return MaterialEmpty;
    return GetMaterial(PreviousCellularMeta.Load(int3(position, 0)));
}

void ConsiderEnvironment(uint material, inout uint heat, inout bool hasAcid, inout bool hasSeaWater)
{
    if (material == MaterialLava)
        heat = MaterialLava;
    else if (material == MaterialFire && heat != MaterialLava)
        heat = MaterialFire;
    else if (material == MaterialEmber && heat == MaterialEmpty)
        heat = MaterialEmber;

    hasAcid = hasAcid || material == MaterialAcid;
    hasSeaWater = hasSeaWater || material == MaterialSeaWater;
}

void ReadEnvironment(uint2 cell, out uint heat, out bool hasAcid, out bool hasSeaWater)
{
    heat = MaterialEmpty;
    hasAcid = false;
    hasSeaWater = false;

    const int2 p = int2(cell);
    // Liquids and gases can occupy the same CA cell beneath a rigid particle.
    // Include the center cell as well as the 8-neighbour ring; otherwise an ice
    // particle immersed directly in lava/acid/seawater receives fluid forces but
    // never sees that material for chemistry.
    ConsiderEnvironment(ReadPreviousMaterial(p), heat, hasAcid, hasSeaWater);
    ConsiderEnvironment(ReadPreviousMaterial(p + int2(-1, -1)), heat, hasAcid, hasSeaWater);
    ConsiderEnvironment(ReadPreviousMaterial(p + int2( 0, -1)), heat, hasAcid, hasSeaWater);
    ConsiderEnvironment(ReadPreviousMaterial(p + int2( 1, -1)), heat, hasAcid, hasSeaWater);
    ConsiderEnvironment(ReadPreviousMaterial(p + int2(-1,  0)), heat, hasAcid, hasSeaWater);
    ConsiderEnvironment(ReadPreviousMaterial(p + int2( 1,  0)), heat, hasAcid, hasSeaWater);
    ConsiderEnvironment(ReadPreviousMaterial(p + int2(-1,  1)), heat, hasAcid, hasSeaWater);
    ConsiderEnvironment(ReadPreviousMaterial(p + int2( 0,  1)), heat, hasAcid, hasSeaWater);
    ConsiderEnvironment(ReadPreviousMaterial(p + int2( 1,  1)), heat, hasAcid, hasSeaWater);
}

void ClearRigid(uint2 id)
{
    RigidState[id] = 0.0f;
    RigidColor[id] = 0u;
    RigidMeta[id] = 0u;
    RigidLambda[id] = 0.0f;
}

void ConvertRigidToCell(uint2 id, uint2 target, uint material)
{
    // A phase change must not silently lose the product just because a liquid or
    // gas is frozen underneath the rigid occupancy. The grid only has one CA slot
    // per cell, so the converted material replaces that hidden cell. This also
    // gives same-cell heat contact a natural consume/replace behavior without a
    // second cross-thread write to an arbitrary neighbour.
    uint color = RigidColor[id];
    if (color == 0u)
        color = PackColor(TransitionMaterialColor(material));
    CellularColor[target] = color;
    CellularMeta[target] = MakeMeta(material, 0u);
    ClearRigid(id);
}

[numthreads(8, 8, 1)]
void main(uint3 dispatchThreadId : SV_DispatchThreadID)
{
    if (SolidPhysicsMode != 1u)
        return;

    const uint2 id = dispatchThreadId.xy;
    if (id.x >= StateWidth || id.y >= StateHeight ||
        id.x >= LogicalStateWidth || id.y >= LogicalStateHeight)
        return;

    const uint meta = RigidMeta[id];
    const uint material = GetMaterial(meta);

    if (material == MaterialEmpty)
    {
        // Promote fixed materials created by CA reactions (for example lava +
        // water -> stone, nitrogen + water -> ice) into an unused lattice slot.
        // If this source-index slot is still occupied by a moved rigid particle,
        // the CA solid remains a valid static obstacle rather than duplicating it.
        if (RigidOccupancy.Load(int3(id, 0)) != EmptyRigidOwner)
            return;

        const uint cellMeta = CellularMeta[id];
        const uint cellMaterial = GetMaterial(cellMeta);
        if (!IsRigidPhysicsMaterial(cellMaterial))
            return;

        const float2 position = float2(id) + 0.5f;
        RigidState[id] = float4(position, position);
        RigidColor[id] = CellularColor[id];
        RigidMeta[id] = cellMeta;
        RigidLambda[id] = 0.0f;
        CellularColor[id] = 0u;
        CellularMeta[id] = 0u;
        return;
    }

    if (!IsRigidPhysicsMaterial(material))
    {
        ClearRigid(id);
        return;
    }

    const uint2 target = PositionToCell(RigidState[id].xy);
    if (RigidOccupancy.Load(int3(target, 0)) != OwnerFor(id))
        return;

    if (ManualExplosionEnabled != 0u &&
        target.x == ManualExplosionCellX && target.y == ManualExplosionCellY &&
        IgnitionProbability(MaterialFire, material) > 0.0f)
    {
        // Match the CA hot-core rule for XPBD-owned flammable material. Only the
        // exact center becomes fire; propagation remains normal CA chemistry.
        ConvertRigidToCell(id, target, MaterialFire);
        return;
    }

    uint heat;
    bool hasAcid;
    bool hasSeaWater;
    ReadEnvironment(target, heat, hasAcid, hasSeaWater);

    if (material == MaterialCopper && hasSeaWater && Chance(id, ReactionSalt(0x9101u), 1.0f / 401.0f))
    {
        RigidMeta[id] = MakeMeta(MaterialOxidizedCopper, 0u);
        return;
    }

    if (IsColdSolid(material) && IsHeat(heat) && Chance(id, ReactionSalt(0x9102u), 0.65f))
    {
        ConvertRigidToCell(id, target, heat == MaterialLava ? MaterialSteam : MaterialWater);
        return;
    }

    if (material == MaterialPinkWax && IsHeat(heat) && Chance(id, ReactionSalt(0x9103u), 0.45f))
    {
        ConvertRigidToCell(id, target, MaterialOil);
        return;
    }

    if (hasAcid)
    {
        const float probability = AcidProbability(material);
        if (probability > 0.0f && Chance(id, ReactionSalt(0x9104u), probability))
        {
            // Acid is treated as an eroding neighbour here. We cannot safely
            // consume an arbitrary neighbouring CA cell from this parallel pass
            // without atomics, so the acid remains while the rigid cell dissolves.
            ClearRigid(id);
            return;
        }
    }

    if (IsHeat(heat))
    {
        const float probability = IgnitionProbability(heat, material);
        if (probability > 0.0f && Chance(id, ReactionSalt(0x9105u), probability))
            ConvertRigidToCell(id, target, MaterialFire);
    }
}
