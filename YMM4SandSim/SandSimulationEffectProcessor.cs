using System.Numerics;
using Vortice.Direct2D1;
using Vortice.Direct2D1.Effects;
using YMM4SandSim.Diagnostics;
using YukkuriMovieMaker.Commons;
using YukkuriMovieMaker.Player.Video;
using YukkuriMovieMaker.Player.Video.Effects;

namespace YMM4SandSim;

/// <summary>
/// YMM4 video-effect processor.
///
/// This class intentionally implements <see cref="IVideoEffectProcessor"/> directly.
/// The source/simulation blend is performed by the plugin-owned D3D render pass.
/// Keeping managed Direct2D custom-effect callback shadows out of the output graph
/// avoids retaining those callbacks when YMM4 chains or replaces processors.
/// </summary>
internal sealed class SandSimulationEffectProcessor : IVideoEffectProcessor
{
    private readonly IGraphicsDevicesAndContext _devices;
    private readonly SandSimulationEffect _item;

    private SandSimulationGpu? _gpu;
    private Crop? _outputCrop;
    private ID2D1Image? _outputCropOutput;
    private AffineTransform2D? _outputTransform;
    private ID2D1Image? _outputTransformOutput;
    private ID2D1Image? _input;

    private bool _isFirst = true;
    private bool _hasOutput;
    private bool _hasOutputOffset;
    private bool _hasCropRect;
    private bool _disposed;
    private long _lastFrame = long.MinValue;
    private Vector2 _outputOffset;
    private Vector4 _cropRect;
    private Parameters _parameters;
    private StateKey _stateKey;
    private SourceGeometry _snapshotGeometry;
    private bool _hasSnapshotGeometry;
    private string? _lastUpdateErrorKey;

    /// <summary>
    /// The effect output consumed by YMM4. Until the first valid GPU result is
    /// available, this falls back to the current input.
    /// </summary>
    public ID2D1Image Output
        => (_hasOutput ? _outputTransformOutput : null) ??
           _input ??
           throw new InvalidOperationException("The video-effect input has not been set.");

    public SandSimulationEffectProcessor(IGraphicsDevicesAndContext devices, SandSimulationEffect item)
    {
        _devices = devices;
        _item = item;
        PluginLog.Initialize();
        PluginLog.Information("Video effect processor created");
        CreateResources(devices);
    }

    public void SetInput(ID2D1Image? inputImage)
    {
        if (_disposed)
            return;

        _input = inputImage;
    }

    public void ClearInput()
    {
        if (_disposed)
            return;

        _input = null;
        ResetTimelineState();
    }

    public DrawDescription Update(EffectDescription effectDescription)
    {
        try
        {
            var result = UpdateCore(effectDescription);
            _lastUpdateErrorKey = null;
            return result;
        }
        catch (Exception exception)
        {
            var errorKey = $"{exception.GetType().FullName}|{exception.HResult}|{exception.Message}";
            if (!string.Equals(_lastUpdateErrorKey, errorKey, StringComparison.Ordinal))
            {
                _lastUpdateErrorKey = errorKey;
                PluginLog.Error(
                    $"Video effect update failed. frame={effectDescription.ItemPosition.Frame}",
                    exception);
            }

            throw;
        }
    }

