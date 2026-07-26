#ifndef YMM4_SAND_LIGHTING_HLSLI
#define YMM4_SAND_LIGHTING_HLSLI

#include "SandBehavior.hlsli"

float3 MaterialEmission(uint material)
{
    if (material == MaterialFire) return float3(1.00f, 0.28f, 0.04f);
    if (material == MaterialEmber) return float3(0.70f, 0.252f, 0.042f);
    if (material == MaterialLava) return float3(1.00f, 0.18f, 0.02f);
    if (material == MaterialSeaLantern) return float3(0.289f, 0.8075f, 0.85f);
    return 0.0f;
}

float MaterialLightTransmission(uint material)
{
    if (material == MaterialEmpty) return 1.00f;
    if (material == MaterialFire || material == MaterialEmber ||
        material == MaterialLava || material == MaterialSeaLantern) return 1.00f;
    if (material == MaterialSteam) return 0.88f;
    if (material == MaterialSmoke) return 0.55f;
    if (material == MaterialWater || material == MaterialSeaWater || material == MaterialLiquidNitrogen) return 0.90f;
    if (material == MaterialOil) return 0.72f;
    if (material == MaterialAcid || material == MaterialSlime) return 0.68f;
    if (material == MaterialInk) return 0.28f;
    // Translucent solids need explicit optical behaviour before the generic
    // fixed-solid fallback. Treating glass/ice/quartz like stone made them cast
    // nearly black shadows despite their visual/material identity.
    if (material == MaterialCobaltGlass) return 0.84f;
    if (material == MaterialIce) return 0.72f;
    if (material == MaterialQuartz) return 0.62f;
    if (material == MaterialPinkWax) return 0.52f;
    if (material == MaterialRoseQuartz || material == MaterialFluorite) return 0.48f;
    if (material == MaterialAmethyst || material == MaterialAmber) return 0.36f;
    if (IsGas(material)) return 0.82f;
    if (IsLiquid(material)) return 0.70f;
    if (IsPowder(material)) return 0.16f;
    if (IsFixed(material)) return 0.02f;
    return 0.50f;
}

uint PackLight(float3 light, float transmission)
{
    const uint3 rgb = (uint3)round(saturate(light) * 511.0f);
    const uint optical = (uint)round(saturate(transmission) * 31.0f);
    return rgb.r | (rgb.g << 9u) | (rgb.b << 18u) | (optical << 27u);
}

float3 UnpackLight(uint packed)
{
    return float3(
        packed & 511u,
        (packed >> 9u) & 511u,
        (packed >> 18u) & 511u) / 511.0f;
}

float UnpackLightTransmission(uint packed)
{
    return ((packed >> 27u) & 31u) / 31.0f;
}

#endif
