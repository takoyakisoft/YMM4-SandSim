#include "SandBehavior.hlsli"

Texture2D<uint> SourceColor : register(t0);
Texture2D<uint> SourceMeta : register(t1);
Texture2D<uint> RigidOccupancy : register(t2);
Texture2D<float> ExplosionPressure : register(t3);
RWTexture2D<uint> DestinationColor : register(u0);
RWTexture2D<uint> DestinationMeta : register(u1);

struct Cell
{
    uint Color;
    uint Meta;
};

Cell LoadCell(uint2 position)
{
    Cell cell;
    cell.Color = SourceColor.Load(int3(position, 0));
    cell.Meta = SourceMeta.Load(int3(position, 0));
    return cell;
}

void StoreCell(uint2 position, Cell cell)
{
    DestinationColor[position] = cell.Color;
    DestinationMeta[position] = cell.Meta;
}

Cell EmptyCell()
{
    Cell cell;
    cell.Color = 0u;
    cell.Meta = 0u;
    return cell;
}

static const uint EmptyRigidOwner = 0xffffffffu;

bool IsRigidOccupied(uint2 position)
{
    if (SolidPhysicsMode != 1u)
        return false;
    return RigidOccupancy.Load(int3(position, 0)) != EmptyRigidOwner;
}

uint EffectiveMaterial(Cell cell, bool rigidOccupied)
{
    return rigidOccupied ? MaterialStone : GetMaterial(cell.Meta);
}

bool HasPendingExplosion(Cell cell)
{
    return HasExplosionEvent(cell.Meta);
}

void SwapCells(inout Cell first, inout Cell second)
{
    Cell temporary = first;
    first = second;
    second = temporary;
}

void SetMaterial(inout Cell cell, uint material)
{
    if (material == MaterialEmpty)
    {
        cell = EmptyCell();
        return;
    }

    // A material transition changes behavior, not the source artwork. Keep the
    // packed source color in state even while palette rendering is selected,
    // so ColorMode can be changed later without rebuilding simulation history.
    const uint preservedColor = cell.Color;
    cell.Meta = MakeMeta(material, 0u);
    cell.Color = preservedColor != 0u
        ? preservedColor
        : PackColor(TransitionMaterialColor(material));
}

void SetMaterialFromSource(inout Cell destination, Cell source, uint material)
{
    SetMaterial(destination, material);
    if (source.Color != 0u)
        destination.Color = source.Color;
}

void AdvanceLifetime(inout Cell cell, uint2 block, uint salt)
{
    const uint material = GetMaterial(cell.Meta);
    if (material == MaterialEmpty)
        return;

    const uint age = min(GetAge(cell.Meta) + 1u, MaximumAge);
    cell.Meta = SetAge(cell.Meta, age);

    if (material == MaterialEmber && age >= EmberLifetimeSteps)
    {
        cell = EmptyCell();
    }
    else if (material == MaterialSmoke && age >= SmokeLifetimeSteps)
    {
        cell = EmptyCell();
    }
    else if (material == MaterialSteam && age >= SteamLifetimeSteps)
    {
        cell = EmptyCell();
    }
    else if (material == MaterialFire && age >= FireLifetimeSteps && ChanceUnscaled(block, salt, 1.0f / 404.0f))
    {
        if (ChanceUnscaled(block, salt + 1u, 0.60f))
            SetMaterial(cell, MaterialSmoke);
        else
            cell = EmptyCell();
    }
}

void ReactWaterAndHeat(inout Cell water, inout Cell heat, uint heatMaterial, uint2 block, uint salt)
{
    if (!Chance(block, salt, 0.5f))
        return;

    if (heatMaterial == MaterialLava)
        SetMaterial(heat, MaterialStone);
    else
        heat = EmptyCell();
    SetMaterial(water, MaterialSteam);
}

void ReactColdSolidAndHeat(inout Cell cold, inout Cell heat, uint heatMaterial, uint2 block, uint salt)
{
    if (!Chance(block, salt, 0.65f))
        return;

    if (heatMaterial == MaterialLava)
    {
        SetMaterialFromSource(cold, cold, MaterialSteam);
        SetMaterial(heat, MaterialStone);
    }
    else
    {
        SetMaterialFromSource(cold, cold, MaterialWater);
        heat = EmptyCell();
    }
}

