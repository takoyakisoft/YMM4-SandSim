namespace YMM4SandSim.Tests;

public sealed class SettingsTests
{
    [Theory]
    [InlineData(SandParticleSize.One, 1)]
    [InlineData(SandParticleSize.Two, 2)]
    [InlineData(SandParticleSize.Three, 3)]
    [InlineData(SandParticleSize.Four, 4)]
    [InlineData(SandParticleSize.Six, 6)]
    [InlineData(SandParticleSize.Eight, 8)]
    [InlineData((SandParticleSize)0, 4)]
    public void ParticleSizeIsNormalized(SandParticleSize value, int expected)
        => Assert.Equal(expected, SandSimulationSettings.NormalizeParticleSize(value));

    [Fact]
    public void InvalidEnumValuesUseSafeDefaults()
    {
        Assert.Equal(SandSourceMode.Snapshot, SandSimulationSettings.NormalizeSourceMode((SandSourceMode)999));
        Assert.Equal(SandMaskMode.Alpha, SandSimulationSettings.NormalizeMaskMode((SandMaskMode)999));
        Assert.Equal(SandMaterialAssignment.ClosestColor, SandSimulationSettings.NormalizeMaterialAssignment((SandMaterialAssignment)999));
        Assert.Equal(SandMaterial.Sand, SandSimulationSettings.NormalizeMaterial((SandMaterial)0));
        Assert.Equal(SandMaterial.Sand, SandSimulationSettings.NormalizeMaterial((SandMaterial)999));
        Assert.Equal(SandColorMode.MaterialPalette, SandSimulationSettings.NormalizeColorMode((SandColorMode)999));
        Assert.Equal(SandSolidPhysicsMode.Disabled, SandSimulationSettings.NormalizeSolidPhysicsMode((SandSolidPhysicsMode)999));
    }

    [Fact]
    public void ValidBoundaryValuesArePreserved()
    {
        Assert.Equal(SandMaterial.Quartz, SandSimulationSettings.NormalizeMaterial(SandMaterial.Quartz));
        Assert.Equal(SandSolidPhysicsMode.Xpbd, SandSimulationSettings.NormalizeSolidPhysicsMode(SandSolidPhysicsMode.Xpbd));
        Assert.Equal(8, SandSimulationSettings.MaximumSolidSolverIterations);
    }

    [Fact]
    public void ParameterRangesFollowYmm4Conventions()
    {
        Assert.Equal(-500.0, SandSimulationSettings.PositionSliderMinimum);
        Assert.Equal(500.0, SandSimulationSettings.PositionSliderMaximum);
        Assert.Equal(0.0, SandSimulationSettings.PercentMultiplierSliderMinimum);
        Assert.Equal(400.0, SandSimulationSettings.PercentMultiplierSliderMaximum);
        Assert.Equal(0.0, SandSimulationSettings.PositiveAnimationMinimum);
        Assert.Equal(-100_000.0, SandSimulationSettings.SignedAnimationMinimum);
        Assert.Equal(100_000.0, SandSimulationSettings.AnimationMaximum);
        Assert.Equal(1000.0, SandSimulationSettings.ExplosionRadiusSliderMaximum);
    }

    [Fact]
    public void SimulationMemoryBudgetDependsOnEnabledFeatures()
    {
        Assert.Equal(16, SandSimulationSettings.GetSimulationStateBytesPerCell(false, false, false));
        Assert.Equal(60, SandSimulationSettings.GetSimulationStateBytesPerCell(true, false, false));
        Assert.Equal(76, SandSimulationSettings.GetSimulationStateBytesPerCell(true, true, true));
        Assert.True(SandSimulationSettings.IsSimulationSizeSupported(3840, 2160, 1, false, false, false));
        Assert.False(SandSimulationSettings.IsSimulationSizeSupported(3840, 2160, 1, true, true, true));
        Assert.True(SandSimulationSettings.IsSimulationSizeSupported(3840, 2160, 2, true, true, true));
    }
}
