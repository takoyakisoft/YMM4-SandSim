[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Position = 0)]
    [ValidateSet("build", "test", "fmt", "format", "lint", "check", "clean", "publish", "shaders")]
    [string]$Task = "build",

    [switch]$Verify
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$propsPath = Join-Path $root "Directory.Build.props"

function Get-BuildProperty {
    param([Parameter(Mandatory = $true)][string]$Name)

    if (-not (Test-Path -LiteralPath $propsPath -PathType Leaf)) {
        throw "Directory.Build.props was not found: $propsPath"
    }

    [xml]$props = Get-Content -LiteralPath $propsPath -Raw
    $node = @($props.SelectNodes("/Project/PropertyGroup/$Name")) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_.InnerText) } |
        Select-Object -First 1
    if ($null -eq $node) {
        throw "$Name is not configured in Directory.Build.props."
    }

    return $node.InnerText.Trim()
}

function Get-RequiredFileProperty {
    param([Parameter(Mandatory = $true)][string]$Name)

    $path = [IO.Path]::GetFullPath((Get-BuildProperty $Name))
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "$Name was not found: $path"
    }

    return $path
}

function Invoke-CommandChecked {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Command
    )

    Write-Host "==> $Name" -ForegroundColor Cyan
    $global:LASTEXITCODE = 0
    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$Name failed with exit code $LASTEXITCODE."
    }
}

function Invoke-ShaderBuild {
    $fxc = Get-RequiredFileProperty "FxcPath"
    $shaderDirectory = Join-Path $root "YMM4SandSim\Shaders"
    $shaderJobs = @(
        @{ Source = "SandInitialize.hlsl"; Profile = "cs_5_0" },
        @{ Source = "SandStep.hlsl"; Profile = "cs_5_0" },
        @{ Source = "SandRigidInitialize.hlsl"; Profile = "cs_5_0" },
        @{ Source = "SandRigidIntegrate.hlsl"; Profile = "cs_5_0" },
        @{ Source = "SandRigidSolve.hlsl"; Profile = "cs_5_0" },
        @{ Source = "SandRigidGrid.hlsl"; Profile = "cs_5_0" },
        @{ Source = "SandRigidComponents.hlsl"; Profile = "cs_5_0" },
        @{ Source = "SandRigidReact.hlsl"; Profile = "cs_5_0" },
        @{ Source = "SandExplosionUpdate.hlsl"; Profile = "cs_5_0" },
        @{ Source = "SandLightSeed.hlsl"; Profile = "cs_5_0" },
        @{ Source = "SandLightPropagate.hlsl"; Profile = "cs_5_0" },
        @{ Source = "SandFullscreenVS.hlsl"; Profile = "vs_5_0" },
        @{ Source = "SandRenderPS.hlsl"; Profile = "ps_5_0" }
    )

    foreach ($shader in $shaderJobs) {
        $source = Join-Path $shaderDirectory $shader.Source
        $output = [IO.Path]::ChangeExtension($source, ".cso")
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "Shader source was not found: $source"
        }

        Remove-Item -LiteralPath $output -Force -ErrorAction SilentlyContinue
        Write-Host "Compiling $($shader.Source) [$($shader.Profile)]"
        $global:LASTEXITCODE = 0
        & $fxc /nologo /WX /O3 /T $shader.Profile /E main /I $shaderDirectory /Fo $output $source
        if ($LASTEXITCODE -ne 0) {
            throw "FXC failed for $($shader.Source) with exit code $LASTEXITCODE."
        }
        if (-not (Test-Path -LiteralPath $output -PathType Leaf)) {
            throw "FXC reported success but output is missing: $output"
        }
    }
}

function Invoke-PluginBuild {
    param([switch]$Deploy)

    $dotnet = Get-RequiredFileProperty "DotnetPath"
    $ymm4Dir = [IO.Path]::GetFullPath((Get-BuildProperty "YMM4DirPath"))
    $fxc = Get-RequiredFileProperty "FxcPath"
    if (-not (Test-Path -LiteralPath $ymm4Dir -PathType Container)) {
        throw "YMM4DirPath was not found: $ymm4Dir"
    }

    $pluginProject = Join-Path $root "YMM4SandSim\YMM4SandSim.csproj"
    $skipDeploy = if ($Deploy) { "false" } else { "true" }
    Invoke-CommandChecked "Build plugin and shaders" {
        & $dotnet build $pluginProject -c Release -p:Platform=x64 `
            "-p:YMM4DirPath=$ymm4Dir" "-p:FxcPath=$fxc" `
            "-p:SkipPluginDeploy=$skipDeploy"
    }
}