    private DrawDescription UpdateCore(EffectDescription effectDescription)
    {
        if (_disposed || _outputCrop is null ||
            _outputTransform is null || _outputTransformOutput is null ||
            _gpu is null || _input is null)
        {
            return effectDescription.DrawDescription;
        }

        var frame = effectDescription.ItemPosition.Frame;
        var length = effectDescription.ItemDuration.Frame;
        var fps = effectDescription.FPS;
        var parameters = new Parameters(
            IsScreenSize: _item.IsScreenSize,
            SourceMode: SandSimulationSettings.NormalizeSourceMode(_item.SourceMode),
            ParticleSize: SandSimulationSettings.NormalizeParticleSize(_item.ParticleSize),
            IterationsPerFrame: ClampRounded(_item.IterationsPerFrame.GetValue(frame, length, fps), 1, SandSimulationSettings.MaximumIterationsPerFrame),
            WarmupIterations: ClampRounded(_item.WarmupIterations.GetValue(frame, length, fps), 0, SandSimulationSettings.MaximumWarmupIterations),
            Spread: ClampUnit(_item.Spread.GetValue(frame, length, fps) / 100.0),
            ReactionStrength: ClampFiniteAtLeast(
                _item.ReactionStrength.GetValue(frame, length, fps) / 100.0,
                0f),
            SolidPhysicsMode: SandSimulationSettings.NormalizeSolidPhysicsMode(_item.SolidPhysicsMode),
            SolidGravity: ClampFiniteAtLeast(
                _item.SolidGravity.GetValue(frame, length, fps) / 100.0,
                0f),
            SolidStiffness: ClampFiniteAtLeast(
                _item.SolidStiffness.GetValue(frame, length, fps) / 100.0,
                0f),
            SolidBreakStrength: ClampFiniteAtLeast(
                _item.SolidBreakStrength.GetValue(frame, length, fps) / 100.0,
                0f),
            SolidSolverIterations: ClampRounded(_item.SolidSolverIterations.GetValue(frame, length, fps), 1, SandSimulationSettings.MaximumSolidSolverIterations),
            ExplosionControllerEnabled: _item.ExplosionControllerEnabled,
            ExplosionX: FiniteOrZero(_item.ExplosionX.GetValue(frame, length, fps)),
            ExplosionY: FiniteOrZero(_item.ExplosionY.GetValue(frame, length, fps)),
            ExplosionTriggerFrame: RoundAtLeast(_item.ExplosionTriggerFrame.GetValue(frame, length, fps), 0),
            ExplosionStrength: ClampFiniteAtLeast(
                _item.ExplosionStrength.GetValue(frame, length, fps) / 100.0,
                0f),
            ExplosionRadius: RoundAtLeast(_item.ExplosionRadius.GetValue(frame, length, fps), 2),
            LightingStrength: ClampFiniteAtLeast(
                _item.LightingStrength.GetValue(frame, length, fps) / 100.0,
                0f),
            LightingRadius: ClampRounded(_item.LightingRadius.GetValue(frame, length, fps), 1, SandSimulationSettings.MaximumLightingRadius),
            AmbientLight: ClampUnit(_item.AmbientLight.GetValue(frame, length, fps) / 100.0),
            ShadowStrength: ClampUnit(_item.ShadowStrength.GetValue(frame, length, fps) / 100.0),
            MaterialAssignment: SandSimulationSettings.NormalizeMaterialAssignment(_item.MaterialAssignment),
            SingleMaterial: SandSimulationSettings.NormalizeMaterial(_item.SingleMaterial),
            ColorMode: SandSimulationSettings.NormalizeColorMode(_item.ColorMode),
            MaskMode: SandSimulationSettings.NormalizeMaskMode(_item.MaskMode),
            AlphaThreshold: ClampUnit(_item.AlphaThreshold.GetValue(frame, length, fps) / 100.0),
            LuminanceThreshold: ClampUnit(_item.LuminanceThreshold.GetValue(frame, length, fps) / 100.0));

        SourceGeometry geometry;
        if (parameters.IsScreenSize)
        {
            if (!TryGetScreenGeometry(effectDescription, out geometry))
            {
                ResetTimelineState();
                return effectDescription.DrawDescription;
            }
        }
        else if (SandSnapshotGeometryPolicy.CanReuse(
                parameters.SourceMode,
                _hasSnapshotGeometry,
                _isFirst,
                frame,
                _lastFrame) &&
            !_snapshotGeometry.IsScreenSize)
        {
            geometry = _snapshotGeometry;
        }
        else if (!TryGetInputGeometry(_input, out geometry))
        {
            ResetTimelineState();
            return effectDescription.DrawDescription;
        }

        if (parameters.SourceMode == SandSourceMode.Snapshot)
        {
            _snapshotGeometry = geometry;
            _hasSnapshotGeometry = true;
        }
        else
        {
            _hasSnapshotGeometry = false;
        }

        var itemWidth = geometry.Width;
        var itemHeight = geometry.Height;
        var solidPhysicsEnabled = parameters.SolidPhysicsMode == SandSolidPhysicsMode.Xpbd;
        var explosionEnabled = parameters.ExplosionStrength > 0.0f;
        var lightingEnabled = parameters.LightingStrength > 0.0f;
        if (!SandSimulationSettings.IsSimulationSizeSupported(
                itemWidth,
                itemHeight,
                parameters.ParticleSize,
                solidPhysicsEnabled,
                explosionEnabled,
                lightingEnabled))
        {
            // Fail closed before allocating D3D11 state textures; the source-pixel
            // cap alone does not bound the expanded per-cell simulation state.
            ResetTimelineState();
            return effectDescription.DrawDescription;
        }

        var resourcesChanged = _gpu.EnsureResources(
            itemWidth,
            itemHeight,
            parameters.ParticleSize,
            solidPhysicsEnabled,
            explosionEnabled,
            lightingEnabled);
        var stateKey = StateKey.Create(itemWidth, itemHeight, in parameters);

        var simulationParametersChanged = !_isFirst && !_parameters.SimulationEquals(parameters);
        var renderParametersChanged = _isFirst ||
            _parameters.ColorMode != parameters.ColorMode ||
            _parameters.LightingStrength != parameters.LightingStrength ||
            _parameters.LightingRadius != parameters.LightingRadius ||
            _parameters.AmbientLight != parameters.AmbientLight ||
            _parameters.ShadowStrength != parameters.ShadowStrength;
        var decision = SandTimelinePolicy.Decide(
            isFirst: _isFirst,
            frame: frame,
            lastFrame: _lastFrame,
            resourcesChanged: resourcesChanged,
            stateKeyChanged: _stateKey != stateKey,
            simulationParametersChanged: simulationParametersChanged,
            sourceMode: parameters.SourceMode);

        if (decision.NeedsInput)
        {
            _gpu.RenderInput(_input, geometry.Bounds);
        }

        var manualExplosionThisFrame = SandExplosionTriggerPolicy.ShouldTrigger(
            parameters.ExplosionControllerEnabled,
            parameters.ExplosionTriggerFrame,
            frame,
            _lastFrame,
            _isFirst,
            decision.Reset);

        var gpuParameters = new SandSimulationGpu.FrameParameters(
            FrameIndex: frame,
            ParticleSize: parameters.ParticleSize,
            MaskMode: parameters.MaskMode,
            AlphaThreshold: parameters.AlphaThreshold,
            LuminanceThreshold: parameters.LuminanceThreshold,
            Spread: parameters.Spread,
            ReactionStrength: parameters.ReactionStrength,
            SolidPhysicsMode: parameters.SolidPhysicsMode,
            SolidGravity: parameters.SolidGravity,
            SolidStiffness: parameters.SolidStiffness,
            SolidBreakStrength: parameters.SolidBreakStrength,
            SolidSolverIterations: parameters.SolidSolverIterations,
            ManualExplosion: manualExplosionThisFrame,
            ManualExplosionX: parameters.ExplosionX,
            ManualExplosionY: parameters.ExplosionY,
            ExplosionStrength: parameters.ExplosionStrength,
            ExplosionRadius: Math.Max(
                1, (parameters.ExplosionRadius + parameters.ParticleSize - 1) / parameters.ParticleSize),
            LightingStrength: parameters.LightingStrength,
            LightingRadius: parameters.LightingRadius,
            AmbientLight: parameters.AmbientLight,
            ShadowStrength: parameters.ShadowStrength,
            MaterialAssignment: parameters.MaterialAssignment,
            SingleMaterial: parameters.SingleMaterial,
            ColorMode: parameters.ColorMode,
            Seed: SandSimulationSettings.DefaultSeed);
        var warmupGpuParameters = gpuParameters with { ManualExplosion = false };

        if (decision.NeedsAdvance)
        {
            switch (parameters.SourceMode)
            {
                case SandSourceMode.Snapshot:
                    if (decision.Reset)
                    {
                        _gpu.Initialize(in gpuParameters, SandSimulationGpu.InitializeMode.ClearAndRebuild);
                        _gpu.Step(in warmupGpuParameters, parameters.WarmupIterations);
                    }
                    _gpu.Step(in gpuParameters, parameters.IterationsPerFrame);
                    break;

                case SandSourceMode.ContinuousEmitter:
                    _gpu.Initialize(in gpuParameters, decision.Reset
                        ? SandSimulationGpu.InitializeMode.ClearAndRebuild
                        : SandSimulationGpu.InitializeMode.FillEmptyOnly);
                    if (decision.Reset)
                        _gpu.Step(in warmupGpuParameters, parameters.WarmupIterations);
                    _gpu.Step(in gpuParameters, parameters.IterationsPerFrame);
                    break;

                case SandSourceMode.AddEveryFrame:
                    _gpu.Initialize(in gpuParameters, decision.Reset
                        ? SandSimulationGpu.InitializeMode.ClearAndRebuild
                        : SandSimulationGpu.InitializeMode.StampSelectedEveryFrame);
                    if (decision.Reset)
                        _gpu.Step(in warmupGpuParameters, parameters.WarmupIterations);
                    _gpu.Step(in gpuParameters, parameters.IterationsPerFrame);
                    break;

                default:
                    throw new ArgumentOutOfRangeException(
                        nameof(effectDescription),
                        parameters.SourceMode,
                        "The normalized source mode is not supported.");
            }

            _gpu.Render(in gpuParameters);
        }
        else if (renderParametersChanged)
        {
            _gpu.Render(in gpuParameters);
        }

        if (resourcesChanged || !_hasOutput)
        {
            _outputCrop.SetInput(0, _gpu.OutputBitmap, true);
        }

        var cropRect = new Vector4(0f, 0f, itemWidth, itemHeight);
        if (!_hasCropRect || _cropRect != cropRect)
        {
            _outputCrop.Rectangle = cropRect;
            _cropRect = cropRect;
            _hasCropRect = true;
        }

        var outputOffset = geometry.Offset;
        if (!_hasOutputOffset || _outputOffset != outputOffset)
        {
            _outputTransform.TransformMatrix = Matrix3x2.CreateTranslation(outputOffset);
            _outputOffset = outputOffset;
            _hasOutputOffset = true;
        }

        _hasOutput = true;
        _parameters = parameters;
        _stateKey = stateKey;
        _lastFrame = frame;
        _isFirst = false;

        var drawDescription = effectDescription.DrawDescription;
        if (parameters.ExplosionControllerEnabled)
        {
            // VideoEffectController coordinates are item-local and centered, matching
            // YMM4's X/Y effect parameters. The second point is a horizontal radius
            // handle; ExplosionRadius is already expressed in screen pixels.
            var radiusPixels = (float)parameters.ExplosionRadius;
            var controller = new VideoEffectController(
                _item,
                [
                    new ControllerPoint(
                        new Vector3(parameters.ExplosionX, parameters.ExplosionY, 0f),
                        args =>
                        {
                            _item.ExplosionX.AddToEachValues(args.Delta.X);
                            _item.ExplosionY.AddToEachValues(args.Delta.Y);
                        }),
                    new ControllerPoint(
                        new Vector3(parameters.ExplosionX + radiusPixels, parameters.ExplosionY, 0f),
                        args =>
                        {
                            _item.ExplosionRadius.AddToEachValues(args.Delta.X);
                        }),
                ])
            {
                Connection = VideoControllerPointConnection.Line,
            };
            drawDescription = drawDescription with
            {
                Controllers = [.. drawDescription.Controllers, controller],
            };
        }

        return drawDescription;
    }

