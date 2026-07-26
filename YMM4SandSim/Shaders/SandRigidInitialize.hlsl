#include "SandCommon.hlsli"
#include "SandBehavior.hlsli"

Texture2D<float4> Source : register(t0);
Texture2D<uint> CellularMeta : register(t1);
Texture2D<uint> ExistingRigidOccupancy : register(t2);
RWTexture2D<float4> RigidState : register(u0); // xy=current position, zw=previous position
RWTexture2D<uint> RigidColor : register(u1);
RWTexture2D<uint> RigidMeta : register(u2);
RWTexture2D<float4> RigidLambda : register(u3); // +X, +Y, +X+Y, -X+Y bond lambdas

static const uint EmptyRigidOwner = 0xffffffffu;

uint RigidOwnerFor(uint2 sourceId)
{
    return sourceId.y * StateWidth + sourceId.x + 1u;
}

[numthreads(8, 8, 1)]
void main(uint3 dispatchThreadId : SV_DispatchThreadID)
{
    const uint2 statePosition = dispatchThreadId.xy;
    if (statePosition.x >= StateWidth || statePosition.y >= StateHeight)
        return;

    if (SolidPhysicsMode != 1u)
    {
        RigidState[statePosition] = 0.0f;
        RigidColor[statePosition] = 0u;
        RigidMeta[statePosition] = 0u;
        RigidLambda[statePosition] = 0.0f;
        return;
    }

    const bool preserveExisting = InitializeMode != 0u;
    const bool overwriteSelected = InitializeMode == 2u;
    const uint existingMeta = RigidMeta[statePosition];
    const bool hadExisting = IsOccupiedMeta(existingMeta);

    if (statePosition.x >= LogicalStateWidth || statePosition.y >= LogicalStateHeight)
    {
        if (!preserveExisting)
        {
            RigidState[statePosition] = 0.0f;
            RigidColor[statePosition] = 0u;
            RigidMeta[statePosition] = 0u;
            RigidLambda[statePosition] = 0.0f;
        }
        return;
    }

    const uint2 sourcePosition = min(
        statePosition * ParticleSize + ParticleSize / 2u,
        uint2(SourceWidth - 1u, SourceHeight - 1u));
    const float4 premultiplied = Source.Load(int3(sourcePosition, 0));
    const float alpha = saturate(premultiplied.a);
    const float3 straightRgb = alpha > 0.000001f
        ? saturate(premultiplied.rgb / alpha)
        : float3(0.0f, 0.0f, 0.0f);
    const float luminance = dot(straightRgb, float3(0.2126f, 0.7152f, 0.0722f));

    bool selected;
    if (MaskMode == 1u)
        selected = alpha > 0.0f && luminance >= LuminanceThreshold;
    else if (MaskMode == 2u)
        selected = alpha > 0.0f && alpha >= AlphaThreshold && luminance >= LuminanceThreshold;
    else
        selected = alpha > 0.0f && alpha >= AlphaThreshold;

    if (preserveExisting && hadExisting && !overwriteSelected)
        return;

    if (!selected)
    {
        if (!preserveExisting)
        {
            RigidState[statePosition] = 0.0f;
            RigidColor[statePosition] = 0u;
            RigidMeta[statePosition] = 0u;
            RigidLambda[statePosition] = 0.0f;
        }
        return;
    }

    uint material = MaterialAssignment == 1u
        ? SingleMaterial
        : ClosestMaterialFromColor(straightRgb);
    if (material < MaterialSand || material > MaterialQuartz)
        material = MaterialSand;

    if (InitializeMode == 1u && IsOccupiedMeta(CellularMeta.Load(int3(statePosition, 0))))
    {
        // FillEmptyOnly is shared by both solvers: an already occupied CA cell
        // must not gain a second rigid owner at the same logical source cell.
        return;
    }

    if (InitializeMode != 0u)
    {
        const uint occupyingRigid = ExistingRigidOccupancy.Load(int3(statePosition, 0));
        if (InitializeMode == 1u && occupyingRigid != EmptyRigidOwner)
            return;
        if (InitializeMode == 2u && occupyingRigid != EmptyRigidOwner &&
            occupyingRigid != RigidOwnerFor(statePosition))
            return;
    }

    if (!IsRigidPhysicsMaterial(material))
    {
        // StampSelectedEveryFrame owns selected pixels. If a selected source
        // pixel changes from rigid to cellular material, remove the previous
        // rigid particle so the two simulations never own the same source cell.
        if (!preserveExisting || overwriteSelected)
        {
            RigidState[statePosition] = 0.0f;
            RigidColor[statePosition] = 0u;
            RigidMeta[statePosition] = 0u;
            RigidLambda[statePosition] = 0.0f;
        }
        return;
    }

    const float2 initialPosition = float2(statePosition) + 0.5f;
    RigidState[statePosition] = float4(initialPosition, initialPosition);
    RigidColor[statePosition] = PackColor(float4(straightRgb, alpha));
    RigidMeta[statePosition] = MakeMeta(material, 0u);
    // Preserve fracture history for an existing source particle during emitter
    // restamping. ClearAndRebuild and genuinely new particles still start with
    // intact bonds. This avoids healing only the four bonds owned by a stamped
    // cell while leaving neighbour-owned broken bonds unchanged.
    if (!preserveExisting || !hadExisting)
        RigidLambda[statePosition] = 0.0f;
}