function Invoke-DotnetFormat {
    param(
        [string]$Subcommand,
        [switch]$VerifyNoChanges
    )

    $dotnet = Get-RequiredFileProperty "DotnetPath"
    foreach ($project in @(
        (Join-Path $root "YMM4SandSim\YMM4SandSim.csproj"),
        (Join-Path $root "YMM4SandSim.Tests\YMM4SandSim.Tests.csproj")
    )) {
        $arguments = @("format")
        if (-not [string]::IsNullOrWhiteSpace($Subcommand)) {
            $arguments += $Subcommand
        }
        $arguments += @($project, "--verbosity", "minimal")
        if ($VerifyNoChanges) {
            $arguments += "--verify-no-changes"
        }
        Invoke-CommandChecked "dotnet format $Subcommand $([IO.Path]::GetFileName($project))" {
            & $dotnet @arguments
        }
    }
}

function Invoke-Tests {
    $python = Get-RequiredFileProperty "PythonPath"
    Invoke-CommandChecked "Run static contract tests" {
        & $python (Join-Path $root "YMM4SandSim.Tests\StaticContractTests.py")
    }

    $dotnet = Get-RequiredFileProperty "DotnetPath"
    $testProject = Join-Path $root "YMM4SandSim.Tests\YMM4SandSim.Tests.csproj"
    Invoke-CommandChecked "Run xUnit tests" {
        & $dotnet test $testProject -c Release -p:Platform=x64 -p:SkipPluginDeploy=true
    }
}

function Invoke-Format {
    Invoke-DotnetFormat -VerifyNoChanges:$Verify
}

