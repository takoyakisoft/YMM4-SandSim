using System.Numerics;
using System.IO;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using SharpGen.Runtime;
using Vortice;
using Vortice.Direct2D1;
using Vortice.Direct3D;
using Vortice.Direct3D11;
using Vortice.DXGI;
using YMM4SandSim.Diagnostics;
using YukkuriMovieMaker.Commons;
using D3DFeatureLevel = Vortice.Direct3D.FeatureLevel;
using PixelFormat = Vortice.DCommon.PixelFormat;
using D2DInterpolationMode = Vortice.Direct2D1.InterpolationMode;

namespace YMM4SandSim;

internal sealed class SandSimulationGpu : IDisposable
{
    internal enum InitializeMode : uint
    {
        ClearAndRebuild = 0u,
        FillEmptyOnly = 1u,
        StampSelectedEveryFrame = 2u,
    }

    private static readonly ID3D11ShaderResourceView[] NullShaderResourceViews = new ID3D11ShaderResourceView[8];
    private static readonly ID3D11UnorderedAccessView[] NullUnorderedAccessViews = new ID3D11UnorderedAccessView[8];
    private static readonly ID3D11Buffer[] NullConstantBuffers = new ID3D11Buffer[1];
    private static readonly D3DFeatureLevel[] ContextStateFeatureLevels =
    [
        D3DFeatureLevel.Level_11_1,
        D3DFeatureLevel.Level_11_0,
    ];

    private readonly ID3D11Device1 _device;
    private readonly ID3D11DeviceContext1 _context;
    private readonly ID3DDeviceContextState _isolatedContextState;
    private readonly ID3D11Multithread _multithread;
    private readonly ID2D1DeviceContext6 _renderContext;
    private readonly ID3D11ComputeShader _initializeShader;
    private readonly ID3D11ComputeShader _stepShader;
    private readonly ID3D11ComputeShader _rigidInitializeShader;
    private readonly ID3D11ComputeShader _rigidIntegrateShader;
    private readonly ID3D11ComputeShader _rigidSolveShader;
    private readonly ID3D11ComputeShader _rigidGridShader;
    private readonly ID3D11ComputeShader _rigidReactShader;
    private readonly ID3D11ComputeShader _explosionUpdateShader;
    private readonly ID3D11ComputeShader _lightSeedShader;
    private readonly ID3D11ComputeShader _lightPropagateShader;
    private readonly ID3D11VertexShader _fullscreenVertexShader;
    private readonly ID3D11PixelShader _renderPixelShader;
    private readonly ID3D11Buffer _constantBuffer;
    private readonly ID3D11Buffer[] _rigidSolveConstantBuffers;

    private ID3D11Texture2D? _sourceTexture;
    private ID3D11ShaderResourceView? _sourceSrv;
    private ID2D1Bitmap1? _sourceBitmap;

    private ID3D11Texture2D? _outputTexture;
    private ID3D11RenderTargetView? _outputRtv;
    private ID2D1Bitmap1? _outputBitmap;

    private readonly ID3D11Texture2D?[] _stateColorTextures = new ID3D11Texture2D?[2];
    private readonly ID3D11ShaderResourceView?[] _stateColorSrvs = new ID3D11ShaderResourceView?[2];
    private readonly ID3D11UnorderedAccessView?[] _stateColorUavs = new ID3D11UnorderedAccessView?[2];
    private readonly ID3D11Texture2D?[] _stateMetaTextures = new ID3D11Texture2D?[2];
    private readonly ID3D11ShaderResourceView?[] _stateMetaSrvs = new ID3D11ShaderResourceView?[2];
    private readonly ID3D11UnorderedAccessView?[] _stateMetaUavs = new ID3D11UnorderedAccessView?[2];

    private ID3D11Texture2D? _rigidStateTexture;
    private ID3D11ShaderResourceView? _rigidStateSrv;
    private ID3D11UnorderedAccessView? _rigidStateUav;
    private ID3D11Texture2D? _rigidColorTexture;
    private ID3D11ShaderResourceView? _rigidColorSrv;
    private ID3D11UnorderedAccessView? _rigidColorUav;
    private ID3D11Texture2D? _rigidMetaTexture;
    private ID3D11ShaderResourceView? _rigidMetaSrv;
    private ID3D11UnorderedAccessView? _rigidMetaUav;
    private ID3D11Texture2D? _rigidLambdaTexture;
    private ID3D11UnorderedAccessView? _rigidLambdaUav;
    private ID3D11Texture2D? _rigidOccupancyTexture;
    private ID3D11ShaderResourceView? _rigidOccupancySrv;
    private ID3D11UnorderedAccessView? _rigidOccupancyUav;

    private readonly ID3D11Texture2D?[] _explosionPressureTextures = new ID3D11Texture2D?[2];
    private readonly ID3D11ShaderResourceView?[] _explosionPressureSrvs = new ID3D11ShaderResourceView?[2];
    private readonly ID3D11UnorderedAccessView?[] _explosionPressureUavs = new ID3D11UnorderedAccessView?[2];
    private readonly ID3D11Texture2D?[] _lightTextures = new ID3D11Texture2D?[2];
    private readonly ID3D11ShaderResourceView?[] _lightSrvs = new ID3D11ShaderResourceView?[2];
    private readonly ID3D11UnorderedAccessView?[] _lightUavs = new ID3D11UnorderedAccessView?[2];

    private int _sourceWidth;
    private int _sourceHeight;
    private int _stateWidth;
    private int _stateHeight;
    private int _logicalStateWidth;
    private int _logicalStateHeight;
    private int _currentState;
    private int _currentExplosionPressure;
    private bool _explosionPressureDirty;
    private int _currentLight;
    private uint _globalStep;
    private bool _manualExplosionWaveActive;
    private bool _manualExplosionWaveVisible;
    private uint _manualExplosionWaveNextStep;
    private uint _manualExplosionWaveRenderedStep;
    private uint _manualExplosionCellX;
    private uint _manualExplosionCellY;
    private bool _disposed;

    private SandSimulationGpu(
        ID3D11Device1 device,
        ID3D11DeviceContext1 context,
        ID3DDeviceContextState isolatedContextState,
        ID3D11Multithread multithread,
        ID2D1DeviceContext6 renderContext,
        ID3D11ComputeShader initializeShader,
        ID3D11ComputeShader stepShader,
        ID3D11ComputeShader rigidInitializeShader,
        ID3D11ComputeShader rigidIntegrateShader,
        ID3D11ComputeShader rigidSolveShader,
        ID3D11ComputeShader rigidGridShader,
        ID3D11ComputeShader rigidReactShader,
        ID3D11ComputeShader explosionUpdateShader,
        ID3D11ComputeShader lightSeedShader,
        ID3D11ComputeShader lightPropagateShader,
        ID3D11VertexShader fullscreenVertexShader,
        ID3D11PixelShader renderPixelShader,
        ID3D11Buffer constantBuffer,
        ID3D11Buffer[] rigidSolveConstantBuffers)
    {
        _device = device;
        _context = context;
        _isolatedContextState = isolatedContextState;
        _multithread = multithread;
        _renderContext = renderContext;
        _initializeShader = initializeShader;
        _stepShader = stepShader;
        _rigidInitializeShader = rigidInitializeShader;
        _rigidIntegrateShader = rigidIntegrateShader;
        _rigidSolveShader = rigidSolveShader;
        _rigidGridShader = rigidGridShader;
        _rigidReactShader = rigidReactShader;
        _explosionUpdateShader = explosionUpdateShader;
        _lightSeedShader = lightSeedShader;
        _lightPropagateShader = lightPropagateShader;
        _fullscreenVertexShader = fullscreenVertexShader;
        _renderPixelShader = renderPixelShader;
        _constantBuffer = constantBuffer;
        _rigidSolveConstantBuffers = rigidSolveConstantBuffers;
    }

    public ID2D1Bitmap1 OutputBitmap
        => _outputBitmap ?? throw new InvalidOperationException("Output resources are not initialized.");

