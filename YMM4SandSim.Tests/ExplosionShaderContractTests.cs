namespace YMM4SandSim.Tests;

public sealed class ExplosionShaderContractTests
{
    [Fact]
    public void ManualExplosionSeedUsesConfiguredRadiusAndMaterialTransmission()
    {
        var source = ReadShader("SandExplosionUpdate.hlsl");

        Assert.Contains("float ManualExplosionSeed(", source);
        Assert.Contains("ExplosionRadius", source);
        Assert.Contains("length((float2)delta)", source);
        Assert.Contains("ExplosionPressureTransmission(MaterialAt", source);
    }

    [Fact]
    public void BlastPressureFeedsExistingFireChemistry()
    {
        var source = ReadShader("SandStep.hlsl");

        Assert.Contains("void IgniteFromBlast(", source);
        Assert.Contains("IgnitionProbability(MaterialFire, material)", source);
        Assert.Contains("SetMaterial(cell, MaterialFire)", source);
        Assert.Contains("ReactCellToBlast", source);
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
