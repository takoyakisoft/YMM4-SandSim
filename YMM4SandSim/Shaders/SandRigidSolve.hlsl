#include "SandBehavior.hlsli"

Texture2D<uint> RigidMeta : register(t0);
RWTexture2D<float4> RigidState : register(u0); // xy=current, zw=previous
RWTexture2D<float4> RigidLambda : register(u1); // E, S, SE, SW; broken=large persistent marker

float2 ClampRigidPosition(float2 position)
{
    const float2 minimumPosition = float2(0.5f, 0.5f);
    const float2 maximumPosition = max(
        minimumPosition,
        float2((float)LogicalStateWidth - 0.5f, (float)LogicalStateHeight - 0.5f));
    return clamp(position, minimumPosition, maximumPosition);
}

void ClampRigidStateToWorld(inout float4 state)
{
    const float2 before = state.xy;
    const float2 clamped = ClampRigidPosition(before);
    if (clamped.x != before.x)
        state.z = clamped.x;
    if (clamped.y != before.y)
        state.w = clamped.y;
    state.xy = clamped;
}

float SolveDistance(
    inout float4 stateA,
    inout float4 stateB,
    float4 propertiesA,
    float4 propertiesB,
    bool sameMaterial,
    float restLength,
    float lambda)
{
    if (IsBrokenRigidBond(lambda))
        return BrokenRigidBondMarker;

    const float2 delta = stateB.xy - stateA.xy;
    const float lengthSquared = dot(delta, delta);
    if (lengthSquared < 1e-8f)
        return lambda;

    const float currentLength = sqrt(lengthSquared);
    const float2 normal = delta / currentLength;
    const float constraint = currentLength - restLength;

    const float tensileStrain = max(constraint, 0.0f) / restLength;
    if (tensileStrain > RigidPairBreakStrain(propertiesA, propertiesB, sameMaterial) * PhysicsBreakStrength)
        return BrokenRigidBondMarker;

    const float inverseMassA = 1.0f / max(propertiesA.x, 0.05f);
    const float inverseMassB = 1.0f / max(propertiesB.x, 0.05f);
    const float dt2 = max(PhysicsDeltaTime * PhysicsDeltaTime, 1e-8f);
    const float compliance = PhysicsCompliance * RigidPairComplianceScale(propertiesA, propertiesB, sameMaterial);
    const float alphaTilde = compliance / dt2;
    const float deltaLambda = (-constraint - alphaTilde * lambda) /
        (inverseMassA + inverseMassB + alphaTilde);

    lambda += deltaLambda;
    stateA.xy -= inverseMassA * deltaLambda * normal;
    stateB.xy += inverseMassB * deltaLambda * normal;
    return lambda;
}

