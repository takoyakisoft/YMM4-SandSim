#include "SandBehavior.hlsli"

Texture2D<uint> RigidMeta : register(t0);
Texture2D<uint> CellularMeta : register(t1);
Texture2D<float> ExplosionPressure : register(t2);
Texture2D<uint> RigidBodyLabel : register(t3);
RWTexture2D<float4> RigidState : register(u0); // xy=current, zw=previous
RWTexture2D<float4> RigidLambda : register(u1);

float ReadExplosionPressure(int2 p)
{
    if (p.x < 0 || p.y < 0 || p.x >= (int)LogicalStateWidth || p.y >= (int)LogicalStateHeight)
        return 0.0f;
    return ExplosionPressure.Load(int3(p, 0));
}

float2 ExplosionImpulseAt(uint2 cell, float2 rigidBodyReference, float rigidDensity)
{
    if (ExplosionStrength <= 0.0f)
        return 0.0f;

    const int2 p = int2(cell);
    const float centerPressure = ReadExplosionPressure(p);

    if (IsInsideManualExplosionRegionAt(rigidBodyReference))
    {
        const float frontMask = ManualExplosionBlastMaskAt(rigidBodyReference);
        if (frontMask <= 0.0f)
            return 0.0f;

        const float2 delta = rigidBodyReference - float2(ManualExplosionCellX, ManualExplosionCellY);
        const float distance = length(delta);
        if (distance < 0.0001f)
            return 0.0f;

        // Controller blasts are coherent per connected, same-material body. The
        // component representative supplies one shared direction, so distant
        // islands and neighbouring different materials no longer inherit the same
        // impulse merely because they fall inside one fixed macro rectangle.
        const float strengthScale = sqrt(max(ExplosionStrength, 0.0f));
        const float impulseMagnitude =
            frontMask * (0.55f + strengthScale * 0.65f);
        return delta / distance * impulseMagnitude;
    }

    const float densityScale = rsqrt(max(rigidDensity, 0.50f));

    const float left = ReadExplosionPressure(p + int2(-1, 0));
    const float right = ReadExplosionPressure(p + int2(1, 0));
    const float up = ReadExplosionPressure(p + int2(0, -1));
    const float down = ReadExplosionPressure(p + int2(0, 1));

    const float2 pressureGradient = float2(left - right, up - down);
    const float gradientMagnitude = length(pressureGradient);
    if (gradientMagnitude < 0.0001f)
        return 0.0f;

    const float2 direction = pressureGradient / gradientMagnitude;
    const float frontStrength = saturate(gradientMagnitude * max(ExplosionRadius, 1.0f) * 1.50f);
    const float pressureStrength = saturate(centerPressure * 0.35f);
    const float waveStrength = max(frontStrength, pressureStrength);
    const float impulseMagnitude = min(waveStrength * ExplosionStrength * 0.85f * densityScale, 0.90f);
    return direction * impulseMagnitude;
}

float2 ClampRigidPosition(float2 position)
{
    const float2 minimumPosition = float2(0.5f, 0.5f);
    const float2 maximumPosition = max(
        minimumPosition,
        float2((float)LogicalStateWidth - 0.5f, (float)LogicalStateHeight - 0.5f));
    return clamp(position, minimumPosition, maximumPosition);
}

float PreserveBrokenBond(float lambda)
{
    return IsBrokenRigidBond(lambda) ? BrokenRigidBondMarker : 0.0f;
}

