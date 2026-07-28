using System.ComponentModel.DataAnnotations;
using YukkuriMovieMaker.Commons;
using YukkuriMovieMaker.Controls;
using YukkuriMovieMaker.Exo;
using YukkuriMovieMaker.Player.Video;
using YukkuriMovieMaker.Plugin.Effects;
using YMM4SandSim.Localization;

namespace YMM4SandSim;

[VideoEffect(
    nameof(Translate.Plugin_Name),
    [VideoEffectCategories.Filtering],
    ["砂", "水", "火", "物理", "Falling Sand"],
    IsAviUtlSupported = false,
    ResourceType = typeof(Translate))]
public sealed class SandSimulationEffect : VideoEffectBase
{
    public override string Label => Translate.Plugin_Name;

    [Display(GroupName = nameof(Translate.Group_Basic), Name = nameof(Translate.ScreenSize_Name), Description = nameof(Translate.ScreenSize_Desc), ResourceType = typeof(Translate))]
    [ToggleSlider]
    public bool IsScreenSize
    {
        get => _isScreenSize;
        set => Set(ref _isScreenSize, value);
    }
    private bool _isScreenSize;

    [Display(GroupName = nameof(Translate.Group_Basic), Name = nameof(Translate.SourceMode_Name), Description = nameof(Translate.SourceMode_Desc), ResourceType = typeof(Translate))]
    [EnumComboBox]
    public SandSourceMode SourceMode
    {
        get => _sourceMode;
        set => Set(ref _sourceMode, value);
    }
    private SandSourceMode _sourceMode = SandSourceMode.Snapshot;

    [Display(GroupName = nameof(Translate.Group_Basic), Name = nameof(Translate.ParticleSize_Name), Description = nameof(Translate.ParticleSize_Desc), ResourceType = typeof(Translate))]
    [EnumComboBox]
    public SandParticleSize ParticleSize
    {
        get => _particleSize;
        set => Set(ref _particleSize, value);
    }
    private SandParticleSize _particleSize = SandParticleSize.Four;

    [Display(GroupName = nameof(Translate.Group_Material), Name = nameof(Translate.MaterialAssignment_Name), Description = nameof(Translate.MaterialAssignment_Desc), ResourceType = typeof(Translate))]
    [EnumComboBox]
    public SandMaterialAssignment MaterialAssignment
    {
        get => _materialAssignment;
        set => Set(ref _materialAssignment, value);
    }
    private SandMaterialAssignment _materialAssignment = SandMaterialAssignment.ClosestColor;

    [Display(GroupName = nameof(Translate.Group_Material), Name = nameof(Translate.SingleMaterial_Name), Description = nameof(Translate.SingleMaterial_Desc), ResourceType = typeof(Translate))]
    [EnumComboBox]
    public SandMaterial SingleMaterial
    {
        get => _singleMaterial;
        set => Set(ref _singleMaterial, value);
    }
    private SandMaterial _singleMaterial = SandMaterial.Sand;

    [Display(GroupName = nameof(Translate.Group_Material), Name = nameof(Translate.ColorMode_Name), Description = nameof(Translate.ColorMode_Desc), ResourceType = typeof(Translate))]
    [EnumComboBox]
    public SandColorMode ColorMode
    {
        get => _colorMode;
        set => Set(ref _colorMode, value);
    }
    private SandColorMode _colorMode = SandColorMode.MaterialPalette;

    [Display(GroupName = nameof(Translate.Group_Simulation), Name = nameof(Translate.Iterations_Name), Description = nameof(Translate.Iterations_Desc), ResourceType = typeof(Translate))]
    [AnimationSlider("F0", "回", 1, SandSimulationSettings.MaximumIterationsPerFrame)]
    public Animation IterationsPerFrame { get; } = new(
        4,
        SandSimulationSettings.PositiveAnimationMinimum,
        SandSimulationSettings.AnimationMaximum);

    [Display(GroupName = nameof(Translate.Group_Simulation), Name = nameof(Translate.Warmup_Name), Description = nameof(Translate.Warmup_Desc), ResourceType = typeof(Translate))]
    [AnimationSlider("F0", "回", 0, SandSimulationSettings.MaximumWarmupIterations)]
    public Animation WarmupIterations { get; } = new(
        0,
        SandSimulationSettings.PositiveAnimationMinimum,
        SandSimulationSettings.AnimationMaximum);

    [Display(GroupName = nameof(Translate.Group_Simulation), Name = nameof(Translate.Spread_Name), Description = nameof(Translate.Spread_Desc), ResourceType = typeof(Translate))]
    [AnimationSlider("F1", "%", 0, 100)]
    public Animation Spread { get; } = new(
        85,
        SandSimulationSettings.PositiveAnimationMinimum,
        SandSimulationSettings.AnimationMaximum);

    [Display(GroupName = nameof(Translate.Group_Simulation), Name = nameof(Translate.ReactionStrength_Name), Description = nameof(Translate.ReactionStrength_Desc), ResourceType = typeof(Translate))]
    [AnimationSlider("F1", "%", SandSimulationSettings.PercentMultiplierSliderMinimum, SandSimulationSettings.PercentMultiplierSliderMaximum)]
    public Animation ReactionStrength { get; } = new(
        100,
        SandSimulationSettings.PositiveAnimationMinimum,
        SandSimulationSettings.AnimationMaximum);

