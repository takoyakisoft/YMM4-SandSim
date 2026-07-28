#ifndef YMM4_SAND_BEHAVIOR_HLSLI
#define YMM4_SAND_BEHAVIOR_HLSLI

#include "SandCore.hlsli"

// Simulation behavior is deliberately classified independently from palette
// colors. 55 palette materials share a small set of motion/reaction classes,
// so SandStep does not need a long material-by-material branch chain.

static const uint PowderMaskLow  = 0x0041820au;
static const uint PowderMaskHigh = 0x00401250u;
static const uint LiquidMaskLow  = 0x04a02c04u;
static const uint LiquidMaskHigh = 0x01000000u;
static const uint GasMaskLow     = 0x000001e0u;
static const uint GasMaskHigh    = 0x00000000u;

static const uint WaterLikeMaskLow  = 0x00000004u;
static const uint WaterLikeMaskHigh = 0x01000000u;
static const uint ColdSolidMaskLow  = 0x12008000u;
static const uint ColdSolidMaskHigh = 0x00000000u;
static const uint OrganicMaskLow    = 0x00110010u;
static const uint OrganicMaskHigh   = 0x004e8808u;
static const uint HeatMaskLow       = 0x000008a0u;
static const uint HeatMaskHigh      = 0x00000000u;

bool MaterialInSet(uint material, uint lowMask, uint highMask)
{
    if (material < 32u)
        return (lowMask & (1u << material)) != 0u;
    return (highMask & (1u << (material - 32u))) != 0u;
}

bool IsPowder(uint material)
{
    return MaterialInSet(material, PowderMaskLow, PowderMaskHigh);
}

bool IsLiquid(uint material)
{
    return MaterialInSet(material, LiquidMaskLow, LiquidMaskHigh);
}

bool IsGas(uint material)
{
    return MaterialInSet(material, GasMaskLow, GasMaskHigh);
}

bool IsFixed(uint material)
{
    // Metadata reserves six bits for the material id, but only 1..57 are
    // defined. Never let a corrupted/spare id (58..63) silently become a
    // stationary/XPBD solid just because it is absent from the movement masks.
    return material >= MaterialSand && material <= MaterialQuartz &&
           !MaterialInSet(material, PowderMaskLow | LiquidMaskLow | GasMaskLow,
                          PowderMaskHigh | LiquidMaskHigh | GasMaskHigh);
}

bool IsRigidPhysicsMaterial(uint material)
{
    // Powder/liquid/gas stay in CA; every other valid material is XPBD-owned.
    return IsFixed(material);
}