[numthreads(8, 8, 1)]
void main(uint3 dispatchThreadId : SV_DispatchThreadID)
{
    const uint2 id = dispatchThreadId.xy;
    if (id.x >= StateWidth || id.y >= StateHeight)
        return;

    const uint material = GetMaterial(RigidMeta.Load(int3(id, 0)));
    if (SolidPhysicsMode != 1u || id.x >= LogicalStateWidth || id.y >= LogicalStateHeight ||
        !IsRigidPhysicsMaterial(material))
    {
        RigidLambda[id] = 0.0f;
        return;
    }

    float4 state = RigidState[id];
    const float2 current = state.xy;
    const uint2 currentCell = (uint2)clamp(
        floor(current),
        float2(0.0f, 0.0f),
        float2((float)LogicalStateWidth - 1.0f, (float)LogicalStateHeight - 1.0f));
    const uint fluidMaterial = GetMaterial(CellularMeta.Load(int3(currentCell, 0)));
    const float4 rigidProperties = RigidProperties(material);
    float fluidDensity = 0.0f;
    float fluidVelocityRetention = 1.0f;
    if (IsLiquid(fluidMaterial))
    {
        const float2 fluidProperties = FluidProperties(fluidMaterial);
        fluidDensity = fluidProperties.x;
        fluidVelocityRetention = fluidProperties.y;
    }
    const float damping = PhysicsDamping * rigidProperties.z * fluidVelocityRetention;
    float2 velocity = (current - state.zw) * damping;
    const uint rigidBodyOwner = RigidBodyLabel.Load(int3(id, 0));
    const float2 rigidBodyReference = EstimateRigidBodyReference(id, current, rigidBodyOwner);
    const bool manualMacroBlast = IsInsideManualExplosionRegionAt(rigidBodyReference) &&
        ManualExplosionBlastMaskAt(rigidBodyReference) > 0.0f;
    const float2 explosionImpulse = ExplosionImpulseAt(currentCell, rigidBodyReference, rigidProperties.x);
    velocity += explosionImpulse;

    // Keep one substep below one cell so the final-cell occupancy broadphase
    // cannot skip completely over a one-cell-thick obstacle due to integration
    // velocity alone. XPBD projection can still move points, but this removes
    // the dominant tunnelling source without a swept-contact buffer.
    float maximumRigidStep = 0.95f;
    if (length(explosionImpulse) > 0.0001f && manualMacroBlast)
    {
        // Let stronger explosions produce visibly more travel without an
        // arbitrary 4-cell ceiling. Growth is logarithmic to keep the final-cell
        // occupancy collision scheme numerically usable at extreme UI values.
        maximumRigidStep = 0.95f +
            0.85f * log2(max(ExplosionStrength, 1.0f));
    }
    const float speed = length(velocity);
    if (speed > maximumRigidStep)
        velocity *= maximumRigidStep / speed;

    float2 predicted = current + velocity;
    // In air every material shares the same free-fall acceleration. Inside a
    // liquid, Archimedes' density ratio reduces or reverses that acceleration;
    // this keeps ice/wood/wax buoyant without a CPU fluid-body contact system.
    float verticalAcceleration = PhysicsGravity;
    if (fluidDensity > 0.0f)
    {
        const float densityRatio = fluidDensity / max(rigidProperties.x, 0.05f);
        verticalAcceleration *= clamp(1.0f - densityRatio, -2.0f, 1.0f);
    }
    predicted.y += verticalAcceleration * PhysicsDeltaTime * PhysicsDeltaTime;
    const float2 clamped = ClampRigidPosition(predicted);

    float2 previousForNextStep = current;
    if (clamped.x != predicted.x)
        previousForNextStep.x = clamped.x;
    if (clamped.y != predicted.y)
        previousForNextStep.y = clamped.y;

    RigidState[id] = float4(clamped, previousForNextStep);

    // XPBD multipliers reset every substep, but a fracture marker is persistent.
    // This reuses the existing lambda texture instead of adding a bond texture,
    // extra memory traffic, CPU bookkeeping, or GPU readback.
    const float4 oldLambda = RigidLambda[id];
    float4 nextLambda = float4(
        PreserveBrokenBond(oldLambda.x),
        PreserveBrokenBond(oldLambda.y),
        PreserveBrokenBond(oldLambda.z),
        PreserveBrokenBond(oldLambda.w));

    // A sufficiently sharp pressure gradient can fracture bonds immediately.
    // The material-specific tensile strain remains the baseline, so glass/ice
    // shatter before stone and metals usually receive velocity without breaking.
    const float impulseMagnitude = length(explosionImpulse);
    const float fractureThreshold = max(
        rigidProperties.w * PhysicsBreakStrength * 2.0f, 0.04f);
    if (impulseMagnitude > fractureThreshold)
    {
        const float probability = saturate((impulseMagnitude / fractureThreshold - 1.0f) * 0.70f);
        const uint salt = StepIndex * 0x9e3779b9u;
        if (manualMacroBlast)
        {
            // Manual blasts cut a sparse coarse crack lattice. Connected-component
            // labels consume the persistent broken axial bonds on the next frame,
            // turning the resulting same-material islands into independent bodies.
            const uint chunkSpan = max(PhysicsChunkSpan, 2u);
            const bool eastBoundary = ((id.x + 1u) % chunkSpan) == 0u;
            const bool southBoundary = ((id.y + 1u) % chunkSpan) == 0u;
            const bool westBoundary = (id.x % chunkSpan) == 0u;
            const float chunkProbability = saturate(probability * sqrt(max(ExplosionStrength, 1.0f)));

            if (eastBoundary && HashUnit(id, salt + 0u) < chunkProbability)
                nextLambda.x = BrokenRigidBondMarker;
            if (southBoundary && HashUnit(id, salt + 1u) < chunkProbability)
                nextLambda.y = BrokenRigidBondMarker;
            if ((eastBoundary || southBoundary) &&
                HashUnit(id, salt + 2u) < chunkProbability)
                nextLambda.z = BrokenRigidBondMarker;
            if ((westBoundary || southBoundary) &&
                HashUnit(id, salt + 3u) < chunkProbability)
                nextLambda.w = BrokenRigidBondMarker;
        }
        else
        {
            if (HashUnit(id, salt + 0u) < probability) nextLambda.x = BrokenRigidBondMarker;
            if (HashUnit(id, salt + 1u) < probability) nextLambda.y = BrokenRigidBondMarker;
            if (HashUnit(id, salt + 2u) < probability) nextLambda.z = BrokenRigidBondMarker;
            if (HashUnit(id, salt + 3u) < probability) nextLambda.w = BrokenRigidBondMarker;
        }
    }
    RigidLambda[id] = nextLambda;
}