void ReactWaxAndHeat(inout Cell wax, inout Cell heat, uint2 block, uint salt)
{
    if (!Chance(block, salt, 0.45f))
        return;
    SetMaterialFromSource(wax, wax, MaterialOil);
    if (GetMaterial(heat.Meta) != MaterialLava)
        heat = EmptyCell();
}

void ReactLiquidNitrogenAndWater(inout Cell nitrogen, inout Cell water, uint2 block, uint salt)
{
    if (!Chance(block, salt, 0.70f))
        return;
    SetMaterialFromSource(water, water, MaterialIce);
    nitrogen = EmptyCell();
}

void ReactLiquidNitrogenAndHeat(inout Cell nitrogen, inout Cell heat, uint heatMaterial, uint2 block, uint salt)
{
    if (!Chance(block, salt, 0.80f))
        return;
    nitrogen = EmptyCell();
    if (heatMaterial == MaterialLava)
        SetMaterial(heat, MaterialStone);
    else
        heat = EmptyCell();
}

void ReactAcidAndTarget(inout Cell acid, inout Cell target, uint targetMaterial, uint2 block, uint salt)
{
    const float probability = AcidProbability(targetMaterial);
    if (probability <= 0.0f || !Chance(block, salt, probability))
        return;

    target = acid;
    target.Meta = SetAge(target.Meta, 0u);
    acid = EmptyCell();
}