// Dimensionless XPBD material properties: x=density relative to water,
// y=compliance scale, z=per-substep velocity retention, w=tensile break strain.
// Densities follow representative bulk/material values where meaningful;
// fictional materials use nearby real-world analogues. Compliance and break
// strain stay gameplay-scaled because the lattice operates in cell units.
float4 RigidProperties(uint material)
{
    if (material == MaterialWood) return float4(0.65f, 2.50f, 0.9920f, 0.32f);
    if (material == MaterialStone) return float4(2.60f, 0.20f, 0.9995f, 0.12f);
    if (material == MaterialSandstone) return float4(2.20f, 0.75f, 0.9960f, 0.07f);
    if (material == MaterialMetal) return float4(7.85f, 0.08f, 1.0000f, 0.35f);
    if (material == MaterialBrick) return float4(1.90f, 0.30f, 0.9980f, 0.08f);
    if (material == MaterialAmethyst) return float4(2.65f, 0.12f, 0.9980f, 0.08f);
    if (material == MaterialPlant) return float4(0.45f, 25.0f, 0.9800f, 0.65f);
    if (material == MaterialOxidizedCopper) return float4(6.00f, 0.45f, 0.9970f, 0.18f);
    if (material == MaterialIce) return float4(0.917f, 0.35f, 0.9980f, 0.06f);
    if (material == MaterialLapisLazuli) return float4(2.75f, 0.20f, 0.9980f, 0.10f);
    if (material == MaterialPermafrost) return float4(1.40f, 0.55f, 0.9960f, 0.12f);
    if (material == MaterialCobaltGlass) return float4(2.50f, 0.24f, 0.9980f, 0.04f);
    if (material == MaterialAzurite) return float4(3.80f, 0.28f, 0.9970f, 0.08f);
    if (material == MaterialFluorite) return float4(3.18f, 0.22f, 0.9980f, 0.08f);
    if (material == MaterialPurpur) return float4(1.70f, 0.55f, 0.9980f, 0.15f);
    if (material == MaterialCharoite) return float4(2.60f, 0.20f, 0.9980f, 0.10f);
    if (material == MaterialRoseQuartz) return float4(2.65f, 0.12f, 0.9980f, 0.08f);
    if (material == MaterialPinkWax) return float4(0.90f, 40.0f, 0.9850f, 0.90f);
    if (material == MaterialCoral) return float4(1.60f, 0.75f, 0.9950f, 0.06f);
    if (material == MaterialRuby) return float4(4.00f, 0.10f, 0.9990f, 0.08f);
    if (material == MaterialCopper) return float4(8.96f, 0.12f, 1.0000f, 0.42f);
    if (material == MaterialCalcite) return float4(2.71f, 0.35f, 0.9970f, 0.06f);
    if (material == MaterialAmber) return float4(1.08f, 1.50f, 0.9900f, 0.10f);
    if (material == MaterialGold) return float4(19.30f, 0.18f, 1.0000f, 0.60f);
    if (material == MaterialEndStone) return float4(1.70f, 0.55f, 0.9980f, 0.16f);
    if (material == MaterialMoss) return float4(0.30f, 60.0f, 0.9750f, 0.70f);
    if (material == MaterialJade) return float4(3.00f, 0.15f, 0.9990f, 0.18f);
    if (material == MaterialGrass) return float4(0.30f, 50.0f, 0.9750f, 0.70f);
    if (material == MaterialAlgae) return float4(0.25f, 80.0f, 0.9700f, 0.75f);
    if (material == MaterialLeaf) return float4(0.25f, 70.0f, 0.9700f, 0.75f);
    if (material == MaterialSeaLantern) return float4(1.80f, 0.30f, 0.9980f, 0.13f);
    if (material == MaterialVerdigris) return float4(3.60f, 0.50f, 0.9960f, 0.16f);
    if (material == MaterialPrismarine) return float4(2.10f, 0.30f, 0.9980f, 0.13f);
    if (material == MaterialQuartz) return float4(2.65f, 0.12f, 0.9990f, 0.08f);
    return float4(1.50f, 1.00f, 0.9980f, 0.20f);
}

// x=density relative to water, y=rigid velocity retention while overlapping it.
float2 FluidProperties(uint material)
{
    if (material == MaterialLiquidNitrogen) return float2(0.808f, 0.990f);
    if (material == MaterialOil) return float2(0.82f, 0.970f);
    if (material == MaterialWater) return float2(1.00f, 0.982f);
    if (material == MaterialSeaWater) return float2(1.025f, 0.980f);
    if (material == MaterialInk) return float2(1.05f, 0.960f);
    if (material == MaterialAcid) return float2(1.10f, 0.975f);
    if (material == MaterialSlime) return float2(1.20f, 0.930f);
    if (material == MaterialLava) return float2(2.70f, 0.900f);
    return float2(0.0f, 1.0f);
}

float RigidPairComplianceScale(float4 propertiesA, float4 propertiesB, bool sameMaterial)
{
    const float baseScale = max(propertiesA.y, propertiesB.y);
    return sameMaterial ? baseScale : baseScale * 1.75f;
}

float RigidPairBreakStrain(float4 propertiesA, float4 propertiesB, bool sameMaterial)
{
    const float baseStrain = min(propertiesA.w, propertiesB.w);
    return sameMaterial ? baseStrain : baseStrain * 0.70f;
}

static const float BrokenRigidBondMarker = 1.0e20f;

bool IsBrokenRigidBond(float lambda)
{
    return lambda >= BrokenRigidBondMarker * 0.5f;
}

bool IsWaterLike(uint material)
{
    return MaterialInSet(material, WaterLikeMaskLow, WaterLikeMaskHigh);
}

bool IsColdSolid(uint material)
{
    return MaterialInSet(material, ColdSolidMaskLow, ColdSolidMaskHigh);
}

bool IsOrganic(uint material)
{
    return MaterialInSet(material, OrganicMaskLow, OrganicMaskHigh);
}

bool IsHeat(uint material)
{
    return MaterialInSet(material, HeatMaskLow, HeatMaskHigh);
}

static const uint InactiveManualExplosionWaveStep = 0xffffffffu;

bool HasManualExplosionWave()
{
    return ManualExplosionWaveStep != InactiveManualExplosionWaveStep;
}

float ManualExplosionDistance(uint2 cell)
{
    const float2 delta = float2(cell) - float2(ManualExplosionCellX, ManualExplosionCellY);
    return length(delta);
}

bool IsInsideManualExplosionRegion(uint2 cell)
{
    return HasManualExplosionWave() &&
        ManualExplosionDistance(cell) <= max(ExplosionRadius, 1.0f) + 1.0f;
}