    [Display(GroupName = nameof(Translate.Group_SolidPhysics), Name = nameof(Translate.SolidMode_Name), Description = nameof(Translate.SolidMode_Desc), ResourceType = typeof(Translate))]
    [EnumComboBox]
    public SandSolidPhysicsMode SolidPhysicsMode
    {
        get => _solidPhysicsMode;
        set => Set(ref _solidPhysicsMode, value);
    }
    private SandSolidPhysicsMode _solidPhysicsMode = SandSolidPhysicsMode.Xpbd;

    [Display(GroupName = nameof(Translate.Group_SolidPhysics), Name = nameof(Translate.Gravity_Name), Description = nameof(Translate.Gravity_Desc), ResourceType = typeof(Translate))]
    [AnimationSlider("F1", "%", SandSimulationSettings.PercentMultiplierSliderMinimum, SandSimulationSettings.PercentMultiplierSliderMaximum)]
    public Animation SolidGravity { get; } = new(
        100,
        SandSimulationSettings.PositiveAnimationMinimum,
        SandSimulationSettings.AnimationMaximum);

    [Display(GroupName = nameof(Translate.Group_SolidPhysics), Name = nameof(Translate.Stiffness_Name), Description = nameof(Translate.Stiffness_Desc), ResourceType = typeof(Translate))]
    [AnimationSlider("F1", "%", 25, SandSimulationSettings.PercentMultiplierSliderMaximum)]
    public Animation SolidStiffness { get; } = new(
        100,
        SandSimulationSettings.PositiveAnimationMinimum,
        SandSimulationSettings.AnimationMaximum);

    [Display(GroupName = nameof(Translate.Group_SolidPhysics), Name = nameof(Translate.BreakStrength_Name), Description = nameof(Translate.BreakStrength_Desc), ResourceType = typeof(Translate))]
    [AnimationSlider("F1", "%", 25, SandSimulationSettings.PercentMultiplierSliderMaximum)]
    public Animation SolidBreakStrength { get; } = new(
        100,
        SandSimulationSettings.PositiveAnimationMinimum,
        SandSimulationSettings.AnimationMaximum);

    [Display(GroupName = nameof(Translate.Group_SolidPhysics), Name = nameof(Translate.SolverIterations_Name), Description = nameof(Translate.SolverIterations_Desc), ResourceType = typeof(Translate))]
    [AnimationSlider("F0", "回", 1, SandSimulationSettings.MaximumSolidSolverIterations)]
    public Animation SolidSolverIterations { get; } = new(
        3,
        SandSimulationSettings.PositiveAnimationMinimum,
        SandSimulationSettings.AnimationMaximum);

    [Display(GroupName = nameof(Translate.Group_Explosion), Name = nameof(Translate.ExplosionController_Name), Description = nameof(Translate.ExplosionController_Desc), ResourceType = typeof(Translate))]
    [ToggleSlider]
    public bool ExplosionControllerEnabled
    {
        get => _explosionControllerEnabled;
        set => Set(ref _explosionControllerEnabled, value);
    }
    private bool _explosionControllerEnabled;

    [Display(GroupName = nameof(Translate.Group_Explosion), Name = nameof(Translate.ExplosionX_Name), Description = nameof(Translate.ExplosionX_Desc), ResourceType = typeof(Translate))]
    [AnimationSlider("F1", "px", SandSimulationSettings.PositionSliderMinimum, SandSimulationSettings.PositionSliderMaximum)]
    public Animation ExplosionX { get; } = new(
        0,
        SandSimulationSettings.SignedAnimationMinimum,
        SandSimulationSettings.AnimationMaximum);

    [Display(GroupName = nameof(Translate.Group_Explosion), Name = nameof(Translate.ExplosionY_Name), Description = nameof(Translate.ExplosionY_Desc), ResourceType = typeof(Translate))]
    [AnimationSlider("F1", "px", SandSimulationSettings.PositionSliderMinimum, SandSimulationSettings.PositionSliderMaximum)]
    public Animation ExplosionY { get; } = new(
        0,
        SandSimulationSettings.SignedAnimationMinimum,
        SandSimulationSettings.AnimationMaximum);

    [Display(GroupName = nameof(Translate.Group_Explosion), Name = nameof(Translate.ExplosionFrame_Name), Description = nameof(Translate.ExplosionFrame_Desc), ResourceType = typeof(Translate))]
    [AnimationSlider("F0", "フ", 0, 36000)]
    public Animation ExplosionTriggerFrame { get; } = new(
        0,
        SandSimulationSettings.PositiveAnimationMinimum,
        SandSimulationSettings.AnimationMaximum);