void ReactPair(inout Cell first, inout Cell second, uint2 block, uint salt)
{
    if (ReactionStrength <= 0.0f)
        return;

    uint firstMaterial = GetMaterial(first.Meta);
    uint secondMaterial = GetMaterial(second.Meta);
    if (firstMaterial == MaterialEmpty && secondMaterial == MaterialEmpty)
        return;

    // ExplosionEventFlag is a one-shot event tied to this exact ignition cell.
    // Until SandExplosionUpdate consumes it on the next iteration, keep the
    // event-bearing cell chemically and spatially stable. Otherwise a neighbour
    // can extinguish it or swap it away and move/cancel the blast origin.
    if (HasPendingExplosion(first) || HasPendingExplosion(second))
        return;

    if (firstMaterial == MaterialLiquidNitrogen && IsWaterLike(secondMaterial))
    {
        ReactLiquidNitrogenAndWater(first, second, block, salt);
        return;
    }
    if (secondMaterial == MaterialLiquidNitrogen && IsWaterLike(firstMaterial))
    {
        ReactLiquidNitrogenAndWater(second, first, block, salt);
        return;
    }
    if (firstMaterial == MaterialLiquidNitrogen && IsHeat(secondMaterial))
    {
        ReactLiquidNitrogenAndHeat(first, second, secondMaterial, block, salt);
        return;
    }
    if (secondMaterial == MaterialLiquidNitrogen && IsHeat(firstMaterial))
    {
        ReactLiquidNitrogenAndHeat(second, first, firstMaterial, block, salt);
        return;
    }

    if (IsColdSolid(firstMaterial) && IsHeat(secondMaterial))
    {
        ReactColdSolidAndHeat(first, second, secondMaterial, block, salt);
        return;
    }
    if (IsColdSolid(secondMaterial) && IsHeat(firstMaterial))
    {
        ReactColdSolidAndHeat(second, first, firstMaterial, block, salt);
        return;
    }

    if (IsWaterLike(firstMaterial) && IsHeat(secondMaterial))
    {
        ReactWaterAndHeat(first, second, secondMaterial, block, salt);
        return;
    }
    if (IsWaterLike(secondMaterial) && IsHeat(firstMaterial))
    {
        ReactWaterAndHeat(second, first, firstMaterial, block, salt);
        return;
    }

    if (firstMaterial == MaterialPinkWax && IsHeat(secondMaterial))
    {
        ReactWaxAndHeat(first, second, block, salt);
        return;
    }
    if (secondMaterial == MaterialPinkWax && IsHeat(firstMaterial))
    {
        ReactWaxAndHeat(second, first, block, salt);
        return;
    }

    if (firstMaterial == MaterialAcid && IsWaterLike(secondMaterial) && Chance(block, salt, 1.0f / 251.0f))
    {
        first = EmptyCell();
        return;
    }
    if (secondMaterial == MaterialAcid && IsWaterLike(firstMaterial) && Chance(block, salt, 1.0f / 251.0f))
    {
        second = EmptyCell();
        return;
    }

    const bool firstIsDissolvingSalt = firstMaterial == MaterialSalt || firstMaterial == MaterialPinkSalt;
    const bool secondIsDissolvingSalt = secondMaterial == MaterialSalt || secondMaterial == MaterialPinkSalt;
    if (firstIsDissolvingSalt && IsWaterLike(secondMaterial) && Chance(block, salt, 1.0f / 1001.0f))
    {
        first = EmptyCell();
        if (secondMaterial == MaterialWater)
            SetMaterialFromSource(second, second, MaterialSeaWater);
        return;
    }
    if (secondIsDissolvingSalt && IsWaterLike(firstMaterial) && Chance(block, salt, 1.0f / 1001.0f))
    {
        second = EmptyCell();
        if (firstMaterial == MaterialWater)
            SetMaterialFromSource(first, first, MaterialSeaWater);
        return;
    }

    if (firstMaterial == MaterialCopper && secondMaterial == MaterialSeaWater && Chance(block, salt, 1.0f / 401.0f))
    {
        SetMaterial(first, MaterialOxidizedCopper);
        return;
    }
    if (secondMaterial == MaterialCopper && firstMaterial == MaterialSeaWater && Chance(block, salt, 1.0f / 401.0f))
    {
        SetMaterial(second, MaterialOxidizedCopper);
        return;
    }

    if (firstMaterial == MaterialAcid)
    {
        ReactAcidAndTarget(first, second, secondMaterial, block, salt);
        if (GetMaterial(first.Meta) == MaterialEmpty)
            return;
    }
    if (secondMaterial == MaterialAcid)
    {
        ReactAcidAndTarget(second, first, firstMaterial, block, salt);
        if (GetMaterial(second.Meta) == MaterialEmpty)
            return;
    }

    firstMaterial = GetMaterial(first.Meta);
    secondMaterial = GetMaterial(second.Meta);

    if (IsHeat(firstMaterial))
    {
        const float probability = IgnitionProbability(firstMaterial, secondMaterial);
        if (probability > 0.0f && Chance(block, salt, probability))
        {
            const bool explosive = secondMaterial == MaterialGunpowder;
            SetMaterial(second, MaterialFire);
            if (explosive && ExplosionStrength > 0.0f)
                second.Meta |= ExplosionEventFlag;
            return;
        }
    }
    if (IsHeat(secondMaterial))
    {
        const float probability = IgnitionProbability(secondMaterial, firstMaterial);
        if (probability > 0.0f && Chance(block, salt, probability))
        {
            const bool explosive = firstMaterial == MaterialGunpowder;
            SetMaterial(first, MaterialFire);
            if (explosive && ExplosionStrength > 0.0f)
                first.Meta |= ExplosionEventFlag;
            return;
        }
    }

    firstMaterial = GetMaterial(first.Meta);
    secondMaterial = GetMaterial(second.Meta);
    if (IsHeat(firstMaterial) && secondMaterial == MaterialEmpty)
    {
        if (Chance(block, salt, 0.0020f))
            SetMaterialFromSource(second, first, MaterialSmoke);
        else if (Chance(block, salt + 3u, 0.0015f))
            SetMaterialFromSource(second, first, MaterialEmber);
    }
    else if (IsHeat(secondMaterial) && firstMaterial == MaterialEmpty)
    {
        if (Chance(block, salt, 0.0020f))
            SetMaterialFromSource(first, second, MaterialSmoke);
        else if (Chance(block, salt + 3u, 0.0015f))
            SetMaterialFromSource(first, second, MaterialEmber);
    }
}

void ResolveVertical(
    inout Cell upper, bool upperRigid,
    inout Cell lower, bool lowerRigid)
{
    if (upperRigid || lowerRigid)
        return;

    const uint upperMaterial = GetMaterial(upper.Meta);
    const uint lowerMaterial = GetMaterial(lower.Meta);
    // A one-shot explosion event belongs to the ignition cell. Do not let the
    // newly-created fire particle rise before SandExplosionUpdate consumes the
    // event on the next iteration, otherwise the blast origin shifts by one cell.
    if (HasPendingExplosion(upper) || HasPendingExplosion(lower))
        return;

    const bool movesDown = CanMoveDownInto(upperMaterial, lowerMaterial);
    const bool movesUp = CanMoveUpInto(lowerMaterial, upperMaterial);

    if (movesDown || movesUp)
        SwapCells(upper, lower);
}

