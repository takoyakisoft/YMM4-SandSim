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
    uint packedLight = 0u;
    float3 propagatedLight = 0.0f;
    float shockwaveAlpha = 0.0f;
    if (LightingStrength > 0.0f)
    {
        packedLight = LightField.Load(int3(statePosition, 0));
        propagatedLight = UnpackLight(packedLight);
        // Empty cells normally quantize to optical code 31. Code 30 is reserved
        // for an empty pressure-front cell. Restrict the test to MaterialEmpty so
        // ordinary material transmission can never be mistaken for a shock ring.
        if (material == MaterialEmpty && HasShockwaveLightMarker(packedLight))
        {
            const float frontBrightness = max(propagatedLight.r, max(propagatedLight.g, propagatedLight.b));
            shockwaveAlpha = saturate(frontBrightness * saturate(LightingStrength) * 0.36f);
        }
    }

    if (material == MaterialEmpty)
    {
        // Draw only the marked one-cell pressure front across otherwise empty
        // space. The output is premultiplied so it composites correctly in YMM4.
        const float3 shockwaveColor = float3(1.00f, 0.48f, 0.10f);
        return shockwaveAlpha > 0.0f
            ? float4(shockwaveColor * shockwaveAlpha, shockwaveAlpha)
            : 0.0f;
    }

    float4 straightColor;
    const bool transientHeat =
        material == MaterialFire || material == MaterialEmber ||
        material == MaterialSmoke || material == MaterialSteam;
    if (ColorMode == 1u && !transientHeat)
    {
        // Preserve the source artwork for persistent matter. Reaction products
        // use their physical palette color so fire cannot look like orange sand.
        straightColor = UnpackColor(color);
    }
    else
    {
        straightColor = MaterialColor(material);
    }

    if (LightingStrength > 0.0f)
    {
        const float blend = saturate(LightingStrength);
        const float overdrive = max(LightingStrength - 1.0f, 0.0f);
        const float3 litFactor = float3(AmbientLight, AmbientLight, AmbientLight) +
            propagatedLight * (1.0f + overdrive);
        const float3 lightingFactor = max(
            float3(0.0f, 0.0f, 0.0f),
            lerp(float3(1.0f, 1.0f, 1.0f), litFactor, blend));
        straightColor.rgb *= lightingFactor;
    }

    return float4(straightColor.rgb * straightColor.a, straightColor.a);
}
