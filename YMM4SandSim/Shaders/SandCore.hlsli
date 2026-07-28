#ifndef YMM4_SAND_CORE_HLSLI
#define YMM4_SAND_CORE_HLSLI

cbuffer SandConstants : register(b0)
{
    uint SourceWidth;
    uint SourceHeight;
    uint StateWidth;
    uint StateHeight;

    uint ParticleSize;
    uint FrameIndex;
    uint StepIndex;
    uint Seed;

    float AlphaThreshold;
    float LuminanceThreshold;
    float Spread;
    float ReactionStrength;

    uint MaskMode;
    uint InitializeMode;
    uint LogicalStateWidth;
    uint LogicalStateHeight;

    uint MaterialAssignment;
    uint SingleMaterial;
    uint ColorMode;
    float PhysicsBreakStrength;

    uint FireLifetimeSteps;
    uint EmberLifetimeSteps;
    uint SmokeLifetimeSteps;
    uint SteamLifetimeSteps;

    uint SolidPhysicsMode;
    uint PhysicsPass;
    uint PhysicsPhase;
    uint PhysicsSolverIterations;

    float PhysicsDeltaTime;
    float PhysicsGravity;
    float PhysicsCompliance;
    float PhysicsDamping;

    float ExplosionStrength;
    float ExplosionRadius;
    float ExplosionDecay;
    float ExplosionFalloff;

    uint ManualExplosionCellX;
    uint ManualExplosionCellY;
    uint ManualExplosionEnabled;
    uint ManualExplosionWaveStep;

    float LightingStrength;
    float LightingRadius;
    float AmbientLight;
    float ShadowStrength;

};

static const uint MaterialEmpty = 0u;
static const uint MaterialSand = 1u;
static const uint MaterialWater = 2u;
static const uint MaterialSalt = 3u;
static const uint MaterialWood = 4u;
static const uint MaterialFire = 5u;
static const uint MaterialSmoke = 6u;
static const uint MaterialEmber = 7u;
static const uint MaterialSteam = 8u;
static const uint MaterialGunpowder = 9u;
static const uint MaterialOil = 10u;
static const uint MaterialLava = 11u;
static const uint MaterialStone = 12u;
static const uint MaterialAcid = 13u;
static const uint MaterialSandstone = 14u;
static const uint MaterialSnow = 15u;
static const uint MaterialCoal = 16u;
static const uint MaterialMetal = 17u;
static const uint MaterialBrick = 18u;
static const uint MaterialAmethyst = 19u;
static const uint MaterialPlant = 20u;
static const uint MaterialSlime = 21u;
static const uint MaterialSoil = 22u;
static const uint MaterialInk = 23u;
static const uint MaterialOxidizedCopper = 24u;
static const uint MaterialIce = 25u;
static const uint MaterialLiquidNitrogen = 26u;
static const uint MaterialLapisLazuli = 27u;
static const uint MaterialPermafrost = 28u;
static const uint MaterialCobaltGlass = 29u;
static const uint MaterialAzurite = 30u;
static const uint MaterialFluorite = 31u;
static const uint MaterialPurpur = 32u;
static const uint MaterialCharoite = 33u;
static const uint MaterialRoseQuartz = 34u;
static const uint MaterialPinkWax = 35u;
static const uint MaterialPotassiumPermanganate = 36u;
static const uint MaterialCoral = 37u;
static const uint MaterialPinkSalt = 38u;
static const uint MaterialRuby = 39u;
static const uint MaterialCopper = 40u;
static const uint MaterialRust = 41u;
static const uint MaterialCalcite = 42u;
static const uint MaterialAmber = 43u;
static const uint MaterialSulfur = 44u;
static const uint MaterialGold = 45u;
static const uint MaterialEndStone = 46u;
static const uint MaterialMoss = 47u;
static const uint MaterialJade = 48u;
static const uint MaterialGrass = 49u;
static const uint MaterialAlgae = 50u;
static const uint MaterialLeaf = 51u;
static const uint MaterialSeaLantern = 52u;
static const uint MaterialVerdigris = 53u;
static const uint MaterialPineNeedles = 54u;
static const uint MaterialPrismarine = 55u;
static const uint MaterialSeaWater = 56u;
static const uint MaterialQuartz = 57u;

// 6-bit material id, 12-bit age, 14 spare bits.
static const uint MaterialMask = 0x0000003fu;
static const uint AgeMask = 0x0003ffc0u;
static const uint AgeShift = 6u;
static const uint MaximumAge = 4095u;

// The upper six metadata bits are reserved for one-shot simulation events.
// ExplosionEventFlag is consumed by SandExplosionUpdate exactly once, so an
// ignited gunpowder cell cannot retrigger the blast on every later CA step.
static const uint ExplosionEventFlag = 0x04000000u;

uint Hash(uint value)
{
    value ^= value >> 16;
    value *= 0x7feb352du;
    value ^= value >> 15;
    value *= 0x846ca68bu;
    value ^= value >> 16;
    return value;
}

uint HashCell(uint2 cell, uint salt)
{
    return Hash(cell.x ^ Hash(cell.y + 0x9e3779b9u) ^ Hash(salt + FrameIndex * 0x85ebca6bu) ^ Seed);
}

float HashUnit(uint2 cell, uint salt)
{
    return (HashCell(cell, salt) & 0x00ffffffu) / 16777216.0f;
}

bool ChanceUnscaled(uint2 cell, uint salt, float probability)
{
    return HashUnit(cell, salt) < saturate(probability);
}

bool Chance(uint2 cell, uint salt, float probability)
{
    return ChanceUnscaled(cell, salt, probability * ReactionStrength);
}

uint GetMaterial(uint meta)
{
    return meta & MaterialMask;
}

uint GetAge(uint meta)
{
    return (meta & AgeMask) >> AgeShift;
}

uint MakeMeta(uint material, uint age)
{
    return (material & MaterialMask) |
           ((min(age, MaximumAge) << AgeShift) & AgeMask);
}

uint SetAge(uint meta, uint age)
{
    return (meta & ~AgeMask) | ((min(age, MaximumAge) << AgeShift) & AgeMask);
}

bool HasExplosionEvent(uint meta)
{
    return (meta & ExplosionEventFlag) != 0u;
}

uint ClearExplosionEvent(uint meta)
{
    return meta & ~ExplosionEventFlag;
}

bool IsOccupiedMeta(uint meta)
{
    return GetMaterial(meta) != MaterialEmpty;
}

uint PackColor(float4 straightColor)
{
    const uint4 rgba = (uint4)round(saturate(straightColor) * 255.0f);
    const uint alpha = max(rgba.a, 1u);
    return rgba.r | (rgba.g << 8u) | (rgba.b << 16u) | (alpha << 24u);
}

float4 UnpackColor(uint packedColor)
{
    return float4(
        packedColor & 255u,
        (packedColor >> 8u) & 255u,
        (packedColor >> 16u) & 255u,
        (packedColor >> 24u) & 255u) / 255.0f;
}

#endif