    public static SandSimulationGpu? TryCreate(IGraphicsDevicesAndContext devices)
    {
        ID3D11Device1? device = null;
        ID3D11DeviceContext1? context = null;
        ID3DDeviceContextState? isolatedContextState = null;
        ID3D11Multithread? multithread = null;
        ID2D1DeviceContext6? renderContext = null;
        ID3D11ComputeShader? initializeShader = null;
        ID3D11ComputeShader? stepShader = null;
        ID3D11ComputeShader? rigidInitializeShader = null;
        ID3D11ComputeShader? rigidIntegrateShader = null;
        ID3D11ComputeShader? rigidSolveShader = null;
        ID3D11ComputeShader? rigidGridShader = null;
        ID3D11ComputeShader? rigidReactShader = null;
        ID3D11ComputeShader? explosionUpdateShader = null;
        ID3D11ComputeShader? lightSeedShader = null;
        ID3D11ComputeShader? lightPropagateShader = null;
        ID3D11VertexShader? fullscreenVertexShader = null;
        ID3D11PixelShader? renderPixelShader = null;
        ID3D11Buffer? constantBuffer = null;
        var rigidSolveConstantBuffers = new ID3D11Buffer[4];

        try
        {
            device = devices.D3D.Device.QueryInterface<ID3D11Device1>();
            context = devices.D3D.DeviceContext.QueryInterface<ID3D11DeviceContext1>();
            multithread = context.QueryInterface<ID3D11Multithread>();
            multithread.SetMultithreadProtected(true);
            isolatedContextState = device.CreateDeviceContextState<ID3D11Device1>(
                CreateDeviceContextStateFlags.None,
                ContextStateFeatureLevels,
                out _);
            renderContext = devices.D2D.Device.CreateDeviceContext(DeviceContextOptions.EnableMultithreadedOptimizations);

            initializeShader = device.CreateComputeShader(ShaderBytecode.Load("SandInitialize"));
            stepShader = device.CreateComputeShader(ShaderBytecode.Load("SandStep"));
            rigidInitializeShader = device.CreateComputeShader(ShaderBytecode.Load("SandRigidInitialize"));
            rigidIntegrateShader = device.CreateComputeShader(ShaderBytecode.Load("SandRigidIntegrate"));
            rigidSolveShader = device.CreateComputeShader(ShaderBytecode.Load("SandRigidSolve"));
            rigidGridShader = device.CreateComputeShader(ShaderBytecode.Load("SandRigidGrid"));
            rigidReactShader = device.CreateComputeShader(ShaderBytecode.Load("SandRigidReact"));
            explosionUpdateShader = device.CreateComputeShader(ShaderBytecode.Load("SandExplosionUpdate"));
            lightSeedShader = device.CreateComputeShader(ShaderBytecode.Load("SandLightSeed"));
            lightPropagateShader = device.CreateComputeShader(ShaderBytecode.Load("SandLightPropagate"));
            fullscreenVertexShader = device.CreateVertexShader(ShaderBytecode.Load("SandFullscreenVS"));
            renderPixelShader = device.CreatePixelShader(ShaderBytecode.Load("SandRenderPS"));

            var constantBufferDescription = new BufferDescription
            {
                ByteWidth = Unsafe.SizeOf<GpuConstants>(),
                Usage = ResourceUsage.Dynamic,
                BindFlags = BindFlags.ConstantBuffer,
                CPUAccessFlags = CpuAccessFlags.Write,
                MiscFlags = ResourceOptionFlags.None,
                StructureByteStride = 0,
            };
            constantBuffer = device.CreateBuffer(constantBufferDescription);
            for (var phase = 0; phase < rigidSolveConstantBuffers.Length; phase++)
                rigidSolveConstantBuffers[phase] = device.CreateBuffer(constantBufferDescription);

            return new SandSimulationGpu(
                device,
                context,
                isolatedContextState,
                multithread,
                renderContext,
                initializeShader,
                stepShader,
                rigidInitializeShader,
                rigidIntegrateShader,
                rigidSolveShader,
                rigidGridShader,
                rigidReactShader,
                explosionUpdateShader,
                lightSeedShader,
                lightPropagateShader,
                fullscreenVertexShader,
                renderPixelShader,
                constantBuffer,
                rigidSolveConstantBuffers);
        }
        catch (Exception exception) when (
            exception is SharpGenException or
            IOException or
            InvalidOperationException or
            ArgumentException or
            NotSupportedException)
        {
            PluginLog.Error("GPU resource initialization failed", exception);
            foreach (var buffer in rigidSolveConstantBuffers)
                buffer?.Dispose();
            constantBuffer?.Dispose();
            renderPixelShader?.Dispose();
            fullscreenVertexShader?.Dispose();
            lightPropagateShader?.Dispose();
            lightSeedShader?.Dispose();
            explosionUpdateShader?.Dispose();
            rigidReactShader?.Dispose();
            rigidGridShader?.Dispose();
            rigidSolveShader?.Dispose();
            rigidIntegrateShader?.Dispose();
            rigidInitializeShader?.Dispose();
            stepShader?.Dispose();
            initializeShader?.Dispose();
            renderContext?.Dispose();
            isolatedContextState?.Dispose();
            multithread?.Dispose();
            context?.Dispose();
            device?.Dispose();
            return null;
        }
    }

    public bool EnsureResources(
        int sourceWidth,
        int sourceHeight,
        int particleSize,
        bool solidPhysicsEnabled,
        bool explosionEnabled,
        bool lightingEnabled)
    {
        ThrowIfDisposed();
        if (!SandSimulationSettings.IsSimulationSizeSupported(
                sourceWidth,
                sourceHeight,
                particleSize,
                solidPhysicsEnabled,
                explosionEnabled,
                lightingEnabled))
            throw new ArgumentOutOfRangeException(nameof(particleSize), "Requested simulation state exceeds the GPU safety limit.");

        var logicalStateWidth = DivideRoundUp(sourceWidth, particleSize);
        var logicalStateHeight = DivideRoundUp(sourceHeight, particleSize);
        var stateWidth = RoundUpEven(logicalStateWidth);
        var stateHeight = RoundUpEven(logicalStateHeight);
        var frameResourcesChanged =
            _sourceWidth != sourceWidth || _sourceHeight != sourceHeight ||
            _stateWidth != stateWidth || _stateHeight != stateHeight ||
            _logicalStateWidth != logicalStateWidth || _logicalStateHeight != logicalStateHeight ||
            _sourceTexture is null || _outputTexture is null ||
            _stateColorTextures[0] is null || _stateColorTextures[1] is null ||
            _stateMetaTextures[0] is null || _stateMetaTextures[1] is null;

        if (frameResourcesChanged)
        {
            ReleaseFrameResources();
            CreateFrameResources(sourceWidth, sourceHeight, stateWidth, stateHeight, logicalStateWidth, logicalStateHeight);
            _currentState = 0;
            _globalStep = 0;
        }

        if (solidPhysicsEnabled)
            EnsureRigidResources();
        else
            ReleaseRigidResources();

        // Explosion pressure is stateful, so a dirty field survives until Step
        // consumes pending events. An already-clean disabled field can be freed.
        if (!explosionEnabled && !_explosionPressureDirty)
            ReleaseExplosionResources();

        // Lighting is derived from the current simulation every render and has
        // no persistent state, so it can be released immediately when disabled.
        if (!lightingEnabled)
            ReleaseLightResources();

        return frameResourcesChanged;
    }

    public void RenderInput(ID2D1Image source, RawRectF sourceBounds)
    {
        ThrowIfDisposed();
        if (_sourceBitmap is null)
            throw new InvalidOperationException("Source resources are not initialized.");

        // Direct2D protects normal rendering with its own factory lock. Do not
        // acquire the D3D11 lock around Direct2D calls: reversing the D2D/D3D
        // lock order can deadlock another rendering thread.
        _renderContext.Target = _sourceBitmap;
        try
        {
            _renderContext.BeginDraw();
            _renderContext.Clear(null);
            _renderContext.DrawImage(
                source,
                new Vector2(-sourceBounds.Left, -sourceBounds.Top),
                null,
                D2DInterpolationMode.NearestNeighbor,
                CompositeMode.SourceCopy);
            _renderContext.EndDraw();
        }
        finally
        {
            _renderContext.Target = null;
        }
    }

