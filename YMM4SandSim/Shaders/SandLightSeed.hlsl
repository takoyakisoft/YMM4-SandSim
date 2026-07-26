#include "SandLighting.hlsli"

Texture2D<uint> CellularMeta : register(t0);
Texture2D<uint> RigidOccupancy : register(t1);
Texture2D<uint> RigidMeta : register(t2);
Texture2D<float> ExplosionPressure : register(t3);
RWTexture2D<uint> LightField : register(u0);

static const uint EmptyRigidOwner = 0xffffffffu;

uint MaterialAt(uint2 cell)
{
    // Initialize first so FXC /WX can prove the return value is assigned.
    uint material = GetMaterial(CellularMeta.Load(int3(cell, 0)));
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

[numthreads(8, 8, 1)]
void main(uint3 dispatchThreadId : SV_DispatchThreadID)
{
    const uint2 id = dispatchThreadId.xy;
    if (id.x >= StateWidth || id.y >= StateHeight)
        return;
    if (id.x >= LogicalStateWidth || id.y >= LogicalStateHeight)
    {
        LightField[id] = 0u;
        return;
    }

    const uint material = MaterialAt(id);
    float3 light = MaterialEmission(material);

    // The pressure wave doubles as a short warm flash. It is derived from the
    // same deterministic explosion field that drives CA/XPBD motion, so light,
    // debris and fracture stay synchronized without a separate event list.
    if (ExplosionStrength > 0.0f)
    {
        const float flash = saturate(ExplosionPressure.Load(int3(id, 0)) * ExplosionStrength);
        light = max(light, float3(1.00f, 0.48f, 0.10f) * flash);
    }
    const float transmission = lerp(1.0f, MaterialLightTransmission(material), saturate(ShadowStrength));
    LightField[id] = PackLight(light, transmission);
}