    public void Dispose()
    {
        if (_disposed)
            return;

        PluginLog.Information("Video effect processor disposing");
        _disposed = true;

        // Disconnect all graph edges before releasing their independently
        // owned outputs and effects.
        ClearEffectGraph();
        _input = null;

        _outputTransformOutput?.Dispose();
        _outputTransformOutput = null;
        _outputTransform?.Dispose();
        _outputTransform = null;

        _outputCropOutput?.Dispose();
        _outputCropOutput = null;
        _outputCrop?.Dispose();
        _outputCrop = null;

        _gpu?.Dispose();
        _gpu = null;
    }

    private void CreateResources(IGraphicsDevicesAndContext devices)
    {
        SandSimulationGpu? gpu = null;
        Crop? outputCrop = null;
        ID2D1Image? outputCropOutput = null;
        AffineTransform2D? outputTransform = null;
        ID2D1Image? outputTransformOutput = null;

        try
        {
            gpu = SandSimulationGpu.TryCreate(devices);
            if (gpu is null)
                return;

            outputCrop = new Crop(devices.DeviceContext);
            outputCropOutput = outputCrop.Output;
            outputTransform = new AffineTransform2D(devices.DeviceContext)
            {
                BorderMode = BorderMode.Hard,
            };
            outputTransform.SetInput(0, outputCropOutput, true);
            outputTransformOutput = outputTransform.Output;

            _gpu = gpu;
            _outputCrop = outputCrop;
            _outputCropOutput = outputCropOutput;
            _outputTransform = outputTransform;
            _outputTransformOutput = outputTransformOutput;
            gpu = null;
        }
        catch (Exception exception)
        {
            PluginLog.Error("Direct2D output graph initialization failed", exception);
            outputTransformOutput?.Dispose();
            outputTransform?.SetInput(0, null, true);
            outputTransform?.Dispose();
            outputCropOutput?.Dispose();
            outputCrop?.SetInput(0, null, true);
            outputCrop?.Dispose();
            throw;
        }
        finally
        {
            gpu?.Dispose();
        }
    }