void TryDiagonalDown(
    inout Cell upper, bool upperRigid,
    Cell support, bool supportRigid,
    inout Cell diagonal, bool diagonalRigid,
    uint2 block, uint salt)
{
    if (upperRigid || diagonalRigid || HasPendingExplosion(upper) || HasPendingExplosion(diagonal))
        return;

    const uint material = GetMaterial(upper.Meta);
    if (!(IsPowder(material) || IsLiquid(material)))
        return;
    if (CanMoveDownInto(material, EffectiveMaterial(support, supportRigid)))
        return;
    if (!CanMoveDownInto(material, EffectiveMaterial(diagonal, diagonalRigid)))
        return;
    if (HashUnit(block, salt) >= Spread * Mobility(material))
        return;
    SwapCells(upper, diagonal);
}

void TryDiagonalUp(
    inout Cell lower, bool lowerRigid,
    Cell support, bool supportRigid,
    inout Cell diagonal, bool diagonalRigid,
    uint2 block, uint salt)
{
    if (lowerRigid || diagonalRigid || HasPendingExplosion(lower) || HasPendingExplosion(diagonal))
        return;

    const uint material = GetMaterial(lower.Meta);
    if (!IsGas(material))
        return;
    if (CanMoveUpInto(material, EffectiveMaterial(support, supportRigid)))
        return;
    if (!CanMoveUpInto(material, EffectiveMaterial(diagonal, diagonalRigid)))
        return;
    if (HashUnit(block, salt) >= Spread * Mobility(material))
        return;
    SwapCells(lower, diagonal);
}

uint TryHorizontalMover(
    inout Cell destination, bool destinationRigid,
    inout Cell moverCell, bool moverRigid,
    uint2 block, uint salt)
{
    if (destinationRigid || moverRigid || HasPendingExplosion(destination) || HasPendingExplosion(moverCell))
        return 0u;

    const uint mover = GetMaterial(moverCell.Meta);
    const uint target = GetMaterial(destination.Meta);
    uint canMove = 0u;

    // Horizontal motion is diffusion, not buoyancy. Density-driven swaps here
    // make two liquid layers exchange left/right with no gravity preference and
    // can produce interface jitter. Density ordering is already handled by the
    // vertical and diagonal rules, so lateral flow only fills empty cells.
    if ((IsLiquid(mover) || IsGas(mover)) && target == MaterialEmpty)
        canMove = 1u;

    if (canMove == 0u)
        return 0u;
    if (HashUnit(block, salt) >= Spread * Mobility(mover))
        return 0u;

    SwapCells(destination, moverCell);
    return 1u;
}

void TryHorizontal(
    inout Cell left, bool leftRigid,
    inout Cell right, bool rightRigid,
    uint2 block, uint salt)
{
    const uint rightFirst = (HashCell(block, salt) & 1u);
    if (rightFirst != 0u)
    {
        if (TryHorizontalMover(left, leftRigid, right, rightRigid, block, salt + 1u) == 0u)
            TryHorizontalMover(right, rightRigid, left, leftRigid, block, salt + 2u);
    }
    else if (TryHorizontalMover(right, rightRigid, left, leftRigid, block, salt + 1u) == 0u)
    {
        TryHorizontalMover(left, leftRigid, right, rightRigid, block, salt + 2u);
    }
}

float ExplosionPressureAt(uint2 position)
{
    if (position.x >= LogicalStateWidth || position.y >= LogicalStateHeight)
        return 0.0f;

    const float pressure = max(ExplosionPressure.Load(int3(position, 0)), 0.0f);
    if (IsInsideManualExplosionRegion(position))
        return pressure * ManualExplosionWaveMask(position);
    return pressure;
}