    public void Initialize(in FrameParameters parameters, InitializeMode initializeMode)
    {
        ThrowIfDisposed();
        EnsureReady();

        var destination = 1 - _currentState;
        var sourceSrv = _sourceSrv
            ?? throw new InvalidOperationException("Source shader resource is not initialized.");
        var previousColorSrv = _stateColorSrvs[_currentState]
            ?? throw new InvalidOperationException("Current color state SRV is not initialized.");
        var previousMetaSrv = _stateMetaSrvs[_currentState]
            ?? throw new InvalidOperationException("Current metadata state SRV is not initialized.");
        var destinationColorUav = _stateColorUavs[destination]
            ?? throw new InvalidOperationException("Destination color state UAV is not initialized.");
        var destinationMetaUav = _stateMetaUavs[destination]
            ?? throw new InvalidOperationException("Destination metadata state UAV is not initialized.");

        var previousContextState = EnterIsolatedContext();
        try
        {
            var constants = CreateConstants(in parameters);
            constants.InitializeMode = (uint)initializeMode;
            constants.StepIndex = _globalStep;
            if (initializeMode == InitializeMode.ClearAndRebuild)
                ResetExplosionPressure(ref constants);
            UpdateConstants(in constants);

            _context.CSSetShader(_initializeShader);
            _context.CSSetConstantBuffer(0, _constantBuffer);
            _context.CSSetShaderResource(0, sourceSrv);
            _context.CSSetShaderResource(1, previousColorSrv);
            _context.CSSetShaderResource(2, previousMetaSrv);
            if (parameters.SolidPhysicsMode == SandSolidPhysicsMode.Xpbd)
            {
                _context.CSSetShaderResource(3, _rigidOccupancySrv
                    ?? throw new InvalidOperationException("Rigid occupancy SRV is not initialized."));
            }
            _context.CSSetUnorderedAccessView(0, destinationColorUav);
            _context.CSSetUnorderedAccessView(1, destinationMetaUav);
            _context.Dispatch(DivideRoundUp(_stateWidth, 8), DivideRoundUp(_stateHeight, 8), 1);
            UnbindComputeViews();

            if (parameters.SolidPhysicsMode == SandSolidPhysicsMode.Xpbd)
            {
                var rigidOccupancySrv = _rigidOccupancySrv
                    ?? throw new InvalidOperationException("Rigid occupancy SRV is not initialized.");
                var destinationMetaSrv = _stateMetaSrvs[destination]
                    ?? throw new InvalidOperationException("Destination metadata SRV is not initialized.");
                InitializeRigid(in constants, destinationMetaSrv, rigidOccupancySrv);
                BuildRigidOccupancy(ref constants, resolveConflicts: true, destinationMetaSrv);
            }
            UnbindCompute();
        }
        finally
        {
            LeaveIsolatedContext(previousContextState);
        }

        _currentState = destination;
        if (initializeMode == InitializeMode.ClearAndRebuild)
            _globalStep = 0;
    }

    public void Step(in FrameParameters parameters, int iterations)
    {
        ThrowIfDisposed();
        EnsureReady();
        if (iterations <= 0)
            return;

        var solidPhysicsEnabled = parameters.SolidPhysicsMode == SandSolidPhysicsMode.Xpbd;
        if (solidPhysicsEnabled && _rigidOccupancySrv is null)
            throw new InvalidOperationException("Rigid occupancy SRV is not initialized.");

        var explosionResourcesCreated = parameters.ExplosionStrength > 0.0f && EnsureExplosionResources();

        var previousContextState = EnterIsolatedContext();
        try
        {
            var constants = CreateConstants(in parameters);
            if (explosionResourcesCreated)
                ResetExplosionPressure(ref constants);

            _manualExplosionWaveVisible = false;
            if (parameters.ManualExplosion && parameters.ExplosionStrength > 0.0f)
                StartManualExplosionWave(in constants);

            for (var i = 0; i < iterations; i++)
            {
                var destination = 1 - _currentState;
                var sourceColorSrv = _stateColorSrvs[_currentState]
                    ?? throw new InvalidOperationException("Current color state SRV is not initialized.");
                var sourceMetaSrv = _stateMetaSrvs[_currentState]
                    ?? throw new InvalidOperationException("Current metadata state SRV is not initialized.");
                var destinationColorUav = _stateColorUavs[destination]
                    ?? throw new InvalidOperationException("Destination color state UAV is not initialized.");
                var destinationMetaUav = _stateMetaUavs[destination]
                    ?? throw new InvalidOperationException("Destination metadata state UAV is not initialized.");

                constants.StepIndex = _globalStep;
                constants.ManualExplosionEnabled = parameters.ManualExplosion && i == 0 ? 1u : 0u;
                PrepareManualExplosionWaveForStep(ref constants);
                uint manualExplosionWaveStep = constants.ManualExplosionWaveStep;
                if (parameters.ExplosionStrength > 0.0f)
                {
                    UpdateExplosion(ref constants);
                }
                else if (_explosionPressureDirty)
                {
                    ClearExplosionState(ref constants);
                }

                if (solidPhysicsEnabled)
                    StepRigid(ref constants, sourceMetaSrv);

                constants.StepIndex = _globalStep++;
                constants.PhysicsPass = 0u;
                constants.PhysicsPhase = 0u;
                UpdateConstants(in constants);

                _context.CSSetShader(_stepShader);
                _context.CSSetConstantBuffer(0, _constantBuffer);
                _context.CSSetShaderResource(0, sourceColorSrv);
                _context.CSSetShaderResource(1, sourceMetaSrv);
                if (solidPhysicsEnabled)
                {
                    _context.CSSetShaderResource(2, _rigidOccupancySrv
                        ?? throw new InvalidOperationException("Rigid occupancy SRV is not initialized."));
                }
                if (parameters.ExplosionStrength > 0.0f)
                {
                    _context.CSSetShaderResource(3, _explosionPressureSrvs[_currentExplosionPressure]
                        ?? throw new InvalidOperationException("Explosion pressure SRV is not initialized."));
                }
                _context.CSSetUnorderedAccessView(0, destinationColorUav);
                _context.CSSetUnorderedAccessView(1, destinationMetaUav);
                _context.Dispatch(
                    DivideRoundUp(_stateWidth / 2, 8),
                    DivideRoundUp(_stateHeight / 2, 8),
                    1);
                UnbindComputeViews();
                _currentState = destination;

                if (solidPhysicsEnabled &&
                    (parameters.ReactionStrength > 0.0f || constants.ManualExplosionEnabled != 0u))
                {
                    ReactRigid(ref constants, sourceMetaSrv);
                    BuildRigidOccupancy(ref constants, resolveConflicts: false);
                }

                if (manualExplosionWaveStep != uint.MaxValue)
                {
                    _manualExplosionWaveNextStep = manualExplosionWaveStep + 1u;
                    if ((float)manualExplosionWaveStep < Math.Max(constants.ExplosionRadius, 1.0f))
                    {
                        _manualExplosionWaveRenderedStep = manualExplosionWaveStep;
                        _manualExplosionWaveVisible = true;
                    }
                }
            }

            _context.CSSetConstantBuffers(0, 1, NullConstantBuffers);
            _context.CSSetShader(null);
        }
        finally
        {
            LeaveIsolatedContext(previousContextState);
        }

        if (parameters.ExplosionStrength <= 0.0f && !_explosionPressureDirty)
            ReleaseExplosionResources();
    }

    public void Render(in FrameParameters parameters)
    {
        ThrowIfDisposed();
        EnsureReady();
        if (_outputRtv is null)
            throw new InvalidOperationException("Output render target is not initialized.");

        var solidPhysicsEnabled = parameters.SolidPhysicsMode == SandSolidPhysicsMode.Xpbd;
        var previousContextState = EnterIsolatedContext();
        try
        {
            var colorSrv = _stateColorSrvs[_currentState]
                ?? throw new InvalidOperationException("Current color state SRV is not initialized.");
            var metaSrv = _stateMetaSrvs[_currentState]
                ?? throw new InvalidOperationException("Current metadata state SRV is not initialized.");
            var constants = CreateConstants(in parameters);
            constants.StepIndex = _globalStep;
            PrepareManualExplosionWaveForRender(ref constants);
            BuildLighting(ref constants, parameters.LightingRadius);
            UpdateConstants(in constants);

            _context.OMSetRenderTargets(_outputRtv);
            _context.OMSetBlendState(null);
            _context.OMSetDepthStencilState(null, 0);
            _context.RSSetState(null);
            _context.RSSetViewport(0f, 0f, _sourceWidth, _sourceHeight);
            _context.IASetInputLayout(null);
            _context.IASetPrimitiveTopology(PrimitiveTopology.TriangleList);
            _context.GSSetShader(null);
            _context.HSSetShader(null);
            _context.DSSetShader(null);
            _context.VSSetShader(_fullscreenVertexShader);
            _context.PSSetShader(_renderPixelShader);
            _context.PSSetConstantBuffer(0, _constantBuffer);
            _context.PSSetShaderResource(0, colorSrv);
            _context.PSSetShaderResource(1, metaSrv);
            if (solidPhysicsEnabled)
            {
                _context.PSSetShaderResource(2, _rigidOccupancySrv
                    ?? throw new InvalidOperationException("Rigid occupancy SRV is not initialized."));
                _context.PSSetShaderResource(3, _rigidColorSrv
                    ?? throw new InvalidOperationException("Rigid color SRV is not initialized."));
                _context.PSSetShaderResource(4, _rigidMetaSrv
                    ?? throw new InvalidOperationException("Rigid metadata SRV is not initialized."));
            }
            if (parameters.LightingStrength > 0.0f)
            {
                _context.PSSetShaderResource(5, _lightSrvs[_currentLight]
                    ?? throw new InvalidOperationException("Light field SRV is not initialized."));
            }
            _context.Draw(3, 0);

            _context.PSSetShaderResources(0, 6, NullShaderResourceViews);
            _context.PSSetConstantBuffers(0, 1, NullConstantBuffers);
            _context.VSSetShader(null);
            _context.PSSetShader(null);
            _context.UnsetRenderTargets();
        }
        finally
        {
            LeaveIsolatedContext(previousContextState);
        }
    }