    private static bool TryGetScreenGeometry(
        EffectDescription effectDescription,
        out SourceGeometry geometry)
    {
        var widthValue = Math.Ceiling((double)effectDescription.ScreenSize.Width);
        var heightValue = Math.Ceiling((double)effectDescription.ScreenSize.Height);
        if (!TryNormalizeGeometrySize(widthValue, heightValue, out var width, out var height))
        {
            geometry = default;
            return false;
        }

        // YMM4's item-local origin is the center of the screen. Keep the
        // simulation canvas centered on that origin so its output covers the
        // full screen instead of starting at the screen center.
        var left = -width / 2f;
        var top = -height / 2f;
        geometry = new SourceGeometry(
            width,
            height,
            new Vector2(left, top),
            new Vortice.RawRectF(left, top, left + width, top + height),
            IsScreenSize: true);
        return true;
    }

    private bool TryGetInputGeometry(ID2D1Image input, out SourceGeometry geometry)
    {
        geometry = default;
        var bounds = _devices.DeviceContext.GetImageLocalBounds(input);
        var widthValue = Math.Ceiling((double)bounds.Right - bounds.Left);
        var heightValue = Math.Ceiling((double)bounds.Bottom - bounds.Top);
        if (!float.IsFinite(bounds.Left) || !float.IsFinite(bounds.Top) ||
            !TryNormalizeGeometrySize(widthValue, heightValue, out var width, out var height))
        {
            return false;
        }

        geometry = new SourceGeometry(
            width,
            height,
            new Vector2(bounds.Left, bounds.Top),
            new Vortice.RawRectF(bounds.Left, bounds.Top, bounds.Left + width, bounds.Top + height),
            IsScreenSize: false);
        return true;
    }

