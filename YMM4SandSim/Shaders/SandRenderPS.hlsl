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

    uint packedLight = 0u;
    float3 propagatedLight = 0.0f;
    float shockwaveAlpha = 0.0f;
    if (LightingStrength > 0.0f)
    {
        packedLight = LightField.Load(int3(statePosition, 0));
        propagatedLight = UnpackLight(packedLight);
        if (HasShockwaveLightMarker(packedLight))
        {
            const float frontBrightness = max(propagatedLight.r, max(propagatedLight.g, propagatedLight.b));
            shockwaveAlpha = saturate(frontBrightness * saturate(LightingStrength) * 0.36f);
        }
    }

    const float3 shockwaveColor = float3(1.00f, 0.48f, 0.10f);
    const uint material = GetMaterial(meta);
    if (material == MaterialEmpty)
    {
        // Empty cells normally remain transparent. A marked pressure-front cell is
        // the exception: draw a thin premultiplied warm ring so the physical wave
        // itself is visible while it crosses otherwise empty space.
        return shockwaveAlpha > 0.0f
            ? float4(shockwaveColor * shockwaveAlpha, shockwaveAlpha)
            : 0.0f;
    }

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
        const float blend = saturate(LightingStrength);
        const float overdrive = max(LightingStrength - 1.0f, 0.0f);
        const float3 litFactor = float3(AmbientLight, AmbientLight, AmbientLight) +
            propagatedLight * (1.0f + overdrive);
        const float3 lightingFactor = max(
            float3(0.0f, 0.0f, 0.0f),
            lerp(float3(1.0f, 1.0f, 1.0f), litFactor, blend));
        straightColor.rgb *= lightingFactor;
    }

    float4 sandColor = float4(straightColor.rgb * straightColor.a, straightColor.a);
    // Keep the ring readable as it crosses visible material too. Alpha is left
    // unchanged for occupied cells; only premultiplied RGB receives the flash.
    sandColor.rgb = saturate(sandColor.rgb + shockwaveColor * shockwaveAlpha * sandColor.a);
    return sandColor;
}