    [Display(GroupName = nameof(Translate.Group_Explosion), Name = nameof(Translate.ExplosionStrength_Name), Description = nameof(Translate.ExplosionStrength_Desc), ResourceType = typeof(Translate))]
    [AnimationSlider("F1", "%", SandSimulationSettings.PercentMultiplierSliderMinimum, SandSimulationSettings.PercentMultiplierSliderMaximum)]
    public Animation ExplosionStrength { get; } = new(
        100,
        SandSimulationSettings.PositiveAnimationMinimum,
        SandSimulationSettings.AnimationMaximum);

    [Display(GroupName = nameof(Translate.Group_Explosion), Name = nameof(Translate.ExplosionRadius_Name), Description = nameof(Translate.ExplosionRadius_Desc), ResourceType = typeof(Translate))]
    [AnimationSlider("F0", "px", 2, SandSimulationSettings.ExplosionRadiusSliderMaximum)]
    public Animation ExplosionRadius { get; } = new(
        120,
        SandSimulationSettings.PositiveAnimationMinimum,
        SandSimulationSettings.AnimationMaximum);

    [Display(GroupName = nameof(Translate.Group_Lighting), Name = nameof(Translate.LightingStrength_Name), Description = nameof(Translate.LightingStrength_Desc), ResourceType = typeof(Translate))]
    [AnimationSlider("F1", "%", SandSimulationSettings.PercentMultiplierSliderMinimum, SandSimulationSettings.PercentMultiplierSliderMaximum)]
    public Animation LightingStrength { get; } = new(
        100,
        SandSimulationSettings.PositiveAnimationMinimum,
        SandSimulationSettings.AnimationMaximum);

    [Display(GroupName = nameof(Translate.Group_Lighting), Name = nameof(Translate.LightingRadius_Name), Description = nameof(Translate.LightingRadius_Desc), ResourceType = typeof(Translate))]
    [AnimationSlider("F0", "セル", 1, SandSimulationSettings.MaximumLightingRadius)]
    public Animation LightingRadius { get; } = new(
        12,
        SandSimulationSettings.PositiveAnimationMinimum,
        SandSimulationSettings.AnimationMaximum);

    [Display(GroupName = nameof(Translate.Group_Lighting), Name = nameof(Translate.AmbientLight_Name), Description = nameof(Translate.AmbientLight_Desc), ResourceType = typeof(Translate))]
    [AnimationSlider("F1", "%", 0, 100)]
    public Animation AmbientLight { get; } = new(
        100,
        SandSimulationSettings.PositiveAnimationMinimum,
        SandSimulationSettings.AnimationMaximum);

    [Display(GroupName = nameof(Translate.Group_Lighting), Name = nameof(Translate.ShadowStrength_Name), Description = nameof(Translate.ShadowStrength_Desc), ResourceType = typeof(Translate))]
    [AnimationSlider("F1", "%", 0, 100)]
    public Animation ShadowStrength { get; } = new(
        90,
        SandSimulationSettings.PositiveAnimationMinimum,
        SandSimulationSettings.AnimationMaximum);

    [Display(GroupName = nameof(Translate.Group_Extraction), Name = nameof(Translate.MaskMode_Name), Description = nameof(Translate.MaskMode_Desc), ResourceType = typeof(Translate))]
    [EnumComboBox]
    public SandMaskMode MaskMode
    {
        get => _maskMode;
        set => Set(ref _maskMode, value);
    }
    private SandMaskMode _maskMode = SandMaskMode.Alpha;

    [Display(GroupName = nameof(Translate.Group_Extraction), Name = nameof(Translate.AlphaThreshold_Name), Description = nameof(Translate.AlphaThreshold_Desc), ResourceType = typeof(Translate))]
    [AnimationSlider("F1", "%", 0, 100)]
    public Animation AlphaThreshold { get; } = new(
        1,
        SandSimulationSettings.PositiveAnimationMinimum,
        SandSimulationSettings.AnimationMaximum);

    [Display(GroupName = nameof(Translate.Group_Extraction), Name = nameof(Translate.LuminanceThreshold_Name), Description = nameof(Translate.LuminanceThreshold_Desc), ResourceType = typeof(Translate))]
    [AnimationSlider("F1", "%", 0, 100)]
    public Animation LuminanceThreshold { get; } = new(
        1,
        SandSimulationSettings.PositiveAnimationMinimum,
        SandSimulationSettings.AnimationMaximum);

    private IAnimatable[]? _animatables;

    public override IEnumerable<string> CreateExoVideoFilters(int keyFrameIndex, ExoOutputDescription exoOutputDescription) => [];

    public override IVideoEffectProcessor CreateVideoEffect(IGraphicsDevicesAndContext devices)
        => new SandSimulationEffectProcessor(devices, this);

    protected override IEnumerable<IAnimatable> GetAnimatables()
        => _animatables ??=
        [
            IterationsPerFrame,
            WarmupIterations,
            Spread,
            ReactionStrength,
            SolidGravity,
            SolidStiffness,
            SolidBreakStrength,
            SolidSolverIterations,
            ExplosionX,
            ExplosionY,
            ExplosionTriggerFrame,
            ExplosionStrength,
            ExplosionRadius,
            LightingStrength,
            LightingRadius,
            AmbientLight,
            ShadowStrength,
            AlphaThreshold,
            LuminanceThreshold,
        ];
}