float ManualExplosionWaveMask(uint2 cell)
{
    if (!HasManualExplosionWave())
        return 0.0f;

    const float waveRadius = (float)ManualExplosionWaveStep;
    if (waveRadius > max(ExplosionRadius, 1.0f))
        return 0.0f;

    const float distance = ManualExplosionDistance(cell);
    const float halfWidth = 0.75f;
    return saturate(1.0f - abs(distance - waveRadius) / halfWidth);
}

float ManualExplosionBlastMask(uint2 cell)
{
    if (!HasManualExplosionWave())
        return 0.0f;

    const float waveRadius = (float)ManualExplosionWaveStep;
    const float distance = ManualExplosionDistance(cell);
    if (waveRadius > max(ExplosionRadius, 1.0f) || distance > waveRadius + 0.75f)
        return 0.0f;

    // Keep the visible front thin, but let high-strength explosions leave a
    // wider pressure wake. Rigid/CA material is therefore pushed for several
    // safe substeps instead of strength disappearing into a one-step velocity cap.
    const float strengthScale = sqrt(max(ExplosionStrength, 0.0f));
    // The host advances the controller front in about six iterations. Make the
    // wake at least one radial stride wide so no cells are skipped when a large
    // radius jumps several cells between simulation iterations.
    const float propagationStride = max(ceil(max(ExplosionRadius, 1.0f) / 6.0f), 1.0f);
    const float trailWidth = propagationStride + 1.0f + strengthScale;
    const float behindFront = max(waveRadius - distance, 0.0f);
    const float trail = saturate(1.0f - behindFront / trailWidth);
    return max(ManualExplosionWaveMask(cell), trail);
}

float ManualExplosionCavityRadius()
{
    const float radius = max(ExplosionRadius, 1.0f);
    const float intensityScale = max(
        sqrt(sqrt(max(ExplosionStrength, 0.01f))), 0.60f);
    // Radius is the semantic boundary of the effect. Strength may carve more of
    // that radius, but there is no unrelated fixed cell-count ceiling.
    return min(radius, max(radius * 0.18f * intensityScale, 1.5f));
}

// Fraction of a pressure wave that enters a cell occupied by this material.
// This is deliberately a coarse gameplay model rather than an acoustic solver:
// gases transmit a blast almost freely, liquids damp it slightly, loose powder
// shields more, and dense/rigid solids attenuate it strongly. A non-zero solid
// transmission lets a surface receive enough pressure to fracture while thick
// walls still create a pressure shadow behind them.
float ExplosionPressureTransmission(uint material)
{
    if (material == MaterialEmpty || IsGas(material)) return 1.00f;
    if (IsLiquid(material)) return material == MaterialSlime ? 0.78f : 0.88f;
    if (IsPowder(material)) return 0.62f;
    // Pink wax uses its dedicated soft-solid response before the broader organic class.
    if (material == MaterialPinkWax || material == MaterialIce || material == MaterialCobaltGlass) return 0.40f;
    if (IsOrganic(material)) return 0.46f;
    if (material == MaterialGold || material == MaterialCopper || material == MaterialMetal ||
        material == MaterialOxidizedCopper || material == MaterialVerdigris) return 0.24f;
    if (IsFixed(material))
        return clamp(0.52f / sqrt(max(RigidProperties(material).x, 0.25f)), 0.24f, 0.42f);
    return 1.00f;
}

// Only relative ordering is used by the CA swap rules. Liquid ranks follow
// FluidProperties().x so CA stratification and XPBD buoyancy agree.
uint DensityRank(uint material)
{
    if (material == MaterialEmpty) return 0u;
    if (material == MaterialFire) return 1u;
    if (material == MaterialEmber) return 2u;
    if (material == MaterialSteam) return 3u;
    if (material == MaterialSmoke) return 4u;
    if (material == MaterialSnow || material == MaterialPineNeedles) return 5u;
    // Keep liquid buoyancy ordering consistent with FluidProperties().x. These are
    // relative ranks only; equal/near-equal real densities still get a stable
    // deterministic order for the cellular swap rules.
    if (material == MaterialLiquidNitrogen) return 6u;
    if (material == MaterialOil) return 7u;
    if (material == MaterialWater) return 8u;
    if (material == MaterialSeaWater) return 9u;
    if (material == MaterialInk) return 10u;
    if (material == MaterialAcid) return 11u;
    if (material == MaterialSlime) return 12u;
    if (material == MaterialCoal || material == MaterialSoil) return 13u;
    if (material == MaterialGunpowder) return 14u;
    if (material == MaterialSulfur) return 15u;
    if (material == MaterialSalt || material == MaterialPinkSalt) return 16u;
    if (material == MaterialSand) return 17u;
    if (material == MaterialLava) return 18u;
    if (material == MaterialPotassiumPermanganate) return 19u;
    if (material == MaterialRust) return 20u;
    return 63u;
}

