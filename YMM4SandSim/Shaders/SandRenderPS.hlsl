#include "SandCommon.hlsli"
#include "SandLighting.hlsli"

Texture2D<uint> StateColor : register(t0);
Texture2D<uint> StateMeta : register(t1);
Texture2D<uint> RigidOccupancy : register(t2);
Texture2D<uint> RigidColor : register(t3);
Texture2D<uint> RigidMeta : register(t4);
Texture2D<uint> LightField : register(t5);

static const uint EmptyRigidOwner = 0xffffffffu;

uint2 DecodeRigidOwner(uint owner)
{
    const uint index = owner - 1u;
    return uint2(index % StateWidth, index / StateWidth);
}

float4 main(float4 position : SV_Position) : SV_Target
{
    const uint2 pixel = (uint2)position.xy;
    if (pixel.x >= SourceWidth || pixel.y >= SourceHeight)
        return 0.0f;

    const uint2 statePosition = min(pixel / ParticleSize, uint2(LogicalStateWidth - 1u, LogicalStateHeight - 1u));

    uint color;
    uint meta;
    uint owner = EmptyRigidOwner;
    if (SolidPhysicsMode == 1u)
        owner = RigidOccupancy.Load(int3(statePosition, 0));
    if (owner != EmptyRigidOwner && owner != 0u)
    {
        const uint2 sourceId = DecodeRigidOwner(owner);
        color = RigidColor.Load(int3(sourceId, 0));
        meta = RigidMeta.Load(int3(sourceId, 0));
    }
    else
    {
        color = StateColor.Load(int3(statePosition, 0));
        meta = StateMeta.Load(int3(statePosition, 0));
    }

    const uint material = GetMaterial(meta);
    if (material == MaterialEmpty)
        return 0.0f;

    float4 straightColor;
    if (ColorMode == 1u)
    {
        // PreserveInput is literal for both cellular and XPBD-owned solids.
        straightColor = UnpackColor(color);
    }
    else
    {
        straightColor = MaterialColor(material);
    }

    if (LightingStrength > 0.0f)
    {
        const float3 propagatedLight = UnpackLight(LightField.Load(int3(statePosition, 0)));
        const float blend = saturate(LightingStrength);
        const float overdrive = max(LightingStrength - 1.0f, 0.0f);
        const float3 litFactor = float3(AmbientLight, AmbientLight, AmbientLight) +
            propagatedLight * (1.0f + overdrive);
        const float3 lightingFactor = max(
            float3(0.0f, 0.0f, 0.0f),
            lerp(float3(1.0f, 1.0f, 1.0f), litFactor, blend));
        straightColor.rgb *= lightingFactor;
    }

    const float4 sandColor = float4(straightColor.rgb * straightColor.a, straightColor.a);
    return sandColor;
}