void TriggerGunpowderFromBlast(inout Cell cell, bool rigidOccupied, uint2 position, uint2 randomCell, uint salt)
{
    if (rigidOccupied || GetMaterial(cell.Meta) != MaterialGunpowder || ExplosionStrength <= 0.0f)
        return;

    const float blastEnergy = ExplosionPressureAt(position) * ExplosionStrength;
    if (blastEnergy <= 0.45f)
        return;

    // A shock front can set off neighbouring gunpowder before fire physically
    // reaches it. The newly-created one-shot event is consumed at the start of
    // the next CA iteration, producing deterministic GPU-only chain reactions.
    const float probability = saturate((blastEnergy - 0.45f) * 1.75f);
    if (HashUnit(randomCell, salt) >= probability)
        return;

    SetMaterial(cell, MaterialFire);
    cell.Meta |= ExplosionEventFlag;
}

void SeedManualExplosionFire(inout Cell cell, bool rigidOccupied, uint2 position, uint2 randomCell, uint salt)
{
    if (rigidOccupied || ManualExplosionEnabled == 0u || ExplosionStrength <= 0.0f)
        return;

    const float2 delta = float2(position) - float2(ManualExplosionCellX, ManualExplosionCellY);
    const float distance = length(delta);
    const float coreRadius = clamp(ExplosionRadius * 0.20f, 1.25f, 4.0f);
    if (distance > coreRadius)
        return;

    const uint material = GetMaterial(cell.Meta);
    if (material != MaterialEmpty)
    {
        // The controller must create at least one heat source even when its core
        // is completely filled. Ignite only the exact flammable center cell;
        // all subsequent spread still goes through ReactPair/ignition chemistry.
        if (distance < 0.5f && !IsHeat(material) &&
            IgnitionProbability(MaterialFire, material) > 0.0f)
        {
            SetMaterial(cell, MaterialFire);
        }
        return;
    }

    const float core = saturate(1.0f - distance / max(coreRadius, 0.001f));
    const float probability = saturate((0.20f + core * 0.65f) * ExplosionStrength);
    if (ChanceUnscaled(randomCell, salt, probability))
        SetMaterial(cell, MaterialFire);
}

void ReactCellToBlast(inout Cell cell, bool rigidOccupied, uint2 position, uint2 randomCell, uint salt)
{
    TriggerGunpowderFromBlast(cell, rigidOccupied, position, randomCell, salt);
    SeedManualExplosionFire(cell, rigidOccupied, position, randomCell, salt + 1u);
}

bool CanBlastMove(uint mover, uint target)
{
    if (mover == MaterialEmpty || IsFixed(mover))
        return false;
    if (target == MaterialEmpty)
        return true;
    if (IsGas(target) && !IsGas(mover))
        return true;
    return IsLiquid(mover) && IsGas(target);
}

void TryBlastPair(
    inout Cell first, bool firstRigid, uint2 firstPosition,
    inout Cell second, bool secondRigid, uint2 secondPosition,
    uint2 block, uint salt)
{
    if (ExplosionStrength <= 0.0f || firstRigid || secondRigid ||
        HasPendingExplosion(first) || HasPendingExplosion(second))
        return;

    const float firstPressure = ExplosionPressureAt(firstPosition);
    const float secondPressure = ExplosionPressureAt(secondPosition);
    const float difference = firstPressure - secondPressure;
    const float magnitude = abs(difference) * ExplosionStrength;
    if (magnitude < 0.015f)
        return;

    if (difference > 0.0f)
    {
        if (!CanBlastMove(GetMaterial(first.Meta), GetMaterial(second.Meta)))
            return;
    }
    else
    {
        if (!CanBlastMove(GetMaterial(second.Meta), GetMaterial(first.Meta)))
            return;
    }

    if (HashUnit(block, salt) >= saturate(magnitude * 3.0f))
        return;

    SwapCells(first, second);
}

void CopyCell(uint2 position)
{
    // CA state under a rigid occupancy is frozen rather than destroyed. This
    // preserves liquid/gas mass while the rigid lattice passes through it; the
    // rigid occupancy still blocks all CA movement for the visible cell.
    DestinationColor[position] = SourceColor.Load(int3(position, 0));
    DestinationMeta[position] = SourceMeta.Load(int3(position, 0));
}

void StoreResolvedCell(uint2 position, Cell cell, bool rigidOccupied)
{
    if (rigidOccupied)
    {
        CopyCell(position);
        return;
    }
    StoreCell(position, cell);
}