float Mobility(uint material)
{
    if (material == MaterialWater || material == MaterialLiquidNitrogen || material == MaterialFire) return 1.00f;
    if (material == MaterialSeaWater || material == MaterialAcid || material == MaterialEmber) return 0.95f;
    if (material == MaterialSteam) return 0.90f;
    if (material == MaterialSnow) return 0.88f;
    if (material == MaterialOil || material == MaterialSalt || material == MaterialPinkSalt) return 0.85f;
    if (material == MaterialPineNeedles) return 0.82f;
    if (material == MaterialSand) return 0.80f;
    if (material == MaterialSmoke || material == MaterialGunpowder || material == MaterialSulfur) return 0.75f;
    if (material == MaterialInk) return 0.72f;
    if (material == MaterialCoal) return 0.70f;
    if (material == MaterialSoil || material == MaterialRust || material == MaterialPotassiumPermanganate) return 0.62f;
    if (material == MaterialLava) return 0.30f;
    if (material == MaterialSlime) return 0.28f;
    return 0.0f;
}

bool CanMoveDownInto(uint mover, uint target)
{
    const bool movable = IsPowder(mover) || IsLiquid(mover);
    if (target == MaterialEmpty)
        return movable;
    return movable && IsLiquid(target) && DensityRank(mover) > DensityRank(target);
}

bool CanMoveUpInto(uint mover, uint target)
{
    if (!IsGas(mover))
        return false;
    if (target == MaterialEmpty)
        return true;
    return !IsFixed(target) && DensityRank(mover) < DensityRank(target);
}

float IgnitionProbability(uint heat, uint target)
{
    if (target == MaterialGunpowder) return heat == MaterialLava ? 1.0f : 0.5f;
    if (target == MaterialSulfur) return heat == MaterialLava ? 1.0f : 0.35f;
    if (target == MaterialOil) return 1.0f / 6.0f;
    if (target == MaterialPinkWax || target == MaterialAmber) return 1.0f / 81.0f;
    if (target == MaterialCoal) return heat == MaterialEmber ? 1.0f / 301.0f : 1.0f / 151.0f;
    if (IsOrganic(target)) return heat == MaterialEmber ? 1.0f / 201.0f : 1.0f / 101.0f;
    return 0.0f;
}

float AcidProbability(uint target)
{
    if (target == MaterialEmpty || target == MaterialAcid || IsWaterLike(target)) return 0.0f;
    if (target == MaterialCobaltGlass || target == MaterialSeaLantern) return 0.0f;
    if (IsOrganic(target)) return 1.0f / 101.0f;
    if (IsPowder(target)) return 1.0f / 51.0f;
    if (target == MaterialMetal || target == MaterialCopper || target == MaterialOxidizedCopper || target == MaterialVerdigris)
        return 1.0f / 151.0f;
    if (IsFixed(target)) return 1.0f / 301.0f;
    return 0.0f;
}

// SandStep never performs palette classification. This tiny fallback only
// covers materials created by simulation reactions when a source color is
// unavailable; normal particles preserve their packed source color.
float4 TransitionMaterialColor(uint material)
{
    if (material == MaterialFire) return float4(0.894117647f, 0.360784314f, 0.062745098f, 1.0f);
    if (material == MaterialSmoke) return float4(0.470588235f, 0.470588235f, 0.470588235f, 1.0f);
    if (material == MaterialEmber) return float4(0.784313725f, 0.470588235f, 0.078431373f, 1.0f);
    if (material == MaterialSteam) return float4(0.643137255f, 0.894117647f, 0.988235294f, 1.0f);
    if (material == MaterialWater) return float4(0.000000000f, 0.470588235f, 0.972549020f, 1.0f);
    if (material == MaterialOil) return float4(0.000000000f, 0.250980392f, 0.345098039f, 1.0f);
    if (material == MaterialStone) return float4(0.486274510f, 0.486274510f, 0.486274510f, 1.0f);
    if (material == MaterialOxidizedCopper) return float4(0.000000000f, 0.658823529f, 0.266666667f, 1.0f);
    if (material == MaterialIce) return float4(0.000000000f, 0.988235294f, 0.988235294f, 1.0f);
    return float4(1.0f, 1.0f, 1.0f, 1.0f);
}

#endif
