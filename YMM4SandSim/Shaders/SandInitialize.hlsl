#include "SandCommon.hlsli"
#include "SandBehavior.hlsli"

Texture2D<float4> Source : register(t0);
Texture2D<uint> PreviousColor : register(t1);
Texture2D<uint> PreviousMeta : register(t2);
Texture2D<uint> ExistingRigidOccupancy : register(t3);
RWTexture2D<uint> DestinationColor : register(u0);
RWTexture2D<uint> DestinationMeta : register(u1);

static const uint EmptyRigidOwner = 0xffffffffu;

uint RigidOwnerFor(uint2 sourceId)
{
    return sourceId.y * StateWidth + sourceId.x + 1u;
}

void PreservePreviousCell(uint2 position)
{
    DestinationColor[position] = PreviousColor.Load(int3(position, 0));
    DestinationMeta[position] = PreviousMeta.Load(int3(position, 0));
}

[numthreads(8, 8, 1)]
void main(uint3 dispatchThreadId : SV_DispatchThreadID)
{
    const uint2 statePosition = dispatchThreadId.xy;
    if (statePosition.x >= StateWidth || statePosition.y >= StateHeight)
        return;

    const bool preserveExisting = InitializeMode != 0u;
    const bool overwriteSelected = InitializeMode == 2u;

    if (statePosition.x >= LogicalStateWidth || statePosition.y >= LogicalStateHeight)
    {
        if (preserveExisting)
        {
            DestinationColor[statePosition] = PreviousColor.Load(int3(statePosition, 0));
            DestinationMeta[statePosition] = PreviousMeta.Load(int3(statePosition, 0));
        }
        else
        {
            DestinationColor[statePosition] = 0u;
            DestinationMeta[statePosition] = 0u;
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

    const uint previousMeta = PreviousMeta.Load(int3(statePosition, 0));
    const bool hadPrevious = IsOccupiedMeta(previousMeta);

    if (preserveExisting && hadPrevious && !overwriteSelected)
    {
        DestinationColor[statePosition] = PreviousColor.Load(int3(statePosition, 0));
        DestinationMeta[statePosition] = previousMeta;
        return;
    }

    if (!selected)
    {
        if (preserveExisting && hadPrevious)
        {
            DestinationColor[statePosition] = PreviousColor.Load(int3(statePosition, 0));
            DestinationMeta[statePosition] = previousMeta;
        }
        else
        {
            DestinationColor[statePosition] = 0u;
            DestinationMeta[statePosition] = 0u;
        }
        return;
    }

    if (preserveExisting && SolidPhysicsMode == 1u)
    {
        const uint occupyingRigid = ExistingRigidOccupancy.Load(int3(statePosition, 0));
        // "Fill empty" means visually empty across both solvers. A moved rigid
        // particle may occupy this cell even though the CA metadata is empty.
        // Restamping may replace its own source particle, but must not inject CA
        // state underneath a different rigid owner.
        const bool occupiedByOtherRigid = occupyingRigid != EmptyRigidOwner &&
            occupyingRigid != RigidOwnerFor(statePosition);
        if ((InitializeMode == 1u && occupyingRigid != EmptyRigidOwner) ||
            (InitializeMode == 2u && occupiedByOtherRigid))
        {
            PreservePreviousCell(statePosition);
            return;
        }
    }

    uint material = MaterialAssignment == 1u
        ? SingleMaterial
        : ClosestMaterialFromColor(straightRgb);
    if (material < MaterialSand || material > MaterialQuartz)
        material = MaterialSand;

    // In GPU XPBD mode, stationary-solid classes are owned by the rigid
    // lattice solver rather than the cellular state. Keeping ownership
    // disjoint prevents duplicated solids and makes rasterized rigid cells
    // usable as transient obstacles without leaving trails in StateMeta.
    if (SolidPhysicsMode == 1u && IsRigidPhysicsMaterial(material))
    {
        DestinationColor[statePosition] = 0u;
        DestinationMeta[statePosition] = 0u;
        return;
    }

    DestinationColor[statePosition] = PackColor(float4(straightRgb, alpha));
    DestinationMeta[statePosition] = MakeMeta(material, 0u);
}
