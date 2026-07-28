namespace YMM4SandSim;

internal static class SandSimulationSettings
{
    public const int MaximumCanvasSize = 8192;
    public const long MaximumSourcePixelCount = 16_777_216;
    // Cap GPU simulation state at about 304 MiB while charging only the buffers
    // required by enabled features. Source/output textures are guarded separately
    // by MaximumSourcePixelCount.
    public const long MaximumSimulationStateBytes = 318_767_104;
    private const int CellularStateBytesPerCell = 16;
    private const int RigidStateBytesPerCell = 44;
    private const int ExplosionStateBytesPerCell = 8;
    private const int LightingStateBytesPerCell = 8;
    public const int MaximumIterationsPerFrame = 32;
    public const int MaximumWarmupIterations = 256;
    public const int MaximumSolidSolverIterations = 8;
    public const double ExplosionRadiusSliderMaximum = 1000.0;
    public const int MaximumLightingRadius = 32;
    public const double PositionSliderMinimum = -500.0;
    public const double PositionSliderMaximum = 500.0;
    public const double PercentMultiplierSliderMinimum = 0.0;
    public const double PercentMultiplierSliderMaximum = 400.0;
    public const double PositiveAnimationMinimum = 0.0;
    public const double SignedAnimationMinimum = -100_000.0;
    public const double AnimationMaximum = 100_000.0;
    public const uint DefaultSeed = 0x6D2B79F5u;

    public static int GetSimulationStateBytesPerCell(
        bool solidPhysicsEnabled,
        bool explosionEnabled,
        bool lightingEnabled)
        => CellularStateBytesPerCell +
           (solidPhysicsEnabled ? RigidStateBytesPerCell : 0) +
           (explosionEnabled ? ExplosionStateBytesPerCell : 0) +
           (lightingEnabled ? LightingStateBytesPerCell : 0);

    public static bool IsSimulationSizeSupported(
        int width,
        int height,
        int particleSize,
        bool solidPhysicsEnabled,
        bool explosionEnabled,
        bool lightingEnabled)
    {
        if (width <= 0 || height <= 0 || particleSize <= 0)
            return false;

        var logicalWidth = (width + (long)particleSize - 1L) / particleSize;
        var logicalHeight = (height + (long)particleSize - 1L) / particleSize;
        var stateWidth = logicalWidth + (logicalWidth & 1L);
        var stateHeight = logicalHeight + (logicalHeight & 1L);
        var bytesPerCell = GetSimulationStateBytesPerCell(solidPhysicsEnabled, explosionEnabled, lightingEnabled);
        return stateWidth * stateHeight * bytesPerCell <= MaximumSimulationStateBytes;
    }

    public static SandSourceMode NormalizeSourceMode(SandSourceMode value)
        => value is SandSourceMode.Snapshot or
                    SandSourceMode.ContinuousEmitter or
                    SandSourceMode.AddEveryFrame
            ? value
            : SandSourceMode.Snapshot;

    public static SandMaskMode NormalizeMaskMode(SandMaskMode value)
        => value is SandMaskMode.Alpha or
                    SandMaskMode.Luminance or
                    SandMaskMode.AlphaAndLuminance
            ? value
            : SandMaskMode.Alpha;

    public static SandMaterialAssignment NormalizeMaterialAssignment(SandMaterialAssignment value)
        => value is SandMaterialAssignment.ClosestColor or SandMaterialAssignment.SingleMaterial
            ? value
            : SandMaterialAssignment.ClosestColor;

    public static SandMaterial NormalizeMaterial(SandMaterial value)
        => value is >= SandMaterial.Sand and <= SandMaterial.Quartz
            ? value
            : SandMaterial.Sand;

    public static SandColorMode NormalizeColorMode(SandColorMode value)
        => value is SandColorMode.MaterialPalette or SandColorMode.PreserveInput
            ? value
            : SandColorMode.MaterialPalette;

    public static SandSolidPhysicsMode NormalizeSolidPhysicsMode(SandSolidPhysicsMode value)
        => value is SandSolidPhysicsMode.Disabled or SandSolidPhysicsMode.Xpbd
            ? value
            : SandSolidPhysicsMode.Disabled;

    public static int NormalizeParticleSize(SandParticleSize value)
        => value switch
        {
            SandParticleSize.One => 1,
            SandParticleSize.Two => 2,
            SandParticleSize.Three => 3,
            SandParticleSize.Four => 4,
            SandParticleSize.Six => 6,
            SandParticleSize.Eight => 8,
            _ => 4,
        };
}
