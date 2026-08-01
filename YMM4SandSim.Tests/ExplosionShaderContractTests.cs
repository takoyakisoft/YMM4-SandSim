using System.IO;

namespace YMM4SandSim.Tests;

public sealed class ExplosionShaderContractTests
{
    [Fact]
    public void MaterialExplosionsUsePressureFieldWithoutControllerSeed()
    {
        var source = ReadShader("SandExplosionUpdate.hlsl");

        Assert.DoesNotContain("float ManualExplosionSeed(", source);
        Assert.DoesNotContain("manualExplosion", source);
        Assert.Contains("eventSeed = explosion ? 1.0f : 0.0f", source);
        Assert.Contains("neighbour - ExplosionFalloff", source);
        Assert.Contains("PressureAt(center) * min(ExplosionDecay, 0.32f)", source);
    }

    [Fact]
    public void ControllerWaveUsesPersistentEuclideanFrontForCaAndLighting()
    {
        var behavior = ReadShader("SandBehavior.hlsli");
        var step = ReadShader("SandStep.hlsl");
        var seed = ReadShader("SandLightSeed.hlsl");

        Assert.Contains("ManualExplosionWaveStep", behavior);
        Assert.Contains("abs(distance - waveRadius)", behavior);
        Assert.Contains("ManualExplosionBlastMask", behavior);
        Assert.Contains("propagationStride", behavior);
        Assert.Contains("trailWidth", behavior);
        Assert.Contains("IsInsideManualExplosionRegion(position)", step);
        Assert.Contains("pressure = max(pressure, ManualExplosionBlastMask(position))", step);
        Assert.Contains("visiblePressure = max(pressure * radialFront, radialFront * 0.35f)", seed);
        Assert.Contains("explosionFront = radialFront", seed);
    }

    [Fact]
    public void BlastImpulseUsesRadialControllerFrontAndRigidDensity()
    {
        var source = ReadShader("SandRigidIntegrate.hlsl");

        Assert.Contains("IsInsideManualExplosionRegionAt(rigidBodyReference)", source);
        Assert.Contains("ManualExplosionBlastMaskAt(rigidBodyReference)", source);
        Assert.Contains("log2(max(ExplosionStrength, 1.0f))", source);
        Assert.Contains("RigidFractureSpanCells(material)", source);
        Assert.Contains("RigidBodyLabel.Load", source);
        Assert.Contains("EstimateRigidBodyReference(id, current, rigidBodyOwner)", source);
        Assert.Contains("frontMask * (0.55f + strengthScale * 0.65f) * densityScale", source);
        Assert.Contains("return delta / distance * impulseMagnitude", source);
        Assert.Contains("rsqrt(max(rigidDensity, 0.50f))", source);
        Assert.Contains("pressureGradient / gradientMagnitude", source);
        Assert.DoesNotContain("PhysicsChunkSpan", source);
    }

    [Fact]
    public void ConnectedBodyContactsPreserveTangentialBlastMomentum()
    {
        var grid = ReadShader("SandRigidGrid.hlsl");
        var integrate = ReadShader("SandRigidIntegrate.hlsl");

        Assert.Contains("RigidContactHorizontal", grid);
        Assert.Contains("RigidContactVertical", grid);
        Assert.Contains("RigidBodyLabel.Load", grid);
        Assert.Contains("InterlockedOr(RigidBodyContact[bodyCell], contactMask", grid);
        Assert.Contains("StopRigidAxes(id, contactMask)", grid);
        Assert.DoesNotContain("IsPowder(cellularMaterial) || IsFixed(cellularMaterial)", grid);
        Assert.Contains("saturate(probability * sqrt(max(ExplosionStrength, 1.0f)))", integrate);
    }

    [Fact]
    public void RigidBodiesAreSameMaterialConnectedComponents()
    {
        var components = ReadShader("SandRigidComponents.hlsl");
        var solve = ReadShader("SandRigidSolve.hlsl");

        Assert.Contains("GetMaterial(RigidMeta.Load(int3(second, 0))) != material", components);
        Assert.Contains("id + uint2(1u, 0u)", components);
        Assert.Contains("id + uint2(0u, 1u)", components);
        Assert.Contains("InterlockedMin(RigidBodyLabel", components);
        Assert.Contains("sameBody00_10", solve);
        Assert.DoesNotContain("IsSameRigidMacro", solve);
    }

    [Fact]
    public void ControllerExplosionCreatesCavityAndFireShell()
    {
        var step = ReadShader("SandStep.hlsl");
        var rigid = ReadShader("SandRigidReact.hlsl");

        Assert.Contains("void SeedManualExplosionFire(", step);
        Assert.Contains("ManualExplosionCavityRadius()", step);
        Assert.Contains("cell = EmptyCell()", step);
        Assert.Contains("IgnitionProbability(MaterialFire, material) <= 0.0f", step);
        Assert.Contains("SetMaterial(cell, MaterialFire)", step);
        Assert.Contains("distance <= cavityRadius", rigid);
        Assert.Contains("ClearRigid(id)", rigid);
        Assert.Contains("ConvertRigidToCell(id, target, MaterialFire)", rigid);
        Assert.DoesNotContain("void IgniteFromBlast(", step);
    }

    [Fact]
    public void ExplosionLightingMarksOnlyThePropagatingShockFront()
    {
        var lighting = ReadShader("SandLighting.hlsli");
        var seed = ReadShader("SandLightSeed.hlsl");
        var propagate = ReadShader("SandLightPropagate.hlsl");

        Assert.Contains("ShockwaveLightOpticalMarker = 30u", lighting);
        Assert.Contains("bool HasShockwaveLightMarker(", lighting);
        Assert.Contains("float ExplosionFrontAt(", seed);
        Assert.Contains("minimumNeighbour < 0.001f", seed);
        Assert.Contains("material == MaterialEmpty && explosionFront > 0.0f", seed);
        Assert.Contains("transmission = ShockwaveLightTransmission", seed);
        Assert.Contains("PackLight(best, UnpackLightTransmission(packedCurrent))", propagate);
    }

    [Fact]
    public void RenderShowsMarkedShockFrontOnlyAcrossEmptyCells()
    {
        var source = ReadShader("SandRenderPS.hlsl");

        Assert.Contains("material == MaterialEmpty && HasShockwaveLightMarker(packedLight)", source);
        Assert.Contains("shockwaveAlpha", source);
        Assert.Contains("float4(shockwaveColor * shockwaveAlpha, shockwaveAlpha)", source);
    }

    private static string ReadShader(string fileName)
    {
        for (var directory = new DirectoryInfo(AppContext.BaseDirectory); directory is not null; directory = directory.Parent)
        {
            var path = Path.Combine(directory.FullName, "YMM4SandSim", "Shaders", fileName);
            if (File.Exists(path))
                return File.ReadAllText(path);
        }

        throw new FileNotFoundException($"Shader source was not found: {fileName}");
    }
}