    private static bool TryNormalizeGeometrySize(
        double widthValue,
        double heightValue,
        out int width,
        out int height)
    {
        width = 0;
        height = 0;
        if (!double.IsFinite(widthValue) || !double.IsFinite(heightValue) ||
            widthValue <= 0d || heightValue <= 0d ||
            Math.Max(widthValue, heightValue) > SandSimulationSettings.MaximumCanvasSize ||
            widthValue * heightValue > SandSimulationSettings.MaximumSourcePixelCount)
        {
            return false;
        }

        width = checked((int)widthValue);
        height = checked((int)heightValue);
        return true;
    }

    private void ClearEffectGraph()
    {
        _outputTransform?.SetInput(0, null, true);
        _outputCrop?.SetInput(0, null, true);
    }

    private void ResetTimelineState()
    {
        _isFirst = true;
        _hasOutput = false;
        _hasOutputOffset = false;
        _hasCropRect = false;
        _lastFrame = long.MinValue;
    }

    private static int ClampRounded(double value, int minimum, int maximum)
        => double.IsFinite(value)
            ? Math.Clamp((int)Math.Round(value), minimum, maximum)
            : minimum;

    private static float ClampUnit(double value)
        => double.IsFinite(value)
            ? Math.Clamp((float)value, 0f, 1f)
            : 0f;