[numthreads(8, 8, 1)]
void main(uint3 dispatchThreadId : SV_DispatchThreadID)
{
    if (SolidPhysicsMode != 1u)
        return;

    const uint2 block = dispatchThreadId.xy;
    const uint blockWidth = StateWidth / 2u;
    const uint blockHeight = StateHeight / 2u;
    if (block.x >= blockWidth || block.y >= blockHeight)
        return;

    const uint2 phaseOffset = uint2(PhysicsPhase & 1u, (PhysicsPhase >> 1u) & 1u);
    const uint2 topLeft = block * 2u + phaseOffset;
    // StateWidth/StateHeight are rounded up to even dimensions. Process the
    // padded 2x2 block at an odd logical boundary as well: padded metadata is
    // empty, while real-real horizontal/vertical edges in the final row/column
    // still need XPBD constraints.
    if (topLeft.x + 1u >= StateWidth || topLeft.y + 1u >= StateHeight)
        return;

    const uint2 p00 = topLeft;
    const uint2 p10 = topLeft + uint2(1u, 0u);
    const uint2 p01 = topLeft + uint2(0u, 1u);
    const uint2 p11 = topLeft + uint2(1u, 1u);

    const uint m00 = RigidMeta.Load(int3(p00, 0));
    const uint m10 = RigidMeta.Load(int3(p10, 0));
    const uint m01 = RigidMeta.Load(int3(p01, 0));
    const uint m11 = RigidMeta.Load(int3(p11, 0));
    const uint material00 = GetMaterial(m00);
    const uint material10 = GetMaterial(m10);
    const uint material01 = GetMaterial(m01);
    const uint material11 = GetMaterial(m11);

    const bool active00 = IsRigidPhysicsMaterial(material00);
    const bool active10 = IsRigidPhysicsMaterial(material10);
    const bool active01 = IsRigidPhysicsMaterial(material01);
    const bool active11 = IsRigidPhysicsMaterial(material11);
    const uint activeCount = (active00 ? 1u : 0u) + (active10 ? 1u : 0u) +
        (active01 ? 1u : 0u) + (active11 ? 1u : 0u);
    if (activeCount < 2u)
        return;

    // Four shifted 2x2 parity phases cover the full 8-neighbour lattice.
    // Axial bonds are enabled only in the phase that owns them; diagonals are
    // unique to one shifted block. Exit before state/lambda traffic when this
    // block has no bond to solve in the current phase.
    const bool solveHorizontal = (PhysicsPhase & 2u) == 0u;
    const bool solveVertical = (PhysicsPhase & 1u) == 0u;
    const bool hasBond =
        (solveHorizontal && ((active00 && active10) || (active01 && active11))) ||
        (solveVertical && ((active00 && active01) || (active10 && active11))) ||
        (active00 && active11) || (active10 && active01);
    if (!hasBond)
        return;

    float4 properties00 = 0.0f;
    float4 properties10 = 0.0f;
    float4 properties01 = 0.0f;
    float4 properties11 = 0.0f;
    float4 a = 0.0f;
    float4 b = 0.0f;
    float4 c = 0.0f;
    float4 d = 0.0f;
    float4 lambda00 = 0.0f;
    float4 lambda10 = 0.0f;
    float4 lambda01 = 0.0f;

    if (active00)
    {
        properties00 = RigidProperties(material00);
        a = RigidState[p00];
        lambda00 = RigidLambda[p00];
    }
    if (active10)
    {
        properties10 = RigidProperties(material10);
        b = RigidState[p10];
        lambda10 = RigidLambda[p10];
    }
    if (active01)
    {
        properties01 = RigidProperties(material01);
        c = RigidState[p01];
        lambda01 = RigidLambda[p01];
    }
    if (active11)
    {
        properties11 = RigidProperties(material11);
        d = RigidState[p11];
    }

    if (solveHorizontal)
    {
        if (active00 && active10)
            lambda00.x = SolveDistance(a, b, properties00, properties10, material00 == material10, 1.0f, lambda00.x);
        if (active01 && active11)
            lambda01.x = SolveDistance(c, d, properties01, properties11, material01 == material11, 1.0f, lambda01.x);
    }
    if (solveVertical)
    {
        if (active00 && active01)
            lambda00.y = SolveDistance(a, c, properties00, properties01, material00 == material01, 1.0f, lambda00.y);
        if (active10 && active11)
            lambda10.y = SolveDistance(b, d, properties10, properties11, material10 == material11, 1.0f, lambda10.y);
    }
    if (active00 && active11)
        lambda00.z = SolveDistance(a, d, properties00, properties11, material00 == material11, 1.41421356237f, lambda00.z);
    if (active10 && active01)
        lambda10.w = SolveDistance(b, c, properties10, properties01, material10 == material01, 1.41421356237f, lambda10.w);

    if (active00)
    {
        ClampRigidStateToWorld(a);
        RigidState[p00] = a;
        RigidLambda[p00] = lambda00;
    }
    if (active10)
    {
        ClampRigidStateToWorld(b);
        RigidState[p10] = b;
        RigidLambda[p10] = lambda10;
    }
    if (active01)
    {
        ClampRigidStateToWorld(c);
        RigidState[p01] = c;
        RigidLambda[p01] = lambda01;
    }
    if (active11)
    {
        ClampRigidStateToWorld(d);
        RigidState[p11] = d;
    }
}
