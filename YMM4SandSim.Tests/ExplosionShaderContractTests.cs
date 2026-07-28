using System.IO;

namespace YMM4SandSim.Tests;

public sealed class ExplosionShaderContractTests
{
    [Fact]
    public void ManualExplosionSeedsCenterAndPropagatesToConfiguredRadius()
    {
        var source = ReadShader("SandExplosionUpdate.hlsl");

        Assert.DoesNotContain("float ManualExplosionSeed(", source);
        Assert.Contains("id.x == ManualExplosionCellX", source);
        Assert.Contains("id.y == ManualExplosionCellY", source);
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
        Assert.Contains("IsInsideManualExplosionRegion(position)", step);
        Assert.Contains("pressure * ManualExplosionWaveMask(position)", step);
        Assert.Contains("visiblePressure *= radialFront", seed);
        Assert.Contains("explosionFront = radialFront * saturate(pressure * 2.5f)", seed);
    }

    [Fact]
    public void BlastImpulseUsesRadialControllerFrontAndRigidDensity()
    {
        var source = ReadShader("SandRigidIntegrate.hlsl");

        Assert.Contains("IsInsideManualExplosionRegion(cell)", source);
        Assert.Contains("ManualExplosionWaveMask(cell)", source);
        Assert.Contains("return delta / distance * impulseMagnitude", source);
        Assert.Contains("rsqrt(max(rigidDensity, 0.50f))", source);
        Assert.Contains("pressureGradient / gradientMagnitude", source);
    }

    [Fact]
    public void ControllerExplosionAlwaysCreatesAHeatSourceAtFlammableCenter()
    {
        var step = ReadShader("SandStep.hlsl");
        var rigid = ReadShader("SandRigidReact.hlsl");

        Assert.Contains("void SeedManualExplosionFire(", step);
        Assert.Contains("distance < 0.5f", step);
        Assert.Contains("IgnitionProbability(MaterialFire, material) > 0.0f", step);
        Assert.Contains("SetMaterial(cell, MaterialFire)", step);
        Assert.Contains("target.x == ManualExplosionCellX", rigid);
        Assert.Contains("target.y == ManualExplosionCellY", rigid);
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