    private static int RoundAtLeast(double value, int minimum)
        => double.IsFinite(value)
            ? Math.Max((int)Math.Clamp(Math.Round(value), int.MinValue, int.MaxValue), minimum)
            : minimum;

    private static float ClampFiniteAtLeast(double value, float minimum)
        => double.IsFinite(value)
            ? Math.Max((float)value, minimum)
            : minimum;

    private static float FiniteOrZero(double value)
        => double.IsFinite(value) ? (float)value : 0f;

    private readonly record struct SourceGeometry(
        int Width,
        int Height,
        Vector2 Offset,
        Vortice.RawRectF Bounds,
        bool IsScreenSize);

    private readonly record struct Parameters(
        bool IsScreenSize,
        SandSourceMode SourceMode,
        int ParticleSize,
        int IterationsPerFrame,
        int WarmupIterations,
        float Spread,
        float ReactionStrength,
        SandSolidPhysicsMode SolidPhysicsMode,
        float SolidGravity,
        float SolidStiffness,
        float SolidBreakStrength,
        int SolidSolverIterations,
        bool ExplosionControllerEnabled,
        float ExplosionX,
        float ExplosionY,
        int ExplosionTriggerFrame,
        float ExplosionStrength,
        int ExplosionRadius,
        float LightingStrength,
        int LightingRadius,
        float AmbientLight,
        float ShadowStrength,
        SandMaterialAssignment MaterialAssignment,
        SandMaterial SingleMaterial,
        SandColorMode ColorMode,
        SandMaskMode MaskMode,
        float AlphaThreshold,
        float LuminanceThreshold)
    {
        public bool SimulationEquals(in Parameters other)
            => IsScreenSize == other.IsScreenSize &&
               SourceMode == other.SourceMode &&
               ParticleSize == other.ParticleSize &&
               IterationsPerFrame == other.IterationsPerFrame &&
               WarmupIterations == other.WarmupIterations &&
               Spread == other.Spread &&
               ReactionStrength == other.ReactionStrength &&
               SolidPhysicsMode == other.SolidPhysicsMode &&
               SolidGravity == other.SolidGravity &&
               SolidStiffness == other.SolidStiffness &&
               SolidBreakStrength == other.SolidBreakStrength &&
               SolidSolverIterations == other.SolidSolverIterations &&
               ExplosionControllerEnabled == other.ExplosionControllerEnabled &&
               ExplosionX == other.ExplosionX &&
               ExplosionY == other.ExplosionY &&
               ExplosionTriggerFrame == other.ExplosionTriggerFrame &&
               ExplosionStrength == other.ExplosionStrength &&
               ExplosionRadius == other.ExplosionRadius &&
               MaterialAssignment == other.MaterialAssignment &&
               SingleMaterial == other.SingleMaterial &&
               MaskMode == other.MaskMode &&
               AlphaThreshold == other.AlphaThreshold &&
               LuminanceThreshold == other.LuminanceThreshold;
    }

    private readonly record struct StateKey(
        int Width,
        int Height,
        bool IsScreenSize,
        int ParticleSize,
        SandSourceMode SourceMode,
        SandSolidPhysicsMode SolidPhysicsMode,
        SandMaterialAssignment MaterialAssignment,
        SandMaterial SingleMaterial,
        SandMaskMode MaskMode,
        float AlphaThreshold,
        float LuminanceThreshold)
    {
        public static StateKey Create(int width, int height, in Parameters parameters)
        {
            // Snapshot extraction defines the persistent initial state. In the
            // emitter modes, extraction settings affect only newly injected
            // cells and must not clear grains accumulated by earlier frames.
            var tracksPersistentInitialState = SandTimelinePolicy.ExtractionDefinesPersistentState(parameters.SourceMode);
            return new StateKey(
                width,
                height,
                parameters.IsScreenSize,
                parameters.ParticleSize,
                parameters.SourceMode,
                parameters.SolidPhysicsMode,
                tracksPersistentInitialState ? parameters.MaterialAssignment : default,
                tracksPersistentInitialState ? parameters.SingleMaterial : default,
                tracksPersistentInitialState ? parameters.MaskMode : default,
                tracksPersistentInitialState ? parameters.AlphaThreshold : 0f,
                tracksPersistentInitialState ? parameters.LuminanceThreshold : 0f);
        }
    }
}