void AdvanceStandaloneCell(uint2 position, uint salt)
{
    // Shifted Margolus phases leave a one-cell border outside any 2x2 block.
    // Those cells still exist for this CA iteration, so lifetime must advance
    // exactly once even though there is no pair to react/move with. Padded
    // backing cells stay copied, and CA state hidden by a rigid occupancy stays
    // intentionally frozen just like StoreResolvedCell().
    if (position.x >= LogicalStateWidth || position.y >= LogicalStateHeight ||
        IsRigidOccupied(position))
    {
        CopyCell(position);
        return;
    }

    Cell cell = LoadCell(position);
    ReactCellToBlast(cell, false, position, position, salt + 41u);
    AdvanceLifetime(cell, position, salt);
    StoreCell(position, cell);
}

void StepSingleLogicalCell(uint2 block)
{
    const uint2 position = uint2(0u, 0u);
    if (IsRigidOccupied(position))
    {
        CopyCell(position);
        return;
    }

    Cell cell = LoadCell(position);
    ReactCellToBlast(cell, false, position, block, StepIndex * 32u + 41u);
    AdvanceLifetime(cell, block, StepIndex * 32u);
    StoreCell(position, cell);
}

void StepVerticalLogicalLine(uint2 block, uint phase)
{
    if (block.x != 0u)
        return;

    const uint y = block.y * 2u + phase;
    if (phase != 0u && block.y == 0u)
        AdvanceStandaloneCell(uint2(0u, 0u), StepIndex * 32u + 20u);
    if (y >= LogicalStateHeight)
        return;
    if (y + 1u >= LogicalStateHeight)
    {
        AdvanceStandaloneCell(uint2(0u, y), StepIndex * 32u + 21u);
        return;
    }

    const uint2 upperPosition = uint2(0u, y);
    const uint2 lowerPosition = uint2(0u, y + 1u);
    const bool upperRigid = IsRigidOccupied(upperPosition);
    const bool lowerRigid = IsRigidOccupied(lowerPosition);

    Cell upper = EmptyCell();
    Cell lower = EmptyCell();
    if (!upperRigid) upper = LoadCell(upperPosition);
    if (!lowerRigid) lower = LoadCell(lowerPosition);

    ReactCellToBlast(upper, upperRigid, upperPosition, block, StepIndex * 32u + 41u);
    ReactCellToBlast(lower, lowerRigid, lowerPosition, block, StepIndex * 32u + 42u);
    AdvanceLifetime(upper, block, StepIndex * 32u + 0u);
    AdvanceLifetime(lower, block, StepIndex * 32u + 4u);
    ReactPair(upper, lower, block, StepIndex * 64u);
    ResolveVertical(upper, upperRigid, lower, lowerRigid);
    TryBlastPair(upper, upperRigid, upperPosition, lower, lowerRigid, lowerPosition, block, StepIndex * 16u + 13u);

    StoreResolvedCell(upperPosition, upper, upperRigid);
    StoreResolvedCell(lowerPosition, lower, lowerRigid);
}

void StepHorizontalLogicalLine(uint2 block, uint phase)
{
    if (block.y != 0u)
        return;

    const uint x = block.x * 2u + phase;
    if (phase != 0u && block.x == 0u)
        AdvanceStandaloneCell(uint2(0u, 0u), StepIndex * 32u + 22u);
    if (x >= LogicalStateWidth)
        return;
    if (x + 1u >= LogicalStateWidth)
    {
        AdvanceStandaloneCell(uint2(x, 0u), StepIndex * 32u + 23u);
        return;
    }

    const uint2 leftPosition = uint2(x, 0u);
    const uint2 rightPosition = uint2(x + 1u, 0u);
    const bool leftRigid = IsRigidOccupied(leftPosition);
    const bool rightRigid = IsRigidOccupied(rightPosition);

    Cell left = EmptyCell();
    Cell right = EmptyCell();
    if (!leftRigid) left = LoadCell(leftPosition);
    if (!rightRigid) right = LoadCell(rightPosition);

    ReactCellToBlast(left, leftRigid, leftPosition, block, StepIndex * 32u + 43u);
    ReactCellToBlast(right, rightRigid, rightPosition, block, StepIndex * 32u + 44u);
    AdvanceLifetime(left, block, StepIndex * 32u + 0u);
    AdvanceLifetime(right, block, StepIndex * 32u + 4u);
    ReactPair(left, right, block, StepIndex * 64u);
    TryHorizontal(left, leftRigid, right, rightRigid, block, StepIndex * 16u + 7u);
    TryBlastPair(left, leftRigid, leftPosition, right, rightRigid, rightPosition, block, StepIndex * 16u + 13u);

    StoreResolvedCell(leftPosition, left, leftRigid);
    StoreResolvedCell(rightPosition, right, rightRigid);
}

