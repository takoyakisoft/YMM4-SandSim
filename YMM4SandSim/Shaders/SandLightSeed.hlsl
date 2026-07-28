#include "SandLighting.hlsli"

Texture2D<uint> CellularMeta : register(t0);
Texture2D<uint> RigidOccupancy : register(t1);
Texture2D<uint> RigidMeta : register(t2);
Texture2D<float> ExplosionPressure : register(t3);
RWTexture2D<uint> LightField : register(u0);

static const uint EmptyRigidOwner = 0xffffffffu;

float ReadExplosionPressure(int2 cell)
{
    if (cell.x < 0 || cell.y < 0 ||
        cell.x >= (int)LogicalStateWidth || cell.y >= (int)LogicalStateHeight)
        return 0.0f;
    return ExplosionPressure.Load(int3(cell, 0));
}

float ExplosionFrontAt(uint2 cell, float pressure)
{
    if (pressure <= 0.0f)
        return 0.0f;

    const int2 p = int2(cell);
    // A wave-front cell has pressure while at least one neighbour is still
    // untouched. Highlight that one-cell boundary instead of the filled field,
    // so the flash reads as a clean expanding shock ring.
    float minimumNeighbour = ReadExplosionPressure(p + int2(-1, -1));
    minimumNeighbour = min(minimumNeighbour, ReadExplosionPressure(p + int2( 0, -1)));
    minimumNeighbour = min(minimumNeighbour, ReadExplosionPressure(p + int2( 1, -1)));
    minimumNeighbour = min(minimumNeighbour, ReadExplosionPressure(p + int2(-1,  0)));
    minimumNeighbour = min(minimumNeighbour, ReadExplosionPressure(p + int2( 1,  0)));
    minimumNeighbour = min(minimumNeighbour, ReadExplosionPressure(p + int2(-1,  1)));
    minimumNeighbour = min(minimumNeighbour, ReadExplosionPressure(p + int2( 0,  1)));
    minimumNeighbour = min(minimumNeighbour, ReadExplosionPressure(p + int2( 1,  1)));

    return minimumNeighbour < 0.001f ? saturate(pressure * 2.5f) : 0.0f;
}

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
    float explosionFront = 0.0f;

    // The pressure wave doubles as a short warm flash. It is derived from the
    // same deterministic explosion field that drives CA/XPBD motion, so light,
    // debris and fracture stay synchronized without a separate event list.
    if (ExplosionStrength > 0.0f)
    {
        const float pressure = ReadExplosionPressure(int2(id));
        float visiblePressure = pressure;
        if (IsInsideManualExplosionRegion(id))
        {
            const float radialFront = ManualExplosionWaveMask(id);
            visiblePressure *= radialFront;
            explosionFront = radialFront * saturate(pressure * 2.5f);
        }
        else
        {
            explosionFront = ExplosionFrontAt(id, pressure);
        }
        const float core = saturate(visiblePressure * 0.10f);
        const float flash = saturate(max(explosionFront, core) * ExplosionStrength);
        light = max(light, float3(1.00f, 0.48f, 0.10f) * flash);
    }

    float transmission = lerp(1.0f, MaterialLightTransmission(material), saturate(ShadowStrength));
    // The 5-bit optical channel has one otherwise-unused code immediately below
    // fully transparent empty space. Mark only empty shock-front cells with it.
    // SandLightPropagate preserves the current cell's optical code, so the marker
    // survives lighting iterations without spreading to neighbouring cells.
    if (material == MaterialEmpty && explosionFront > 0.0f)
        transmission = ShockwaveLightTransmission;

    LightField[id] = PackLight(light, transmission);
}
