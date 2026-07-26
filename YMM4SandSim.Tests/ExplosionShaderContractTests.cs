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
    public void BlastImpulseUsesRadialPressureFrontAndRigidDensity()
    {
        var source = ReadShader("SandRigidIntegrate.hlsl");

        Assert.Contains("pressureGradient / gradientMagnitude", source);
        Assert.Contains("gradientMagnitude * max(ExplosionRadius, 1.0f)", source);
        Assert.Contains("rsqrt(max(rigidDensity, 0.50f))", source);
    }

    [Fact]
    public void ControllerExplosionSeedsFireThenUsesExistingCellularChemistry()
    {
        var source = ReadShader("SandStep.hlsl");

        Assert.Contains("void SeedManualExplosionFire(", source);
        Assert.Contains("coreRadius = clamp(ExplosionRadius * 0.20f", source);
        Assert.Contains("SetMaterial(cell, MaterialFire)", source);
        Assert.DoesNotContain("void IgniteFromBlast(", source);
    }

    [Fact]
    public void ExplosionLightingEmphasizesPropagatingShockFront()
    {
        var source = ReadShader("SandLightSeed.hlsl");

        Assert.Contains("float ExplosionFlashAt(", source);
        Assert.Contains("minimumNeighbour < 0.001f", source);
        Assert.Contains("saturate(pressure * 2.5f)", source);
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