[numthreads(8, 8, 1)]
void main(uint3 dispatchThreadId : SV_DispatchThreadID)
{
    const uint2 block = dispatchThreadId.xy;
    const uint blockWidth = StateWidth / 2u;
    const uint blockHeight = StateHeight / 2u;
    if (block.x >= blockWidth || block.y >= blockHeight)
        return;

    const uint phase = StepIndex & 1u;

    // A 2x2 Margolus block cannot exist on a one-cell-wide/high logical grid.
    // Use conflict-free 1D pair phases instead so narrow source images still
    // age, react, fall/rise, and spread rather than freezing every other edge.
    if (LogicalStateWidth == 1u && LogicalStateHeight == 1u)
    {
        if (block.x == 0u && block.y == 0u)
            StepSingleLogicalCell(block);
        return;
    }
    if (LogicalStateWidth == 1u)
    {
        StepVerticalLogicalLine(block, phase);
        return;
    }
    if (LogicalStateHeight == 1u)
    {
        StepHorizontalLogicalLine(block, phase);
        return;
    }

    if (phase != 0u)
    {
        const uint y = block.y * 2u;
        if (block.x == 0u)
        {
            AdvanceStandaloneCell(uint2(0u, y), StepIndex * 32u + 24u);
            AdvanceStandaloneCell(uint2(0u, y + 1u), StepIndex * 32u + 25u);
        }
        if (block.x + 1u == blockWidth)
        {
            AdvanceStandaloneCell(uint2(StateWidth - 1u, y), StepIndex * 32u + 26u);
            AdvanceStandaloneCell(uint2(StateWidth - 1u, y + 1u), StepIndex * 32u + 27u);
        }

        const uint x = block.x * 2u + 1u;
        if (x + 1u < StateWidth - 1u)
        {
            if (block.y == 0u)
            {
                AdvanceStandaloneCell(uint2(x, 0u), StepIndex * 32u + 28u);
                AdvanceStandaloneCell(uint2(x + 1u, 0u), StepIndex * 32u + 29u);
            }
            if (block.y + 1u == blockHeight)
            {
                AdvanceStandaloneCell(uint2(x, StateHeight - 1u), StepIndex * 32u + 30u);
                AdvanceStandaloneCell(uint2(x + 1u, StateHeight - 1u), StepIndex * 32u + 31u);
            }
        }
    }

    const uint2 topLeft = block * 2u + phase;
    if (topLeft.x + 1u >= StateWidth || topLeft.y + 1u >= StateHeight)
        return;

    const uint2 p00 = topLeft;
    const uint2 p10 = topLeft + uint2(1u, 0u);
    const uint2 p01 = topLeft + uint2(0u, 1u);
    const uint2 p11 = topLeft + uint2(1u, 1u);

    // Logical dimensions may be odd even though the backing textures are padded
    // to even sizes for Margolus dispatch. Treat only the padded cells as solid
    // walls instead of freezing the whole partial 2x2 block. Otherwise the last
    // real column can never move vertically and the last real row can never move
    // horizontally on odd-sized simulation grids.
    const bool logicalA = p00.x < LogicalStateWidth && p00.y < LogicalStateHeight;
    const bool logicalB = p10.x < LogicalStateWidth && p10.y < LogicalStateHeight;
    const bool logicalC = p01.x < LogicalStateWidth && p01.y < LogicalStateHeight;
    const bool logicalD = p11.x < LogicalStateWidth && p11.y < LogicalStateHeight;

    const bool rigidA = !logicalA || IsRigidOccupied(p00);
    const bool rigidB = !logicalB || IsRigidOccupied(p10);
    const bool rigidC = !logicalC || IsRigidOccupied(p01);
    const bool rigidD = !logicalD || IsRigidOccupied(p11);

    Cell a = EmptyCell();
    Cell b = EmptyCell();
    Cell c = EmptyCell();
    Cell d = EmptyCell();
    if (logicalA) a = LoadCell(p00);
    if (logicalB) b = LoadCell(p10);
    if (logicalC) c = LoadCell(p01);
    if (logicalD) d = LoadCell(p11);

    if (rigidA) a = EmptyCell();
    if (rigidB) b = EmptyCell();
    if (rigidC) c = EmptyCell();
    if (rigidD) d = EmptyCell();

    ReactCellToBlast(a, rigidA, p00, block, StepIndex * 32u + 41u);
    ReactCellToBlast(b, rigidB, p10, block, StepIndex * 32u + 42u);
    ReactCellToBlast(c, rigidC, p01, block, StepIndex * 32u + 43u);
    ReactCellToBlast(d, rigidD, p11, block, StepIndex * 32u + 44u);

    AdvanceLifetime(a, block, StepIndex * 32u + 0u);
    AdvanceLifetime(b, block, StepIndex * 32u + 4u);
    AdvanceLifetime(c, block, StepIndex * 32u + 8u);
    AdvanceLifetime(d, block, StepIndex * 32u + 12u);

    ReactPair(a, b, block, StepIndex * 64u + 0u);
    ReactPair(c, d, block, StepIndex * 64u + 8u);
    ReactPair(a, c, block, StepIndex * 64u + 16u);
    ReactPair(b, d, block, StepIndex * 64u + 24u);
    ReactPair(a, d, block, StepIndex * 64u + 32u);
    ReactPair(b, c, block, StepIndex * 64u + 40u);

    ResolveVertical(a, rigidA, c, rigidC);
    ResolveVertical(b, rigidB, d, rigidD);

    const bool diagonalOrder = (HashCell(block, StepIndex * 16u + 2u) & 1u) != 0u;
    if (diagonalOrder)
    {
        TryDiagonalDown(a, rigidA, c, rigidC, d, rigidD, block, StepIndex * 16u + 3u);
        TryDiagonalDown(b, rigidB, d, rigidD, c, rigidC, block, StepIndex * 16u + 4u);
        TryDiagonalUp(c, rigidC, a, rigidA, b, rigidB, block, StepIndex * 16u + 5u);
        TryDiagonalUp(d, rigidD, b, rigidB, a, rigidA, block, StepIndex * 16u + 6u);
    }
    else
    {
        TryDiagonalDown(b, rigidB, d, rigidD, c, rigidC, block, StepIndex * 16u + 3u);
        TryDiagonalDown(a, rigidA, c, rigidC, d, rigidD, block, StepIndex * 16u + 4u);
        TryDiagonalUp(d, rigidD, b, rigidB, a, rigidA, block, StepIndex * 16u + 5u);
        TryDiagonalUp(c, rigidC, a, rigidA, b, rigidB, block, StepIndex * 16u + 6u);
    }

    TryHorizontal(a, rigidA, b, rigidB, block, StepIndex * 16u + 7u);
    TryHorizontal(c, rigidC, d, rigidD, block, StepIndex * 16u + 9u);

    // A pressure gradient acts after ordinary gravity/flow, so an explosion can
    // push powder, liquid, fire and gas sideways/upward without adding a second
    // CA state texture or cross-thread scatter writes. The Margolus block keeps
    // each swap conflict-free and the pressure field supplies the direction.
    TryBlastPair(a, rigidA, p00, b, rigidB, p10, block, StepIndex * 16u + 10u);
    TryBlastPair(c, rigidC, p01, d, rigidD, p11, block, StepIndex * 16u + 11u);
    TryBlastPair(a, rigidA, p00, c, rigidC, p01, block, StepIndex * 16u + 12u);
    TryBlastPair(b, rigidB, p10, d, rigidD, p11, block, StepIndex * 16u + 13u);

    if (logicalA) StoreResolvedCell(p00, a, rigidA);
    if (logicalB) StoreResolvedCell(p10, b, rigidB);
    if (logicalC) StoreResolvedCell(p01, c, rigidC);
    if (logicalD) StoreResolvedCell(p11, d, rigidD);
}