    private void InitializeRigid(
        in GpuConstants constants,
        ID3D11ShaderResourceView cellularMetaSrv,
        ID3D11ShaderResourceView existingRigidOccupancySrv)
    {
        var sourceSrv = _sourceSrv
            ?? throw new InvalidOperationException("Source SRV is not initialized.");
        var rigidStateUav = _rigidStateUav
            ?? throw new InvalidOperationException("Rigid state UAV is not initialized.");
        var rigidColorUav = _rigidColorUav
            ?? throw new InvalidOperationException("Rigid color UAV is not initialized.");
        var rigidMetaUav = _rigidMetaUav
            ?? throw new InvalidOperationException("Rigid metadata UAV is not initialized.");
        var rigidLambdaUav = _rigidLambdaUav
            ?? throw new InvalidOperationException("Rigid lambda UAV is not initialized.");

        UpdateConstants(in constants);
        _context.CSSetShader(_rigidInitializeShader);
        _context.CSSetConstantBuffer(0, _constantBuffer);
        _context.CSSetShaderResource(0, sourceSrv);
        _context.CSSetShaderResource(1, cellularMetaSrv);
        if (constants.InitializeMode != (uint)InitializeMode.ClearAndRebuild)
            _context.CSSetShaderResource(2, existingRigidOccupancySrv);
        _context.CSSetUnorderedAccessView(0, rigidStateUav);
        _context.CSSetUnorderedAccessView(1, rigidColorUav);
        _context.CSSetUnorderedAccessView(2, rigidMetaUav);
        _context.CSSetUnorderedAccessView(3, rigidLambdaUav);
        _context.Dispatch(DivideRoundUp(_stateWidth, 8), DivideRoundUp(_stateHeight, 8), 1);
        UnbindComputeViews();
    }

    private void StepRigid(
        ref GpuConstants constants,
        ID3D11ShaderResourceView cellularMetaSrv)
    {
        var rigidStateUav = _rigidStateUav
            ?? throw new InvalidOperationException("Rigid state UAV is not initialized.");
        var rigidMetaSrv = _rigidMetaSrv
            ?? throw new InvalidOperationException("Rigid metadata SRV is not initialized.");
        var rigidLambdaUav = _rigidLambdaUav
            ?? throw new InvalidOperationException("Rigid lambda UAV is not initialized.");

        constants.PhysicsPass = 0u;
        constants.PhysicsPhase = 0u;
        UpdateConstants(in constants);
        _context.CSSetShader(_rigidIntegrateShader);
        _context.CSSetConstantBuffer(0, _constantBuffer);
        _context.CSSetShaderResource(0, rigidMetaSrv);
        _context.CSSetShaderResource(1, cellularMetaSrv);
        if (constants.ExplosionStrength > 0.0f)
        {
            _context.CSSetShaderResource(2, _explosionPressureSrvs[_currentExplosionPressure]
                ?? throw new InvalidOperationException("Explosion pressure SRV is not initialized."));
        }
        _context.CSSetUnorderedAccessView(0, rigidStateUav);
        _context.CSSetUnorderedAccessView(1, rigidLambdaUav);
        _context.Dispatch(DivideRoundUp(_stateWidth, 8), DivideRoundUp(_stateHeight, 8), 1);
        UnbindComputeViews();

        _context.CSSetShader(_rigidSolveShader);
        // Dispatch boundaries provide the global ordering required between
        // shifted phases. Prepare each phase once and keep the shared views
        // bound across all iterations to avoid repeated maps and driver calls.
        for (uint phase = 0; phase < 4u; phase++)
        {
            constants.PhysicsPhase = phase;
            UpdateConstants(_rigidSolveConstantBuffers[phase], in constants);
        }
        _context.CSSetShaderResource(0, rigidMetaSrv);
        _context.CSSetUnorderedAccessView(0, rigidStateUav);
        _context.CSSetUnorderedAccessView(1, rigidLambdaUav);
        for (uint solverIteration = 0; solverIteration < constants.PhysicsSolverIterations; solverIteration++)
        {
            for (uint phase = 0; phase < 4u; phase++)
            {
                _context.CSSetConstantBuffer(0, _rigidSolveConstantBuffers[phase]);
                _context.Dispatch(
                    DivideRoundUp(_stateWidth / 2, 8),
                    DivideRoundUp(_stateHeight / 2, 8),
                    1);
            }
        }
        UnbindComputeViews();
        constants.PhysicsPhase = 0u;

        // The lattice is continuous during XPBD projection, then mapped back to
        // the cellular grid like FallingSandJava maps Body-local elements back
        // into its matrix. Atomic owner selection makes contested cells fully
        // deterministic without CPU readback or an O(N^2) broadphase.
        BuildRigidOccupancy(ref constants, resolveConflicts: true);
    }

    private void ResetExplosionPressure(ref GpuConstants constants)
    {
        if (_explosionPressureUavs[0] is null || _explosionPressureUavs[1] is null)
            return;

        constants.PhysicsPass = 0u;
        constants.PhysicsPhase = 0u;
        UpdateConstants(in constants);
        _context.CSSetShader(_explosionUpdateShader);
        _context.CSSetConstantBuffer(0, _constantBuffer);
        for (var index = 0; index < 2; index++)
        {
            var uav = _explosionPressureUavs[index]
                ?? throw new InvalidOperationException("Explosion pressure UAV is not initialized.");
            _context.CSSetUnorderedAccessView(1, uav);
            _context.Dispatch(DivideRoundUp(_stateWidth, 8), DivideRoundUp(_stateHeight, 8), 1);
            UnbindComputeViews();
        }
        _currentExplosionPressure = 0;
        _explosionPressureDirty = false;
        ResetManualExplosionWave();
    }

    private void ClearExplosionState(ref GpuConstants constants)
    {
        var metaUav = _stateMetaUavs[_currentState]
            ?? throw new InvalidOperationException("Current metadata UAV is not initialized.");
        var destination = 1 - _currentExplosionPressure;
        var destinationUav = _explosionPressureUavs[destination]
            ?? throw new InvalidOperationException("Explosion pressure UAV is not initialized.");

        // Consume any one-shot events created by the previous enabled iteration
        // while clearing the active pressure field. This runs only on the
        // enabled->disabled transition; subsequent zero-strength iterations do
        // not dispatch the explosion shader at all.
        constants.PhysicsPass = 2u;
        constants.PhysicsPhase = 0u;
        UpdateConstants(in constants);
        _context.CSSetShader(_explosionUpdateShader);
        _context.CSSetConstantBuffer(0, _constantBuffer);
        _context.CSSetUnorderedAccessView(0, metaUav);
        _context.CSSetUnorderedAccessView(1, destinationUav);
        _context.Dispatch(DivideRoundUp(_stateWidth, 8), DivideRoundUp(_stateHeight, 8), 1);
        UnbindComputeViews();
        _currentExplosionPressure = destination;
        _explosionPressureDirty = false;
    }

    private void UpdateExplosion(ref GpuConstants constants)
    {
        var metaUav = _stateMetaUavs[_currentState]
            ?? throw new InvalidOperationException("Current metadata UAV is not initialized.");
        var sourceSrv = _explosionPressureSrvs[_currentExplosionPressure]
            ?? throw new InvalidOperationException("Explosion pressure SRV is not initialized.");
        var destination = 1 - _currentExplosionPressure;
        var destinationUav = _explosionPressureUavs[destination]
            ?? throw new InvalidOperationException("Explosion pressure UAV is not initialized.");

        constants.PhysicsPass = 1u;
        constants.PhysicsPhase = 0u;
        UpdateConstants(in constants);
        _context.CSSetShader(_explosionUpdateShader);
        _context.CSSetConstantBuffer(0, _constantBuffer);
        _context.CSSetShaderResource(0, sourceSrv);
        if (constants.SolidPhysicsMode == 1u)
        {
            _context.CSSetShaderResource(1, _rigidOccupancySrv
                ?? throw new InvalidOperationException("Rigid occupancy SRV is not initialized."));
            _context.CSSetShaderResource(2, _rigidMetaSrv
                ?? throw new InvalidOperationException("Rigid metadata SRV is not initialized."));
        }
        _context.CSSetUnorderedAccessView(0, metaUav);
        _context.CSSetUnorderedAccessView(1, destinationUav);
        _context.Dispatch(DivideRoundUp(_stateWidth, 8), DivideRoundUp(_stateHeight, 8), 1);
        UnbindComputeViews();
        _currentExplosionPressure = destination;
        _explosionPressureDirty = true;
    }

