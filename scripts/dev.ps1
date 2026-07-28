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

function Get-ShaderDependencyPaths {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$ShaderDirectory
    )

    $pending = [System.Collections.Generic.Stack[string]]::new()
    $visited = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $pending.Push([IO.Path]::GetFullPath($SourcePath))

    while ($pending.Count -gt 0) {
        $path = $pending.Pop()
        if (-not $visited.Add($path)) {
            continue
        }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Shader dependency was not found: $path"
        }

        foreach ($line in [IO.File]::ReadLines($path)) {
            if ($line -notmatch '^\s*#\s*include\s+"([^"]+)"') {
                continue
            }

            $includeName = $Matches[1]
            $candidate = [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $path) $includeName))
            if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
                $candidate = [IO.Path]::GetFullPath((Join-Path $ShaderDirectory $includeName))
            }
            if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
                throw "Shader include was not found: $includeName (from $path)"
            }
            $pending.Push($candidate)
        }
    }

    return @($visited)
}

function Test-ShaderNeedsCompilation {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$OutputPath,
        [Parameter(Mandatory = $true)][string]$ShaderDirectory
    )

    if (-not (Test-Path -LiteralPath $OutputPath -PathType Leaf)) {
        return $true
    }

    $outputTime = (Get-Item -LiteralPath $OutputPath).LastWriteTimeUtc
    foreach ($dependency in Get-ShaderDependencyPaths -SourcePath $SourcePath -ShaderDirectory $ShaderDirectory) {
        if ((Get-Item -LiteralPath $dependency).LastWriteTimeUtc -gt $outputTime) {
            return $true
        }
    }

    return $false
}

function Get-ShaderCompilerParallelism {
    $parallelism = [Math]::Max(1, [Math]::Min([Environment]::ProcessorCount, 4))
    $configured = 0
    if ([int]::TryParse($env:YMM4SANDSIM_FXC_JOBS, [ref]$configured) -and $configured -gt 0) {
        $parallelism = [Math]::Min($configured, 16)
    }
    return $parallelism
}

function Start-ShaderCompilerProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FxcPath,
        [Parameter(Mandatory = $true)][string]$ShaderDirectory,
        [Parameter(Mandatory = $true)]$ShaderJob
    )

    $token = [Guid]::NewGuid().ToString("N")
    $tempOutput = "$($ShaderJob.OutputPath).tmp.$token"
    $stdoutPath = "$tempOutput.stdout"
    $stderrPath = "$tempOutput.stderr"
    $arguments = @(
        "/nologo",
        "/WX",
        "/O3",
        "/T", $ShaderJob.Profile,
        "/E", "main",
        "/I", ('"{0}"' -f $ShaderDirectory),
        "/Fo", ('"{0}"' -f $tempOutput),
        ('"{0}"' -f $ShaderJob.SourcePath)
    ) -join " "

    Write-Host "Compiling $($ShaderJob.Source) [$($ShaderJob.Profile)]"
    $process = Start-Process -FilePath $FxcPath -ArgumentList $arguments -NoNewWindow -PassThru `
        -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath

    return [pscustomobject]@{
        Token = $token
        Job = $ShaderJob
        Process = $process
        TempOutput = $tempOutput
        StdoutPath = $stdoutPath
        StderrPath = $stderrPath
    }
}

function Complete-ShaderCompilerProcess {
    param([Parameter(Mandatory = $true)]$ActiveJob)

    $process = $ActiveJob.Process
    $process.WaitForExit()
    $exitCode = $process.ExitCode
    $process.Dispose()

    $stdout = if (Test-Path -LiteralPath $ActiveJob.StdoutPath -PathType Leaf) {
        Get-Content -LiteralPath $ActiveJob.StdoutPath -Raw
    } else { "" }
    $stderr = if (Test-Path -LiteralPath $ActiveJob.StderrPath -PathType Leaf) {
        Get-Content -LiteralPath $ActiveJob.StderrPath -Raw
    } else { "" }

    try {
        if ($exitCode -ne 0) {
            $details = (($stdout, $stderr) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join [Environment]::NewLine
            throw "FXC failed for $($ActiveJob.Job.Source) with exit code $exitCode.$([Environment]::NewLine)$details"
        }
        if (-not (Test-Path -LiteralPath $ActiveJob.TempOutput -PathType Leaf)) {
            throw "FXC reported success but output is missing: $($ActiveJob.Job.OutputPath)"
        }

        if (Test-Path -LiteralPath $ActiveJob.Job.OutputPath -PathType Leaf) {
            [IO.File]::Replace($ActiveJob.TempOutput, $ActiveJob.Job.OutputPath, $null)
        }
        else {
            [IO.File]::Move($ActiveJob.TempOutput, $ActiveJob.Job.OutputPath)
        }
        Write-Host "Compiled $($ActiveJob.Job.Source)"
    }
    finally {
        Remove-Item -LiteralPath $ActiveJob.TempOutput, $ActiveJob.StdoutPath, $ActiveJob.StderrPath `
            -Force -ErrorAction SilentlyContinue
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

    $compileJobs = @()
    foreach ($shader in $shaderJobs) {
        $source = Join-Path $shaderDirectory $shader.Source
        $output = [IO.Path]::ChangeExtension($source, ".cso")
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "Shader source was not found: $source"
        }

        if (Test-ShaderNeedsCompilation -SourcePath $source -OutputPath $output -ShaderDirectory $shaderDirectory) {
            $compileJobs += [pscustomobject]@{
                Source = $shader.Source
                Profile = $shader.Profile
                SourcePath = $source
                OutputPath = $output
            }
        }
    }

    if ($compileJobs.Count -eq 0) {
        Write-Host "Shaders are up to date."
        return
    }

    $parallelism = Get-ShaderCompilerParallelism
    Write-Host "Compiling $($compileJobs.Count) shader(s) with up to $parallelism parallel FXC process(es)."

    $nextJob = 0
    $active = @()
    $failure = $null
    while ($nextJob -lt $compileJobs.Count -or $active.Count -gt 0) {
        while ($null -eq $failure -and $nextJob -lt $compileJobs.Count -and $active.Count -lt $parallelism) {
            $active += Start-ShaderCompilerProcess -FxcPath $fxc -ShaderDirectory $shaderDirectory -ShaderJob $compileJobs[$nextJob]
            $nextJob++
        }

        $completed = @($active | Where-Object { $_.Process.HasExited })
        if ($completed.Count -eq 0) {
            Start-Sleep -Milliseconds 50
            continue
        }

        $completedTokens = @($completed | ForEach-Object { $_.Token })
        foreach ($item in $completed) {
            try {
                Complete-ShaderCompilerProcess -ActiveJob $item
            }
            catch {
                if ($null -eq $failure) {
                    $failure = $_
                }
            }
        }
        $active = @($active | Where-Object { $_.Token -notin $completedTokens })
        if ($null -ne $failure) {
            $nextJob = $compileJobs.Count
        }
    }

    if ($null -ne $failure) {
        throw $failure
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