function Invoke-Lint {
    Invoke-DotnetFormat "style" -VerifyNoChanges
    Invoke-DotnetFormat "analyzers" -VerifyNoChanges
    $dotnet = Get-RequiredFileProperty "DotnetPath"
    Invoke-CommandChecked "Build with warnings treated as errors" {
        & $dotnet build (Join-Path $root "YMM4SandSim\YMM4SandSim.csproj") `
            -c Release -p:Platform=x64 -p:SkipPluginDeploy=true -p:TreatWarningsAsErrors=true
    }
}

function Remove-BuildOutputs {
    $outputPaths = @(
        "artifacts",
        "YMM4SandSim\bin",
        "YMM4SandSim\obj",
        "YMM4SandSim.Tests\bin",
        "YMM4SandSim.Tests\obj",
        "YukkuriMovieMaker.Generator\YukkuriMovieMaker.Generator\bin",
        "YukkuriMovieMaker.Generator\YukkuriMovieMaker.Generator\obj"
    )

    $rootPrefix = [IO.Path]::GetFullPath($root).TrimEnd('\') + '\'
    foreach ($relativePath in $outputPaths) {
        $path = [IO.Path]::GetFullPath((Join-Path $root $relativePath))
        if (-not $path.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to clean a path outside the repository: $path"
        }
        if (Test-Path -LiteralPath $path) {
            Write-Host "Removing $relativePath"
            Remove-Item -LiteralPath $path -Recurse -Force
        }
    }

    Get-ChildItem -LiteralPath (Join-Path $root "YMM4SandSim\Shaders") -Filter "*.cso" -File |
        ForEach-Object {
            Write-Host "Removing YMM4SandSim\Shaders\$($_.Name)"
            Remove-Item -LiteralPath $_.FullName -Force
        }
}

function New-ReleasePackage {
    [xml]$targets = Get-Content -LiteralPath (Join-Path $root "Directory.Build.targets") -Raw
    $version = $targets.SelectSingleNode("/Project/PropertyGroup/YMM4SandSimVersion").InnerText.Trim()
    if ([string]::IsNullOrWhiteSpace($version)) {
        throw "YMM4SandSimVersion could not be read from Directory.Build.targets."
    }

    $buildDirectory = Join-Path $root "YMM4SandSim\bin\x64\Release\net10.0-windows10.0.19041.0"
    $pluginDll = Join-Path $buildDirectory "YMM4SandSim.dll"
    $readmePath = Join-Path $root "packaging\Readme.txt"
    $licensePath = Join-Path $root "LICENSE.txt"
    foreach ($requiredFile in @($pluginDll, $readmePath, $licensePath)) {
        if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
            throw "Required package file was not found: $requiredFile"
        }
    }

    $outputDir = Join-Path $root "artifacts"
    $stageRoot = Join-Path $outputDir "stage"
    $packageRoot = Join-Path $stageRoot "YMM4SandSim"
    $boothStage = Join-Path $outputDir "booth-stage"
    $baseName = "YMM4SandSim-v$version"
    $ymmePath = Join-Path $outputDir "$baseName.ymme"
    $zipPath = Join-Path $outputDir "$baseName.zip"

    Remove-Item -LiteralPath $stageRoot, $boothStage -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $ymmePath, $zipPath -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $packageRoot, $boothStage | Out-Null
    Copy-Item -LiteralPath $pluginDll -Destination $packageRoot -Force
    Copy-Item -LiteralPath $readmePath -Destination (Join-Path $packageRoot "Readme.txt") -Force
    Copy-Item -LiteralPath $licensePath -Destination $packageRoot -Force

    $licensesPath = Join-Path $root "LICENSES"
    if (Test-Path -LiteralPath $licensesPath -PathType Container) {
        Copy-Item -LiteralPath $licensesPath -Destination $packageRoot -Recurse -Force
    }
    Get-ChildItem -LiteralPath $buildDirectory -Directory | ForEach-Object {
        $resource = Join-Path $_.FullName "YMM4SandSim.resources.dll"
        if (Test-Path -LiteralPath $resource -PathType Leaf) {
            $cultureDirectory = Join-Path $packageRoot $_.Name
            New-Item -ItemType Directory -Force -Path $cultureDirectory | Out-Null
            Copy-Item -LiteralPath $resource -Destination $cultureDirectory -Force
        }
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory(
        $stageRoot, $ymmePath, [IO.Compression.CompressionLevel]::Optimal, $false)

    $archive = [IO.Compression.ZipFile]::OpenRead($ymmePath)
    try {
        $entries = @($archive.Entries | Where-Object Name | ForEach-Object FullName)
        $requiredEntries = @(
            "YMM4SandSim/YMM4SandSim.dll",
            "YMM4SandSim/Readme.txt",
            "YMM4SandSim/LICENSE.txt"
        )
        $unexpectedEntries = @($entries | Where-Object {
            $_ -notin $requiredEntries -and
            $_ -notmatch '^YMM4SandSim/LICENSES/[^/]+\.txt$' -and
            $_ -notmatch '^YMM4SandSim/[^/]+/YMM4SandSim\.resources\.dll$'
        })
        if ($unexpectedEntries.Count -ne 0) {
            throw "Unexpected files were found in ymme: $($unexpectedEntries -join ', ')"
        }
        if (@($requiredEntries | Where-Object { $entries -notcontains $_ }).Count -ne 0) {
            throw "Required files were not found in ymme."
        }
    }
    finally {
        $archive.Dispose()
    }

    Copy-Item -LiteralPath $ymmePath -Destination $boothStage -Force
    Copy-Item -LiteralPath $readmePath -Destination (Join-Path $boothStage "Readme.txt") -Force
    [IO.Compression.ZipFile]::CreateFromDirectory(
        $boothStage, $zipPath, [IO.Compression.CompressionLevel]::Optimal, $false)

    Remove-Item -LiteralPath $stageRoot, $boothStage -Recurse -Force
    Remove-Item -LiteralPath $ymmePath -Force
    Write-Host "Created release package: $zipPath" -ForegroundColor Green
}

switch ($Task) {
    "build" {
        Invoke-PluginBuild -Deploy
    }
    "test" {
        Invoke-Tests
    }
    "fmt" {
        Invoke-Format
    }
    "format" {
        Invoke-Format
    }
    "lint" {
        Invoke-Lint
    }
    "check" {
        Invoke-Format
        Invoke-Lint
        Invoke-Tests
    }
    "clean" {
        Remove-BuildOutputs
    }
    "shaders" {
        Invoke-ShaderBuild
    }
    "publish" {
        Invoke-PluginBuild -Deploy
        New-ReleasePackage
    }
}