    private void BuildLighting(ref GpuConstants constants, int radius)
    {
        if (constants.LightingStrength <= 0.0f)
            return;

        EnsureLightResources();
        if (constants.ExplosionStrength > 0.0f)
            EnsureExplosionResources();

        var cellularMetaSrv = _stateMetaSrvs[_currentState]
            ?? throw new InvalidOperationException("Current metadata SRV is not initialized.");
        var seedUav = _lightUavs[0]
            ?? throw new InvalidOperationException("Light field UAV is not initialized.");

        UpdateConstants(in constants);
        _context.CSSetShader(_lightSeedShader);
        _context.CSSetConstantBuffer(0, _constantBuffer);
        _context.CSSetShaderResource(0, cellularMetaSrv);
        if (constants.SolidPhysicsMode == 1u)
        {
            _context.CSSetShaderResource(1, _rigidOccupancySrv
                ?? throw new InvalidOperationException("Rigid occupancy SRV is not initialized."));
            _context.CSSetShaderResource(2, _rigidMetaSrv
                ?? throw new InvalidOperationException("Rigid metadata SRV is not initialized."));
        }
        if (constants.ExplosionStrength > 0.0f)
        {
            _context.CSSetShaderResource(3, _explosionPressureSrvs[_currentExplosionPressure]
                ?? throw new InvalidOperationException("Explosion pressure SRV is not initialized."));
        }
        _context.CSSetUnorderedAccessView(0, seedUav);
        _context.Dispatch(DivideRoundUp(_stateWidth, 8), DivideRoundUp(_stateHeight, 8), 1);
        UnbindComputeViews();
        _currentLight = 0;

        var passCount = Math.Clamp(radius, 1, SandSimulationSettings.MaximumLightingRadius);
        for (var pass = 0; pass < passCount; pass++)
        {
            var destination = 1 - _currentLight;
            var sourceLightSrv = _lightSrvs[_currentLight]
                ?? throw new InvalidOperationException("Light source SRV is not initialized.");
            var destinationLightUav = _lightUavs[destination]
                ?? throw new InvalidOperationException("Light destination UAV is not initialized.");

            _context.CSSetShader(_lightPropagateShader);
            _context.CSSetConstantBuffer(0, _constantBuffer);
            _context.CSSetShaderResource(0, sourceLightSrv);
            _context.CSSetUnorderedAccessView(0, destinationLightUav);
            _context.Dispatch(DivideRoundUp(_stateWidth, 8), DivideRoundUp(_stateHeight, 8), 1);
            UnbindComputeViews();
            _currentLight = destination;
        }
    }

    private void ReactRigid(
        ref GpuConstants constants,
        ID3D11ShaderResourceView previousCellularMetaSrv)
    {
        var rigidStateUav = _rigidStateUav
            ?? throw new InvalidOperationException("Rigid state UAV is not initialized.");
        var rigidColorUav = _rigidColorUav
            ?? throw new InvalidOperationException("Rigid color UAV is not initialized.");
        var rigidMetaUav = _rigidMetaUav
            ?? throw new InvalidOperationException("Rigid metadata UAV is not initialized.");
        var rigidLambdaUav = _rigidLambdaUav
            ?? throw new InvalidOperationException("Rigid lambda UAV is not initialized.");
        var rigidOccupancySrv = _rigidOccupancySrv
            ?? throw new InvalidOperationException("Rigid occupancy SRV is not initialized.");
        var cellularColorUav = _stateColorUavs[_currentState]
            ?? throw new InvalidOperationException("Current cellular color UAV is not initialized.");
        var cellularMetaUav = _stateMetaUavs[_currentState]
            ?? throw new InvalidOperationException("Current cellular metadata UAV is not initialized.");

        constants.PhysicsPass = 0u;
        constants.PhysicsPhase = 0u;
        UpdateConstants(in constants);

        _context.CSSetShader(_rigidReactShader);
        _context.CSSetConstantBuffer(0, _constantBuffer);
        _context.CSSetShaderResource(0, rigidOccupancySrv);
        _context.CSSetShaderResource(1, previousCellularMetaSrv);
        _context.CSSetUnorderedAccessView(0, rigidStateUav);
        _context.CSSetUnorderedAccessView(1, rigidColorUav);
        _context.CSSetUnorderedAccessView(2, rigidMetaUav);
        _context.CSSetUnorderedAccessView(3, rigidLambdaUav);
        _context.CSSetUnorderedAccessView(4, cellularColorUav);
        _context.CSSetUnorderedAccessView(5, cellularMetaUav);
        _context.Dispatch(DivideRoundUp(_stateWidth, 8), DivideRoundUp(_stateHeight, 8), 1);
        UnbindComputeViews();
    }

    private void BuildRigidOccupancy(
        ref GpuConstants constants,
        bool resolveConflicts,
        ID3D11ShaderResourceView? cellularMetaOverride = null)
    {
        var rigidStateSrv = _rigidStateSrv
            ?? throw new InvalidOperationException("Rigid state SRV is not initialized.");
        var rigidStateUav = _rigidStateUav
            ?? throw new InvalidOperationException("Rigid state UAV is not initialized.");
        var rigidMetaSrv = _rigidMetaSrv
            ?? throw new InvalidOperationException("Rigid metadata SRV is not initialized.");
        var rigidOccupancyUav = _rigidOccupancyUav
            ?? throw new InvalidOperationException("Rigid occupancy UAV is not initialized.");
        var cellularMetaSrv = cellularMetaOverride ?? _stateMetaSrvs[_currentState]
            ?? throw new InvalidOperationException("Current cellular metadata SRV is not initialized.");

        var rounds = resolveConflicts ? 2 : 0;
        for (var round = 0; round <= rounds; round++)
        {
            constants.PhysicsPass = 0u;
            UpdateConstants(in constants);
            _context.CSSetShader(_rigidGridShader);
            _context.CSSetConstantBuffer(0, _constantBuffer);
            _context.CSSetUnorderedAccessView(0, rigidOccupancyUav);
            _context.Dispatch(DivideRoundUp(_stateWidth, 8), DivideRoundUp(_stateHeight, 8), 1);
            UnbindComputeViews();

            constants.PhysicsPass = 1u;
            UpdateConstants(in constants);
            _context.CSSetShaderResource(0, rigidMetaSrv);
            _context.CSSetShaderResource(1, rigidStateSrv);
            _context.CSSetUnorderedAccessView(0, rigidOccupancyUav);
            _context.Dispatch(DivideRoundUp(_stateWidth, 8), DivideRoundUp(_stateHeight, 8), 1);
            UnbindComputeViews();

            if (round == rounds)
                break;

            constants.PhysicsPass = 2u;
            UpdateConstants(in constants);
            _context.CSSetShaderResource(0, rigidMetaSrv);
            _context.CSSetShaderResource(2, cellularMetaSrv);
            _context.CSSetUnorderedAccessView(0, rigidOccupancyUav);
            _context.CSSetUnorderedAccessView(1, rigidStateUav);
            _context.Dispatch(DivideRoundUp(_stateWidth, 8), DivideRoundUp(_stateHeight, 8), 1);
            UnbindComputeViews();
        }
    }

    private void CreateFrameResources(
        int sourceWidth,
        int sourceHeight,
        int stateWidth,
        int stateHeight,
        int logicalStateWidth,
        int logicalStateHeight)
    {
        ID3D11Texture2D? sourceTexture = null;
        ID3D11ShaderResourceView? sourceSrv = null;
        ID2D1Bitmap1? sourceBitmap = null;
        ID3D11Texture2D? outputTexture = null;
        ID3D11RenderTargetView? outputRtv = null;
        ID2D1Bitmap1? outputBitmap = null;

        ID3D11Texture2D? color0 = null;
        ID3D11Texture2D? color1 = null;
        ID3D11ShaderResourceView? colorSrv0 = null;
        ID3D11ShaderResourceView? colorSrv1 = null;
        ID3D11UnorderedAccessView? colorUav0 = null;
        ID3D11UnorderedAccessView? colorUav1 = null;
        ID3D11Texture2D? meta0 = null;
        ID3D11Texture2D? meta1 = null;
        ID3D11ShaderResourceView? metaSrv0 = null;
        ID3D11ShaderResourceView? metaSrv1 = null;
        ID3D11UnorderedAccessView? metaUav0 = null;
        ID3D11UnorderedAccessView? metaUav1 = null;

        try
        {
            sourceTexture = _device.CreateTexture2D(
                Format.B8G8R8A8_UNorm,
                sourceWidth,
                sourceHeight,
                mipLevels: 1,
                bindFlags: BindFlags.RenderTarget | BindFlags.ShaderResource);
            sourceSrv = _device.CreateShaderResourceView(sourceTexture);
            using (var sourceSurface = sourceTexture.QueryInterface<IDXGISurface>())
            {
                sourceBitmap = _renderContext.CreateBitmapFromDxgiSurface(
                    sourceSurface,
                    new BitmapProperties1(
                        new PixelFormat(Format.B8G8R8A8_UNorm, Vortice.DCommon.AlphaMode.Premultiplied),
                        96f,
                        96f,
                        BitmapOptions.Target));
            }

            outputTexture = _device.CreateTexture2D(
                Format.B8G8R8A8_UNorm,
                sourceWidth,
                sourceHeight,
                mipLevels: 1,
                bindFlags: BindFlags.RenderTarget | BindFlags.ShaderResource);
            outputRtv = _device.CreateRenderTargetView(outputTexture);
            using (var outputSurface = outputTexture.QueryInterface<IDXGISurface>())
            {
                outputBitmap = _renderContext.CreateBitmapFromDxgiSurface(
                    outputSurface,
                    new BitmapProperties1(
                        new PixelFormat(Format.B8G8R8A8_UNorm, Vortice.DCommon.AlphaMode.Premultiplied),
                        96f,
                        96f,
                        BitmapOptions.None));
            }

            color0 = CreateStateTexture(stateWidth, stateHeight);
            color1 = CreateStateTexture(stateWidth, stateHeight);
            colorSrv0 = _device.CreateShaderResourceView(color0);
            colorSrv1 = _device.CreateShaderResourceView(color1);
            colorUav0 = _device.CreateUnorderedAccessView(color0);
            colorUav1 = _device.CreateUnorderedAccessView(color1);

            meta0 = CreateStateTexture(stateWidth, stateHeight);
            meta1 = CreateStateTexture(stateWidth, stateHeight);
            metaSrv0 = _device.CreateShaderResourceView(meta0);
            metaSrv1 = _device.CreateShaderResourceView(meta1);
            metaUav0 = _device.CreateUnorderedAccessView(meta0);
            metaUav1 = _device.CreateUnorderedAccessView(meta1);

            _sourceTexture = sourceTexture;
            _sourceSrv = sourceSrv;
            _sourceBitmap = sourceBitmap;
            _outputTexture = outputTexture;
            _outputRtv = outputRtv;
            _outputBitmap = outputBitmap;

            _stateColorTextures[0] = color0;
            _stateColorTextures[1] = color1;
            _stateColorSrvs[0] = colorSrv0;
            _stateColorSrvs[1] = colorSrv1;
            _stateColorUavs[0] = colorUav0;
            _stateColorUavs[1] = colorUav1;
            _stateMetaTextures[0] = meta0;
            _stateMetaTextures[1] = meta1;
            _stateMetaSrvs[0] = metaSrv0;
            _stateMetaSrvs[1] = metaSrv1;
            _stateMetaUavs[0] = metaUav0;
            _stateMetaUavs[1] = metaUav1;

            _sourceWidth = sourceWidth;
            _sourceHeight = sourceHeight;
            _stateWidth = stateWidth;
            _stateHeight = stateHeight;
            _logicalStateWidth = logicalStateWidth;
            _logicalStateHeight = logicalStateHeight;

            sourceTexture = null;
            sourceSrv = null;
            sourceBitmap = null;
            outputTexture = null;
            outputRtv = null;
            outputBitmap = null;
            color0 = null;
            color1 = null;
            colorSrv0 = null;
            colorSrv1 = null;
            colorUav0 = null;
            colorUav1 = null;
            meta0 = null;
            meta1 = null;
            metaSrv0 = null;
            metaSrv1 = null;
            metaUav0 = null;
            metaUav1 = null;
        }
        finally
        {
            metaUav1?.Dispose();
            metaUav0?.Dispose();
            metaSrv1?.Dispose();
            metaSrv0?.Dispose();
            meta1?.Dispose();
            meta0?.Dispose();
            colorUav1?.Dispose();
            colorUav0?.Dispose();
            colorSrv1?.Dispose();
            colorSrv0?.Dispose();
            color1?.Dispose();
            color0?.Dispose();
            outputBitmap?.Dispose();
            outputRtv?.Dispose();
            outputTexture?.Dispose();
            sourceBitmap?.Dispose();
            sourceSrv?.Dispose();
            sourceTexture?.Dispose();
        }
    }

    private ID3D11Texture2D CreateStateTexture(int width, int height)
        => _device.CreateTexture2D(
            Format.R32_UInt,
            width,
            height,
            mipLevels: 1,
            bindFlags: BindFlags.ShaderResource | BindFlags.UnorderedAccess);

    private ID3D11Texture2D CreatePhysicsTexture(Format format, int width, int height)
        => _device.CreateTexture2D(
            format,
            width,
            height,
            mipLevels: 1,
            bindFlags: BindFlags.ShaderResource | BindFlags.UnorderedAccess);

    private void EnsureRigidResources()
    {
        if (_rigidStateSrv is not null && _rigidStateUav is not null &&
            _rigidColorSrv is not null && _rigidColorUav is not null &&
            _rigidMetaSrv is not null && _rigidMetaUav is not null &&
            _rigidLambdaUav is not null &&
            _rigidOccupancySrv is not null && _rigidOccupancyUav is not null)
        {
            return;
        }

        ReleaseRigidResources();

        ID3D11Texture2D? rigidState = null;
        ID3D11ShaderResourceView? rigidStateSrv = null;
        ID3D11UnorderedAccessView? rigidStateUav = null;
        ID3D11Texture2D? rigidColor = null;
        ID3D11ShaderResourceView? rigidColorSrv = null;
        ID3D11UnorderedAccessView? rigidColorUav = null;
        ID3D11Texture2D? rigidMeta = null;
        ID3D11ShaderResourceView? rigidMetaSrv = null;
        ID3D11UnorderedAccessView? rigidMetaUav = null;
        ID3D11Texture2D? rigidLambda = null;
        ID3D11UnorderedAccessView? rigidLambdaUav = null;
        ID3D11Texture2D? rigidOccupancy = null;
        ID3D11ShaderResourceView? rigidOccupancySrv = null;
        ID3D11UnorderedAccessView? rigidOccupancyUav = null;

        try
        {
            rigidState = CreatePhysicsTexture(Format.R32G32B32A32_Float, _stateWidth, _stateHeight);
            rigidStateSrv = _device.CreateShaderResourceView(rigidState);
            rigidStateUav = _device.CreateUnorderedAccessView(rigidState);
            rigidColor = CreatePhysicsTexture(Format.R32_UInt, _stateWidth, _stateHeight);
            rigidColorSrv = _device.CreateShaderResourceView(rigidColor);
            rigidColorUav = _device.CreateUnorderedAccessView(rigidColor);
            rigidMeta = CreatePhysicsTexture(Format.R32_UInt, _stateWidth, _stateHeight);
            rigidMetaSrv = _device.CreateShaderResourceView(rigidMeta);
            rigidMetaUav = _device.CreateUnorderedAccessView(rigidMeta);
            rigidLambda = CreatePhysicsTexture(Format.R32G32B32A32_Float, _stateWidth, _stateHeight);
            rigidLambdaUav = _device.CreateUnorderedAccessView(rigidLambda);
            rigidOccupancy = CreatePhysicsTexture(Format.R32_UInt, _stateWidth, _stateHeight);
            rigidOccupancySrv = _device.CreateShaderResourceView(rigidOccupancy);
            rigidOccupancyUav = _device.CreateUnorderedAccessView(rigidOccupancy);

            _rigidStateTexture = rigidState;
            _rigidStateSrv = rigidStateSrv;
            _rigidStateUav = rigidStateUav;
            _rigidColorTexture = rigidColor;
            _rigidColorSrv = rigidColorSrv;
            _rigidColorUav = rigidColorUav;
            _rigidMetaTexture = rigidMeta;
            _rigidMetaSrv = rigidMetaSrv;
            _rigidMetaUav = rigidMetaUav;
            _rigidLambdaTexture = rigidLambda;
            _rigidLambdaUav = rigidLambdaUav;
            _rigidOccupancyTexture = rigidOccupancy;
            _rigidOccupancySrv = rigidOccupancySrv;
            _rigidOccupancyUav = rigidOccupancyUav;

        }
        catch
        {
            rigidOccupancyUav?.Dispose();
            rigidOccupancySrv?.Dispose();
            rigidOccupancy?.Dispose();
            rigidLambdaUav?.Dispose();
            rigidLambda?.Dispose();
            rigidMetaUav?.Dispose();
            rigidMetaSrv?.Dispose();
            rigidMeta?.Dispose();
            rigidColorUav?.Dispose();
            rigidColorSrv?.Dispose();
            rigidColor?.Dispose();
            rigidStateUav?.Dispose();
            rigidStateSrv?.Dispose();
            rigidState?.Dispose();
            throw;
        }
    }

    private bool EnsureExplosionResources()
    {
        if (_explosionPressureSrvs[0] is not null && _explosionPressureSrvs[1] is not null &&
            _explosionPressureUavs[0] is not null && _explosionPressureUavs[1] is not null)
        {
            return false;
        }

        ReleaseExplosionResources();
        ID3D11Texture2D? texture0 = null;
        ID3D11Texture2D? texture1 = null;
        ID3D11ShaderResourceView? srv0 = null;
        ID3D11ShaderResourceView? srv1 = null;
        ID3D11UnorderedAccessView? uav0 = null;
        ID3D11UnorderedAccessView? uav1 = null;

        try
        {
            texture0 = CreatePhysicsTexture(Format.R32_Float, _stateWidth, _stateHeight);
            texture1 = CreatePhysicsTexture(Format.R32_Float, _stateWidth, _stateHeight);
            srv0 = _device.CreateShaderResourceView(texture0);
            srv1 = _device.CreateShaderResourceView(texture1);
            uav0 = _device.CreateUnorderedAccessView(texture0);
            uav1 = _device.CreateUnorderedAccessView(texture1);

            _explosionPressureTextures[0] = texture0;
            _explosionPressureTextures[1] = texture1;
            _explosionPressureSrvs[0] = srv0;
            _explosionPressureSrvs[1] = srv1;
            _explosionPressureUavs[0] = uav0;
            _explosionPressureUavs[1] = uav1;
            _currentExplosionPressure = 0;
            _explosionPressureDirty = false;

            texture0 = null;
            texture1 = null;
            srv0 = null;
            srv1 = null;
            uav0 = null;
            uav1 = null;
            return true;
        }
        finally
        {
            uav1?.Dispose();
            uav0?.Dispose();
            srv1?.Dispose();
            srv0?.Dispose();
            texture1?.Dispose();
            texture0?.Dispose();
        }
    }

    private void EnsureLightResources()
    {
        if (_lightSrvs[0] is not null && _lightSrvs[1] is not null &&
            _lightUavs[0] is not null && _lightUavs[1] is not null)
        {
            return;
        }

        ReleaseLightResources();
        ID3D11Texture2D? texture0 = null;
        ID3D11Texture2D? texture1 = null;
        ID3D11ShaderResourceView? srv0 = null;
        ID3D11ShaderResourceView? srv1 = null;
        ID3D11UnorderedAccessView? uav0 = null;
        ID3D11UnorderedAccessView? uav1 = null;

        try
        {
            texture0 = CreatePhysicsTexture(Format.R32_UInt, _stateWidth, _stateHeight);
            texture1 = CreatePhysicsTexture(Format.R32_UInt, _stateWidth, _stateHeight);
            srv0 = _device.CreateShaderResourceView(texture0);
            srv1 = _device.CreateShaderResourceView(texture1);
            uav0 = _device.CreateUnorderedAccessView(texture0);
            uav1 = _device.CreateUnorderedAccessView(texture1);

            _lightTextures[0] = texture0;
            _lightTextures[1] = texture1;
            _lightSrvs[0] = srv0;
            _lightSrvs[1] = srv1;
            _lightUavs[0] = uav0;
            _lightUavs[1] = uav1;
            _currentLight = 0;

            texture0 = null;
            texture1 = null;
            srv0 = null;
            srv1 = null;
            uav0 = null;
            uav1 = null;
        }
        finally
        {
            uav1?.Dispose();
            uav0?.Dispose();
            srv1?.Dispose();
            srv0?.Dispose();
            texture1?.Dispose();
            texture0?.Dispose();
        }
    }

    private void ReleaseRigidResources()
    {
        _rigidOccupancyUav?.Dispose();
        _rigidOccupancySrv?.Dispose();
        _rigidOccupancyTexture?.Dispose();
        _rigidOccupancyUav = null;
        _rigidOccupancySrv = null;
        _rigidOccupancyTexture = null;

        _rigidLambdaUav?.Dispose();
        _rigidLambdaTexture?.Dispose();
        _rigidLambdaUav = null;
        _rigidLambdaTexture = null;

        _rigidMetaUav?.Dispose();
        _rigidMetaSrv?.Dispose();
        _rigidMetaTexture?.Dispose();
        _rigidMetaUav = null;
        _rigidMetaSrv = null;
        _rigidMetaTexture = null;

        _rigidColorUav?.Dispose();
        _rigidColorSrv?.Dispose();
        _rigidColorTexture?.Dispose();
        _rigidColorUav = null;
        _rigidColorSrv = null;
        _rigidColorTexture = null;

        _rigidStateUav?.Dispose();
        _rigidStateSrv?.Dispose();
        _rigidStateTexture?.Dispose();
        _rigidStateUav = null;
        _rigidStateSrv = null;
        _rigidStateTexture = null;
    }

    private void ReleaseExplosionResources()
    {
        DisposeStateResources(_explosionPressureUavs, _explosionPressureSrvs, _explosionPressureTextures);
        _currentExplosionPressure = 0;
        _explosionPressureDirty = false;
        ResetManualExplosionWave();
    }

    private void ReleaseLightResources()
    {
        DisposeStateResources(_lightUavs, _lightSrvs, _lightTextures);
        _currentLight = 0;
    }

    private void ReleaseFrameResources()
    {
        _renderContext.Target = null;

        ReleaseLightResources();
        ReleaseExplosionResources();
        ReleaseRigidResources();
        DisposeStateResources(_stateMetaUavs, _stateMetaSrvs, _stateMetaTextures);
        DisposeStateResources(_stateColorUavs, _stateColorSrvs, _stateColorTextures);

        _outputBitmap?.Dispose();
        _outputRtv?.Dispose();
        _outputTexture?.Dispose();
        _outputBitmap = null;
        _outputRtv = null;
        _outputTexture = null;

        _sourceBitmap?.Dispose();
        _sourceSrv?.Dispose();
        _sourceTexture?.Dispose();
        _sourceBitmap = null;
        _sourceSrv = null;
        _sourceTexture = null;

        _sourceWidth = 0;
        _sourceHeight = 0;
        _stateWidth = 0;
        _stateHeight = 0;
        _logicalStateWidth = 0;
        _logicalStateHeight = 0;
    }

    private static void DisposeStateResources(
        ID3D11UnorderedAccessView?[] uavs,
        ID3D11ShaderResourceView?[] srvs,
        ID3D11Texture2D?[] textures)
    {
        uavs[1]?.Dispose();
        uavs[0]?.Dispose();
        srvs[1]?.Dispose();
        srvs[0]?.Dispose();
        textures[1]?.Dispose();
        textures[0]?.Dispose();
        uavs[0] = null;
        uavs[1] = null;
        srvs[0] = null;
        srvs[1] = null;
        textures[0] = null;
        textures[1] = null;
    }

    private ID3DDeviceContextState? EnterIsolatedContext()
    {
        _multithread.Enter();
        try
        {
            return _context.SwapDeviceContextState(_isolatedContextState);
        }
        catch
        {
            _multithread.Leave();
            throw;
        }
    }

    private void LeaveIsolatedContext(ID3DDeviceContextState? previousContextState)
    {
        try
        {
            using var activePluginState = _context.SwapDeviceContextState(previousContextState!);
        }
        finally
        {
            previousContextState?.Dispose();
            _multithread.Leave();
        }
    }

    private void UnbindCompute()
    {
        _context.CSSetShaderResources(0, 8, NullShaderResourceViews);
        _context.CSSetUnorderedAccessViews(0, 8, NullUnorderedAccessViews);
        _context.CSSetConstantBuffers(0, 1, NullConstantBuffers);
        _context.CSSetShader(null);
    }

    private void UnbindComputeViews()
    {
        _context.CSSetShaderResources(0, 8, NullShaderResourceViews);
        _context.CSSetUnorderedAccessViews(0, 8, NullUnorderedAccessViews);
    }

    private void UpdateConstants(in GpuConstants constants)
        => UpdateConstants(_constantBuffer, in constants);

    private void UpdateConstants(ID3D11Buffer buffer, in GpuConstants constants)
    {
        var mapped = _context.Map(buffer, MapMode.WriteDiscard);
        unsafe
        {
            Unsafe.WriteUnaligned(mapped.DataPointer.ToPointer(), constants);
        }
        _context.Unmap(buffer);
    }

    private void StartManualExplosionWave(in GpuConstants constants)
    {
        _manualExplosionWaveActive = true;
        _manualExplosionWaveVisible = false;
        _manualExplosionWaveNextStep = 0u;
        _manualExplosionWaveRenderedStep = 0u;
        _manualExplosionCellX = constants.ManualExplosionCellX;
        _manualExplosionCellY = constants.ManualExplosionCellY;
    }

    private void PrepareManualExplosionWaveForStep(ref GpuConstants constants)
    {
        constants.ManualExplosionWaveStep = uint.MaxValue;
        if (!_manualExplosionWaveActive)
            return;

        // Keep suppressing the square residual pressure for four iterations after
        // the visible radial front reaches the configured radius. The pressure
        // field has decayed below its 0.001 cutoff by then at the supported radii.
        var visibleRadius = Math.Max((uint)MathF.Ceiling(constants.ExplosionRadius), 1u);
        var activeStepLimit = visibleRadius + 4u;
        if (_manualExplosionWaveNextStep >= activeStepLimit)
        {
            _manualExplosionWaveActive = false;
            return;
        }

        constants.ManualExplosionCellX = _manualExplosionCellX;
        constants.ManualExplosionCellY = _manualExplosionCellY;
        constants.ManualExplosionWaveStep = _manualExplosionWaveNextStep;
    }

    private void PrepareManualExplosionWaveForRender(ref GpuConstants constants)
    {
        constants.ManualExplosionWaveStep = uint.MaxValue;
        if (!_manualExplosionWaveVisible)
            return;

        constants.ManualExplosionCellX = _manualExplosionCellX;
        constants.ManualExplosionCellY = _manualExplosionCellY;
        constants.ManualExplosionWaveStep = _manualExplosionWaveRenderedStep;
    }

    private void ResetManualExplosionWave()
    {
        _manualExplosionWaveActive = false;
        _manualExplosionWaveVisible = false;
        _manualExplosionWaveNextStep = 0u;
        _manualExplosionWaveRenderedStep = 0u;
        _manualExplosionCellX = 0u;
        _manualExplosionCellY = 0u;
    }

    private GpuConstants CreateConstants(in FrameParameters parameters)
    {
        var manualExplosionCellX = ResolveExplosionCell(parameters.ManualExplosionX, _sourceWidth, _logicalStateWidth, parameters.ParticleSize);
        var manualExplosionCellY = ResolveExplosionCell(parameters.ManualExplosionY, _sourceHeight, _logicalStateHeight, parameters.ParticleSize);
        return new GpuConstants
        {
            SourceWidth = (uint)_sourceWidth,
            SourceHeight = (uint)_sourceHeight,
            StateWidth = (uint)_stateWidth,
            StateHeight = (uint)_stateHeight,
            ParticleSize = (uint)parameters.ParticleSize,
            FrameIndex = unchecked((uint)parameters.FrameIndex),
            StepIndex = _globalStep,
            Seed = parameters.Seed,
            AlphaThreshold = parameters.AlphaThreshold,
            LuminanceThreshold = parameters.LuminanceThreshold,
            Spread = parameters.Spread,
            ReactionStrength = parameters.ReactionStrength,
            MaskMode = (uint)parameters.MaskMode,
            InitializeMode = 0u,
            LogicalStateWidth = (uint)_logicalStateWidth,
            LogicalStateHeight = (uint)_logicalStateHeight,
            MaterialAssignment = (uint)parameters.MaterialAssignment,
            SingleMaterial = (uint)parameters.SingleMaterial,
            ColorMode = (uint)parameters.ColorMode,
            PhysicsBreakStrength = parameters.SolidBreakStrength,
            FireLifetimeSteps = 48u,
            EmberLifetimeSteps = 120u,
            SmokeLifetimeSteps = 2400u,
            SteamLifetimeSteps = 2400u,
            SolidPhysicsMode = (uint)parameters.SolidPhysicsMode,
            PhysicsPass = 0u,
            PhysicsPhase = 0u,
            PhysicsSolverIterations = (uint)parameters.SolidSolverIterations,
            PhysicsDeltaTime = 1.0f / 120.0f,
            PhysicsGravity = 120.0f * parameters.SolidGravity,
            PhysicsCompliance = 0.000001f / Math.Max(parameters.SolidStiffness, 0.25f),
            PhysicsDamping = 0.998f,
            ExplosionStrength = parameters.ExplosionStrength,
            ExplosionRadius = parameters.ExplosionRadius,
            ExplosionDecay = 0.58f,
            ExplosionFalloff = 1.0f / Math.Max(parameters.ExplosionRadius, 1),
            ManualExplosionCellX = manualExplosionCellX,
            ManualExplosionCellY = manualExplosionCellY,
            ManualExplosionEnabled = parameters.ManualExplosion ? 1u : 0u,
            ManualExplosionWaveStep = uint.MaxValue,
            LightingStrength = parameters.LightingStrength,
            LightingRadius = parameters.LightingRadius,
            AmbientLight = parameters.AmbientLight,
            ShadowStrength = parameters.ShadowStrength,
        };
    }

    private static uint ResolveExplosionCell(float offsetPixels, int sourceSize, int logicalStateSize, int particleSize)
    {
        if (logicalStateSize <= 1)
            return 0u;

        var sourceCoordinate = sourceSize * 0.5f + offsetPixels;
        var cell = (int)MathF.Floor(sourceCoordinate / Math.Max(particleSize, 1));
        return (uint)Math.Clamp(cell, 0, logicalStateSize - 1);
    }

    private void EnsureReady()
    {
        if (_sourceSrv is null || _outputBitmap is null ||
            _stateColorSrvs[0] is null || _stateColorSrvs[1] is null ||
            _stateColorUavs[0] is null || _stateColorUavs[1] is null ||
            _stateMetaSrvs[0] is null || _stateMetaSrvs[1] is null ||
            _stateMetaUavs[0] is null || _stateMetaUavs[1] is null)
        {
            throw new InvalidOperationException("Core GPU resources are not initialized.");
        }
    }

    private void ThrowIfDisposed()
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
    }

    private static int DivideRoundUp(int value, int divisor)
        => checked((value + divisor - 1) / divisor);

    private static int RoundUpEven(int value)
        => (value + 1) & ~1;

    public void Dispose()
    {
        if (_disposed)
            return;

        _disposed = true;
        ReleaseFrameResources();
        foreach (var buffer in _rigidSolveConstantBuffers)
            buffer.Dispose();
        _constantBuffer.Dispose();
        _renderPixelShader.Dispose();
        _fullscreenVertexShader.Dispose();
        _lightPropagateShader.Dispose();
        _lightSeedShader.Dispose();
        _explosionUpdateShader.Dispose();
        _rigidReactShader.Dispose();
        _rigidGridShader.Dispose();
        _rigidSolveShader.Dispose();
        _rigidIntegrateShader.Dispose();
        _rigidInitializeShader.Dispose();
        _stepShader.Dispose();
        _initializeShader.Dispose();
        _renderContext.Dispose();
        _isolatedContextState.Dispose();
        _multithread.Dispose();
        _context.Dispose();
        _device.Dispose();
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct GpuConstants
    {
        public uint SourceWidth;
        public uint SourceHeight;
        public uint StateWidth;
        public uint StateHeight;

        public uint ParticleSize;
        public uint FrameIndex;
        public uint StepIndex;
        public uint Seed;

        public float AlphaThreshold;
        public float LuminanceThreshold;
        public float Spread;
        public float ReactionStrength;

        public uint MaskMode;
        public uint InitializeMode;
        public uint LogicalStateWidth;
        public uint LogicalStateHeight;

        public uint MaterialAssignment;
        public uint SingleMaterial;
        public uint ColorMode;
        public float PhysicsBreakStrength;

        public uint FireLifetimeSteps;
        public uint EmberLifetimeSteps;
        public uint SmokeLifetimeSteps;
        public uint SteamLifetimeSteps;

        public uint SolidPhysicsMode;
        public uint PhysicsPass;
        public uint PhysicsPhase;
        public uint PhysicsSolverIterations;

        public float PhysicsDeltaTime;
        public float PhysicsGravity;
        public float PhysicsCompliance;
        public float PhysicsDamping;

        public float ExplosionStrength;
        public float ExplosionRadius;
        public float ExplosionDecay;
        public float ExplosionFalloff;

        public uint ManualExplosionCellX;
        public uint ManualExplosionCellY;
        public uint ManualExplosionEnabled;
        public uint ManualExplosionWaveStep;

        public float LightingStrength;
        public float LightingRadius;
        public float AmbientLight;
        public float ShadowStrength;

    }

    internal readonly record struct FrameParameters(
        long FrameIndex,
        int ParticleSize,
        SandMaskMode MaskMode,
        float AlphaThreshold,
        float LuminanceThreshold,
        float Spread,
        float ReactionStrength,
        SandSolidPhysicsMode SolidPhysicsMode,
        float SolidGravity,
        float SolidStiffness,
        float SolidBreakStrength,
        int SolidSolverIterations,
        bool ManualExplosion,
        float ManualExplosionX,
        float ManualExplosionY,
        float ExplosionStrength,
        int ExplosionRadius,
        float LightingStrength,
        int LightingRadius,
        float AmbientLight,
        float ShadowStrength,
        SandMaterialAssignment MaterialAssignment,
        SandMaterial SingleMaterial,
        SandColorMode ColorMode,
        uint Seed);
}
