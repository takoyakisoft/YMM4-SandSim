#!/usr/bin/env python3
from __future__ import annotations

import csv
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PRODUCT = ROOT / "YMM4SandSim"
SHADERS = PRODUCT / "Shaders"
MANIFEST = ROOT / "YMM4SandSim.Tests" / "TestData" / "material-palette.json"
TRANSLATIONS = PRODUCT / "Localization" / "Translate.csv"

def check(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)

def read_translations() -> dict[str, dict[str, str]]:
    with TRANSLATIONS.open(encoding="utf-8-sig", newline="") as stream:
        return {row["Key"]: row for row in csv.DictReader(stream)}

def test_manifest() -> list[dict[str, object]]:
    entries = json.loads(MANIFEST.read_text(encoding="utf-8"))
    check(len(entries) == 55, "manifest must contain 55 palette entries")
    check(len({entry["hex"] for entry in entries}) == 55, "palette colors must be unique")
    check(len({entry["id"] for entry in entries}) == 55, "palette material ids must be unique")
    check(len({entry["name"] for entry in entries}) == 55, "palette material names must be unique")
    return entries

def test_material_enum(entries: list[dict[str, object]]) -> None:
    text = (PRODUCT / "SandMaterial.cs").read_text(encoding="utf-8")
    enum_values = re.findall(r"^\s+(\w+) = (\d+),$", text, re.M)
    check(len(enum_values) == 57, "SandMaterial must contain 57 materials")
    values = {name: int(value) for name, value in enum_values}
    for entry in entries:
        check(values.get(str(entry["name"])) == int(entry["id"]), f"enum mismatch: {entry['name']}")
    palette_names = {str(entry["name"]) for entry in entries}
    check(set(values) - palette_names == {"Ember", "Gunpowder"},
          "SandMaterial must contain exactly the two simulation-only materials outside the 55-color palette")

def test_shader_material_contract(entries: list[dict[str, object]]) -> None:
    core = (SHADERS / "SandCore.hlsli").read_text(encoding="utf-8")
    common = (SHADERS / "SandCommon.hlsli").read_text(encoding="utf-8")
    enum_text = (PRODUCT / "SandMaterial.cs").read_text(encoding="utf-8")
    enum_values = re.findall(r"^\s+(\w+) = (\d+),$", enum_text, re.M)
    for name, value in enum_values:
        token = f"static const uint Material{name} = {value}u;"
        check(token in core, f"C#/HLSL material id mismatch: {name}")

    checks = {
        "MaterialMask = 0x0000003fu": "6-bit material mask",
        "AgeMask = 0x0003ffc0u": "12-bit age mask",
        "AgeShift = 6u": "age shift",
    }
    for token, label in checks.items():
        check(token in core, f"missing {label}")
    check("VariantMask" not in core and "VariantShift" not in core and "GetVariant(" not in core,
          "unused visual variant metadata must not consume bits or shader work")

    classifier = common.split("uint ClosestMaterialFromColor", 1)[1]
    calls = re.findall(
        r"ConsiderPaletteMaterial\(lab, float3\([^\)]*\), Material(\w+), bestDistance, bestMaterial\); // (#[0-9a-f]{6})",
        classifier,
    )
    check(len(calls) == 55, f"classifier has {len(calls)} anchors, expected 55")
    actual = {(hex_value, name) for name, hex_value in calls}
    expected = {(str(entry["hex"]), str(entry["name"])) for entry in entries}
    check(actual == expected, "classifier mapping differs from manifest")
    check("MaterialEmber, bestDistance" not in classifier, "Ember must stay outside automatic classifier")
    check("MaterialGunpowder, bestDistance" not in classifier, "Gunpowder must stay outside automatic classifier")

    for entry in entries:
        r = int(str(entry["hex"])[1:3], 16) / 255.0
        g = int(str(entry["hex"])[3:5], 16) / 255.0
        b = int(str(entry["hex"])[5:7], 16) / 255.0
        token = f"if (material == Material{entry['name']}) return float4({r:.9f}f, {g:.9f}f, {b:.9f}f, 1.0f); // {entry['hex']}"
        check(token in common, f"material color mismatch: {entry['name']}")


def test_behavior_class_masks(entries: list[dict[str, object]]) -> None:
    behavior = (SHADERS / "SandBehavior.hlsli").read_text(encoding="utf-8")

    def mask(name: str) -> int:
        match = re.search(rf"static const uint {name}\s*=\s*(0x[0-9a-fA-F]+)u;", behavior)
        check(match is not None, f"missing behavior mask: {name}")
        return int(match.group(1), 16)

    powder_low, powder_high = mask("PowderMaskLow"), mask("PowderMaskHigh")
    liquid_low, liquid_high = mask("LiquidMaskLow"), mask("LiquidMaskHigh")
    gas_low, gas_high = mask("GasMaskLow"), mask("GasMaskHigh")

    def contains(material_id: int, low: int, high: int) -> bool:
        return bool((low if material_id < 32 else high) & (1 << (material_id if material_id < 32 else material_id - 32)))

    classes: dict[int, str] = {}
    for material_id in range(1, 58):
        flags = [
            ("powder", contains(material_id, powder_low, powder_high)),
            ("liquid", contains(material_id, liquid_low, liquid_high)),
            ("gas", contains(material_id, gas_low, gas_high)),
        ]
        enabled = [name for name, flag in flags if flag]
        check(len(enabled) <= 1, f"material {material_id} appears in multiple movement classes: {enabled}")
        classes[material_id] = enabled[0] if enabled else "fixed"

    for entry in entries:
        material_id = int(entry["id"])
        check(classes[material_id] == str(entry["behavior"]),
              f"behavior mask mismatch for {entry['name']}: {classes[material_id]} != {entry['behavior']}")

    check(classes[7] == "gas", "support material Ember must remain gas")
    check(classes[9] == "powder", "support material Gunpowder must remain powder")
    check(sum(value == "fixed" for value in classes.values()) == 34, "expected 34 XPBD fixed materials")

    # Secondary reaction masks are easy to drift because they are handwritten
    # bitsets. Validate the semantic membership, not only the primary motion
    # class, so chemistry changes cannot silently add/remove unrelated materials.
    secondary_sets = {
        "WaterLike": {2, 56},
        "ColdSolid": {15, 25, 28},
        "Organic": {4, 16, 20, 35, 43, 47, 49, 50, 51, 54},
        "Heat": {5, 7, 11},
    }
    for prefix, expected_ids in secondary_sets.items():
        low, high = mask(prefix + "MaskLow"), mask(prefix + "MaskHigh")
        actual_ids = {material_id for material_id in range(1, 58) if contains(material_id, low, high)}
        check(actual_ids == expected_ids, f"{prefix} reaction mask mismatch: {sorted(actual_ids)} != {sorted(expected_ids)}")

    fixed_body = extract_hlsl_function(behavior, "bool IsFixed(")
    check("material >= MaterialSand && material <= MaterialQuartz" in fixed_body,
          "IsFixed must reject undefined six-bit material ids 58..63")

def extract_hlsl_function(text: str, signature: str) -> str:
    start = text.find(signature)
    check(start >= 0, f"missing HLSL function: {signature}")
    brace = text.find("{", start)
    check(brace >= 0, f"missing HLSL function body: {signature}")
    depth = 1
    index = brace + 1
    while index < len(text) and depth > 0:
        if text[index] == "{":
            depth += 1
        elif text[index] == "}":
            depth -= 1
        index += 1
    check(depth == 0, f"unbalanced HLSL function body: {signature}")
    return text[brace:index]

def test_material_behavior_parameters(entries: list[dict[str, object]]) -> None:
    behavior = (SHADERS / "SandBehavior.hlsli").read_text(encoding="utf-8")
    fixed = [str(entry["name"]) for entry in entries if entry.get("behavior") == "fixed"]
    check(len(fixed) == 34, f"expected 34 fixed palette materials, got {len(fixed)}")

    rigid_properties = extract_hlsl_function(behavior, "float4 RigidProperties(")
    missing = [name for name in fixed if rigid_properties.count(f"Material{name}") == 0]
    duplicate = [name for name in fixed if rigid_properties.count(f"Material{name}") != 1]
    check(not missing, f"RigidProperties lacks explicit fixed-material coverage: {missing}")
    check(not duplicate, f"RigidProperties must assign each fixed material exactly once: {duplicate}")
    check("x=density relative to water" in behavior and "y=compliance scale" in behavior and
          "z=per-substep velocity retention" in behavior and "w=tensile break strain" in behavior,
          "packed rigid property semantics must remain documented")
    rigid_rows = re.findall(
        r"Material(\w+)\) return float4\(([-0-9.]+)f, ([-0-9.]+)f, ([-0-9.]+)f, ([-0-9.]+)f\);",
        rigid_properties,
    )
    check(len(rigid_rows) == 34, "RigidProperties must contain exactly 34 explicit fixed-material rows")
    rigid_values = {name: tuple(map(float, values)) for name, *values in rigid_rows}
    for name, (density, compliance, retention, break_strain) in rigid_values.items():
        check(density > 0.0, f"{name}: density must be positive")
        check(compliance >= 0.0, f"{name}: compliance must be non-negative")
        check(0.0 < retention <= 1.0, f"{name}: velocity retention must be in (0,1]")
        check(0.0 < break_strain <= 1.0, f"{name}: break strain must be in (0,1]")
    check(rigid_values["Wood"][0] < 1.0 and rigid_values["Ice"][0] < 1.0 and rigid_values["PinkWax"][0] < 1.0,
          "wood/ice/wax should remain buoyant in water by density")
    check(rigid_values["Gold"][0] > rigid_values["Copper"][0] > rigid_values["Metal"][0] > rigid_values["Stone"][0],
          "representative dense-solid ordering drifted")
    check(rigid_values["CobaltGlass"][3] < rigid_values["Wood"][3] < rigid_values["Metal"][3],
          "brittle/organic/metal fracture ordering drifted")

    liquid = [str(entry["name"]) for entry in entries if entry.get("behavior") == "liquid"]
    fluid_properties = extract_hlsl_function(behavior, "float2 FluidProperties(")
    for name in liquid:
        check(fluid_properties.count(f"Material{name}") == 1, f"FluidProperties lacks liquid: {name}")
    fluid_rows = re.findall(r"Material(\w+)\) return float2\(([-0-9.]+)f, ([-0-9.]+)f\);", fluid_properties)
    check(len(fluid_rows) == 8, "FluidProperties must contain exactly eight liquid rows")
    fluid_values = {name: (float(density), float(retention)) for name, density, retention in fluid_rows}
    for name, (density, retention) in fluid_values.items():
        check(density > 0.0, f"{name}: fluid density must be positive")
        check(0.0 < retention <= 1.0, f"{name}: fluid velocity retention must be in (0,1]")
    check(fluid_values["LiquidNitrogen"][0] < fluid_values["Oil"][0] < fluid_values["Water"][0] <
          fluid_values["SeaWater"][0] < fluid_values["Ink"][0] < fluid_values["Acid"][0] <
          fluid_values["Slime"][0] < fluid_values["Lava"][0],
          "liquid density ordering must remain physically/gameplay coherent")

    # CA buoyancy order must agree with the packed liquid densities.
    rank = extract_hlsl_function(behavior, "uint DensityRank(")
    ordered_liquids = [
        "LiquidNitrogen", "Oil", "Water", "SeaWater", "Ink", "Acid", "Slime", "Lava"
    ]
    positions = [rank.find(f"Material{name}") for name in ordered_liquids]
    check(all(position >= 0 for position in positions), "DensityRank is missing a liquid material")
    check(positions == sorted(positions), "CA liquid density order disagrees with FluidProperties")
    # Common powders are less dense than molten rock; only dense KMnO4/rust sink through lava.
    for name in ("Coal", "Soil", "Gunpowder", "Sulfur", "Salt", "PinkSalt", "Sand"):
        check(rank.find(f"Material{name}") < rank.find("MaterialLava"),
              f"{name} must float on denser lava in the coarse CA density model")
    for name in ("PotassiumPermanganate", "Rust"):
        check(rank.find(f"Material{name}") > rank.find("MaterialLava"),
              f"{name} must remain denser than lava in the coarse CA density model")
    check("target == MaterialOil || target == MaterialInk" not in behavior,
          "generic ink must not inherit oil's high flammability")

    # Every CA-controlled material needs an explicit density rank and mobility.
    movable = [str(entry["name"]) for entry in entries if entry.get("behavior") != "fixed"] + ["Ember", "Gunpowder"]
    mobility = extract_hlsl_function(behavior, "float Mobility(")
    for name in movable:
        check(rank.count(f"Material{name}") == 1, f"DensityRank must explicitly cover movable material: {name}")
        check(mobility.count(f"Material{name}") == 1, f"Mobility must explicitly cover movable material: {name}")

def test_initialize_and_step() -> None:
    initialize = (SHADERS / "SandInitialize.hlsl").read_text(encoding="utf-8")
    step = (SHADERS / "SandStep.hlsl").read_text(encoding="utf-8")
    behavior = (SHADERS / "SandBehavior.hlsli").read_text(encoding="utf-8")
    render = (SHADERS / "SandRenderPS.hlsl").read_text(encoding="utf-8")

    check("material > MaterialQuartz" in initialize, "initializer must accept all 57 materials")
    check("ClosestMaterialFromColor(straightRgb)" in initialize, "initializer must use palette classifier")
    check("bool IsPowder" in behavior and "bool IsLiquid" in behavior and "bool IsFixed" in behavior, "behavior classes missing")
    check("MaterialLiquidNitrogen" in step and "MaterialSeaWater" in step, "water variants missing")
    check("MaterialPinkWax" in step and "ReactWaxAndHeat" in step, "wax melting missing")
    check("MaterialCopper" in step and "MaterialOxidizedCopper" in step, "copper oxidation missing")
    check("firstIsDissolvingSalt" in step and "MaterialPinkSalt" in step,
          "salt and pink salt must share water dissolution behavior")
    check("secondMaterial == MaterialOil" not in step and "firstMaterial == MaterialOil" not in step,
          "salt must not dissolve in oil")
    horizontal = extract_hlsl_function(step, "uint TryHorizontalMover(")
    check("target == MaterialEmpty" in horizontal, "lateral liquid/gas flow must fill empty cells")
    check("DensityRank" not in horizontal,
          "horizontal flow must not density-swap non-empty fluids; buoyancy belongs to vertical/diagonal motion")
    check("const bool logicalA" in step and "const bool rigidA = !logicalA" in step,
          "odd logical CA boundaries must treat only padded cells as walls")
    check("p11.x >= LogicalStateWidth || p11.y >= LogicalStateHeight" not in step,
          "partial odd-sized CA blocks must not freeze their real boundary cells")
    check("if (logicalA) StoreResolvedCell" in step and "if (logicalD) StoreResolvedCell" in step,
          "CA must only store real cells from partial padded blocks")
    check("StepVerticalLogicalLine" in step and "StepHorizontalLogicalLine" in step and "StepSingleLogicalCell" in step,
          "one-cell-wide/high CA grids need explicit 1D update paths")
    standalone = extract_hlsl_function(step, "void AdvanceStandaloneCell(")
    check("AdvanceLifetime(cell, position, salt)" in standalone,
          "Margolus boundary cells must advance lifetime even when they are outside a shifted 2x2 block")
    check(step.count("AdvanceStandaloneCell(") >= 11,
          "all 1D and shifted-phase boundary paths must use standalone lifetime advancement")
    check("if (ColorMode == 1u && !transientHeat)" in render, "PreserveInput mode missing")
    check("straightColor = UnpackColor(color);" in render, "PreserveInput must load original color")

    for name, text in (("initialize", initialize), ("step", step), ("render", render)):
        check(text.count("{") == text.count("}"), f"{name}: unbalanced braces")

def test_shader_build_list() -> None:
    csproj = (PRODUCT / "YMM4SandSim.csproj").read_text(encoding="utf-8")
    compile_script = (ROOT / "scripts" / "dev.ps1").read_text(encoding="utf-8")
    project_shaders = set(re.findall(r'<HlslShader Include="Shaders\\([^"\\]+\.hlsl)">', csproj))
    script_shaders = set(re.findall(r'Source = "([^"/\\]+\.hlsl)"', compile_script))
    check(project_shaders, "project HLSL shader list is empty")
    check(project_shaders == script_shaders,
          f"csproj/dev.ps1 shader lists differ: project-only={sorted(project_shaders-script_shaders)}, script-only={sorted(script_shaders-project_shaders)}")
    check("SandRigidReact.hlsl" in script_shaders, "rigid reaction shader must be compiled by FXC")
    for shader in ("SandExplosionUpdate.hlsl", "SandLightSeed.hlsl", "SandLightPropagate.hlsl"):
        check(shader in script_shaders, f"{shader} must be compiled by FXC")
    check("Get-ShaderDependencyPaths" in compile_script and "LastWriteTimeUtc" in compile_script,
          "shader compilation must track recursive includes and skip up-to-date bytecode")
    check("Start-Process -FilePath $FxcPath" in compile_script and "Get-ShaderCompilerParallelism" in compile_script,
          "shader compilation must run independent FXC processes in parallel")
    check('[ValidateSet("Fast", "Release")]' in compile_script and
          '"/O3"' in compile_script and '"/O0"' in compile_script and '$output.mode' in compile_script,
          "shader compilation must retain explicit optimization modes for diagnostics")
    check("$tempOutput" in compile_script and
          "[IO.File]::Replace($ActiveJob.TempOutput, $ActiveJob.Job.OutputPath, $backupOutput)" in compile_script and
          "$backupOutput" in compile_script and
          "[IO.File]::Move($ActiveJob.TempOutput, $ActiveJob.Job.OutputPath)" in compile_script,
          "shader compilation must replace bytecode only after FXC succeeds")
    check('throw "FXC reported success but output is missing: $($ActiveJob.Job.OutputPath)"' in compile_script,
          "FXC success must still require a newly generated .cso output")


def test_timeline_policy_contract() -> None:
    policy = (PRODUCT / "SandTimelinePolicy.cs").read_text(encoding="utf-8")
    check("injectEveryFrame" not in policy,
          "AddEveryFrame must not advance once per render evaluation")
    for access_kind in ("Initial", "Continuous", "Random"):
        check(access_kind in policy,
              f"timeline policy must define the {access_kind} access state")
    check("var accessKind = Classify(isFirst, frame, lastFrame);" in policy,
          "timeline decisions must use the shared three-state access classifier")
    check("accessKind is SandTimelineAccessKind.Initial or SandTimelineAccessKind.Random" in policy,
          "initial and random access must rebuild irreversible simulation state")
    check("reset || (!sameFrame && sourceMode != SandSourceMode.Snapshot)" in policy,
          "emitter/restamp input must be uploaded once when the timeline frame advances")
    check("var needsAdvance = !sameFrame || reset;" in policy,
          "same-frame evaluation must not double-advance stateful simulation")
def test_constant_buffer_layout() -> None:
    core = (SHADERS / "SandCore.hlsli").read_text(encoding="utf-8")
    gpu = (PRODUCT / "SandSimulationGpu.cs").read_text(encoding="utf-8")
    hlsl_body = re.search(r"cbuffer SandConstants : register\(b0\)\s*\{(.*?)\};", core, re.S)
    cs_body = re.search(r"private struct GpuConstants\s*\{(.*?)\n\s*\}", gpu, re.S)
    check(hlsl_body is not None and cs_body is not None, "constant buffer definitions missing")
    hlsl = re.findall(r"\b(?:int|uint|float)\s+(\w+)\s*;", hlsl_body.group(1))
    csharp = re.findall(r"public (?:int|uint|float) (\w+);", cs_body.group(1))
    check(hlsl == csharp, "HLSL/C# constant buffer layout mismatch")
    check(len(hlsl) == 48 and len(hlsl) % 4 == 0, "constant buffer must contain 48 aligned scalars")

def test_multi_instance_graph_and_context_contract() -> None:
    processor = (PRODUCT / "SandSimulationEffectProcessor.cs").read_text(encoding="utf-8")
    gpu = (PRODUCT / "SandSimulationGpu.cs").read_text(encoding="utf-8")
    render = (SHADERS / "SandRenderPS.hlsl").read_text(encoding="utf-8")
    csproj = (PRODUCT / "YMM4SandSim.csproj").read_text(encoding="utf-8")

    check("SandSimulationCustomEffect" not in processor and
          "D2D1CustomShaderEffectBase" not in processor and
          not (PRODUCT / "SandSimulationCustomEffect.cs").exists(),
          "SandSim output graph must not retain managed D2D custom-effect callback shadows")
    check("SandComposite.hlsl" not in csproj and not (SHADERS / "SandComposite.hlsl").exists(),
          "obsolete D2D composite shader must not be compiled or deployed")
    check("SourceTexture" not in render and "sourceColor" not in render and "Amount" not in render and
          "if (material == MaterialEmpty)" in render and "HasShockwaveLightMarker" in render and
          "float4(shockwaveColor * shockwaveAlpha, shockwaveAlpha)" in render and
          "return float4(straightColor.rgb * straightColor.a, straightColor.a);" in render,
          "plugin-owned D3D render pass must output simulation cells plus the premultiplied empty-cell shock front")
    check("CreateDeviceContextState<ID3D11Device1>" in gpu and
          "CreateDeviceContextState<ID3D11DeviceContext1>" not in gpu and
          gpu.count("EnterIsolatedContext()") >= 4 and
          gpu.count("LeaveIsolatedContext(previousContextState)") == 3,
          "each immediate-context GPU pass must use a valid emulated device interface and restore YMM4 pipeline state")
    check("D3DFeatureLevel.Level_11_1" in gpu and
          "D3DFeatureLevel.Level_11_0" in gpu and
          "[device.FeatureLevel]" not in gpu,
          "context-state creation must use its supported feature levels instead of a D3D 12 device level")
    check("_isolatedContextState.Dispose();" in gpu,
          "plugin-owned D3D context state must be released")
    clear_input = re.search(
        r"public void ClearInput\(\)\s*\{(.*?)\n\s*\}",
        processor,
        re.S,
    )
    check(clear_input is not None and
          "ClearEffectGraph()" not in clear_input.group(1) and
          "_input = null;" in clear_input.group(1),
          "ClearInput must release the external input without disconnecting the internal output graph")

def test_gpu_xpbd_contract() -> None:
    behavior = (SHADERS / "SandBehavior.hlsli").read_text(encoding="utf-8")
    initialize = (SHADERS / "SandInitialize.hlsl").read_text(encoding="utf-8")
    rigid_initialize = (SHADERS / "SandRigidInitialize.hlsl").read_text(encoding="utf-8")
    integrate = (SHADERS / "SandRigidIntegrate.hlsl").read_text(encoding="utf-8")
    solve = (SHADERS / "SandRigidSolve.hlsl").read_text(encoding="utf-8")
    grid = (SHADERS / "SandRigidGrid.hlsl").read_text(encoding="utf-8")
    components = (SHADERS / "SandRigidComponents.hlsl").read_text(encoding="utf-8")
    react = (SHADERS / "SandRigidReact.hlsl").read_text(encoding="utf-8")
    step = (SHADERS / "SandStep.hlsl").read_text(encoding="utf-8")
    render = (SHADERS / "SandRenderPS.hlsl").read_text(encoding="utf-8")
    gpu = (PRODUCT / "SandSimulationGpu.cs").read_text(encoding="utf-8")
    effect = (PRODUCT / "SandSimulationEffect.cs").read_text(encoding="utf-8")
    processor = (PRODUCT / "SandSimulationEffectProcessor.cs").read_text(encoding="utf-8")

    check("return IsFixed(material);" in behavior, "fixed materials must be owned by GPU solid physics")
    check("float4 RigidProperties" in behavior and "float2 FluidProperties" in behavior,
          "solid/fluid parameters must use packed property lookups")
    check("uint RigidFractureSpanCells(uint material)" in behavior and
          "MaterialCobaltGlass" in behavior and "MaterialMetal" in behavior and
          "RigidFractureSpanCells(material)" in integrate and "PhysicsChunkSpan" not in integrate,
          "controller fracture scale must be material-specific and independent from explosion radius")
    check("float RigidPairComplianceScale" in behavior and "float RigidPairBreakStrain" in behavior,
          "solid bond property helpers are missing")
    for token in ("SolidGravity", "SolidStiffness", "SolidBreakStrength", "SolidSolverIterations"):
        check(f"public Animation {token}" in effect, f"missing solid-physics UI parameter: {token}")
        check(f"{token}:" in processor, f"processor does not forward solid-physics UI parameter: {token}")
    check("SolidChunkSize" not in effect and "SolidChunkSize" not in processor,
          "fixed macro-size UI must be removed when connected components define body size")
    check('AnimationSlider("F0", "回", 1, SandSimulationSettings.MaximumIterationsPerFrame)' in effect,
          "speed slider must expose the same maximum used by runtime clamping")
    check('AnimationSlider("F0", "回", 0, SandSimulationSettings.MaximumWarmupIterations)' in effect,
          "warmup slider must expose the same maximum used by runtime clamping")
    check('AnimationSlider("F0", "回", 1, SandSimulationSettings.MaximumSolidSolverIterations)' in effect,
          "solid solver slider must expose the same maximum used by runtime clamping")
    check("PhysicsGravity = 120.0f * parameters.SolidGravity" in gpu, "gravity UI must reach GPU constants")
    check("parameters.SolidStiffness" in gpu and "PhysicsCompliance" in gpu, "stiffness UI must reach XPBD compliance")
    check("parameters.SolidStiffness > 0.0f" in gpu and ": 1.0f" in gpu and
          "0.25f" not in gpu[gpu.find("PhysicsCompliance ="):gpu.find("PhysicsDamping =")],
          "0 percent stiffness must not be silently raised to 25 percent")
    check("1.0e-4f" in integrate and "0.04f" not in integrate[integrate.find("fractureThreshold"):integrate.find("if (impulseMagnitude > fractureThreshold)")],
          "0 percent break strength must not retain the old large fracture floor")
    check("PhysicsSolverIterations = (uint)parameters.SolidSolverIterations" in gpu, "solver-iteration UI must reach GPU")
    check("IsRigidPhysicsMaterial(material)" in initialize, "cellular initializer must exclude rigid-owned cells")
    check("ExistingRigidOccupancy : register(t3)" in initialize and "occupiedByOtherRigid" in initialize,
          "cellular source injection must treat current rigid occupancy as occupied")
    check("CSSetShaderResource(3, _rigidOccupancySrv" in gpu,
          "host must bind rigid occupancy during cellular initialization")
    check("overwriteSelected" in rigid_initialize and "RigidMeta[statePosition] = 0u" in rigid_initialize,
          "rigid stamping must be able to relinquish ownership")
    check("InitializeMode == 1u" in rigid_initialize and "CellularMeta.Load" in rigid_initialize,
          "FillEmptyOnly must not create a rigid owner over occupied CA state")
    check("ExistingRigidOccupancy.Load" in rigid_initialize and "RigidOwnerFor" in rigid_initialize,
          "emitter initialization must reject a source cell already occupied by another rigid particle")
    check("verticalAcceleration * PhysicsDeltaTime * PhysicsDeltaTime" in integrate, "rigid integration must use acceleration over fixed dt")
    check("!IsRigidPhysicsMaterial(material)" in integrate,
          "integrator must ignore non-rigid transition states")
    check("rigidProperties = RigidProperties(material)" in integrate and "rigidProperties.z" in integrate,
          "per-material solid damping must use the packed rigid property lookup")
    check("maximumRigidStep = 0.95f" in integrate,
          "rigid integration must stay below one cell per substep to limit tunnelling")
    check("fluidProperties = FluidProperties(fluidMaterial)" in integrate and "fluidProperties.x" in integrate and "fluidProperties.y" in integrate,
          "rigid particles must use packed liquid density/drag for GPU buoyancy")
    check("PreserveBrokenBond" in integrate and "BrokenRigidBondMarker" in integrate,
          "fractured XPBD bonds must survive lambda reset between substeps")
    check("activeCount < 2u" in solve and "IsRigidPhysicsMaterial(material00)" in solve,
          "solver must skip sparse/non-rigid 2x2 blocks before state/lambda traffic")
    check("topLeft.x + 1u >= StateWidth" in solve and "topLeft.y + 1u >= StateHeight" in solve,
          "XPBD odd logical boundaries must be solved through padded state cells")
    check("properties00 = RigidProperties(material00)" in solve and
          "properties11 = RigidProperties(material11)" in solve and
          "1.0f / max(propertiesA.x" in solve and "1.0f / max(propertiesB.x" in solve,
          "per-material density/inverse mass must load properties once per active 2x2 cell and reuse them across bonds")
    check("if (active00 && active10 && sameBody00_10)" in solve and "if (active10 && active01 && sameBody10_01)" in solve,
          "solver must avoid bond work across inactive or separate-body endpoints")
    check("RigidPairComplianceScale(propertiesA, propertiesB, sameCohesiveRegion)" in solve,
          "per-material XPBD compliance is missing")
    check("RigidPairBreakStrain(propertiesA, propertiesB, sameCohesiveRegion)" in solve and "tensileStrain" in solve,
          "per-material tensile fracture is missing")
    check("RigidBodyLabel : register(t1)" in solve and "sameBody00_10" in solve and
          "active00 && active10 && sameBody00_10" in solve and "IsSameRigidMacro" not in solve,
          "XPBD bonds must exist only inside one same-material connected body")
    check("* PhysicsBreakStrength" in solve, "global fracture-strength UI multiplier is missing")
    check("solveHorizontal" in solve and "solveVertical" in solve,
          "axial constraints must not be duplicated across shifted parity phases")
    check("compliance / dt2" in solve, "XPBD compliance scaling is missing")
    check("1.41421356237f" in solve, "diagonal shear constraints are missing")
    check("ClampRigidStateToWorld" in solve and "state.z = clamped.x" in solve and "state.w = clamped.y" in solve,
          "world-boundary projection must remove velocity on clamped axes")
    check("(PhysicsPhase >> 1u) & 1u" in solve and "phase < 4u" in gpu,
          "all four 2x2 parity phases must be solved for full 8-neighbour coverage")
    check("InterlockedMin" in grid, "deterministic GPU grid ownership is missing")
    check("RigidBodyLabel : register(t3)" in grid and "RigidBodyContact : register(u2)" in grid and
          "bodyOwner = RigidBodyLabel.Load" in grid and "PhysicsPass == 3u" in grid and
          "RigidBodyContact[bodyCell]" in grid and "InterlockedOr" in grid and
          "StopRigidAxes" in grid and "RigidContactHorizontal" in grid and "RigidContactVertical" in grid,
          "rigid collision must propagate axis-specific external contact across one connected body")
    check("CSSetUnorderedAccessView(2, rigidBodyContactUav)" in gpu and "PhysicsPass = 3u" in gpu and
          "CSSetShaderResource(3, rigidBodyLabelSrv)" in gpu,
          "host must execute the connected-body contact resolve pass")
    check("IsRigidPhysicsMaterial(material)" in grid, "grid rasterization must ignore non-rigid transition states")
    check("return IsFixedCell(target) || IsOccupiedByOtherBody(id, target);" in grid and
          "IsPowder" not in extract_hlsl_function(grid, "bool HasExternalObstacle("),
          "loose powder must not erase body momentum while fixed CA solids still block rigid bodies")
    check("RigidBodyLabel : register(u0)" in components and "RigidMeta : register(t0)" in components and
          "RigidLambda : register(t1)" in components and "InterlockedMin(RigidBodyLabel" in components and
          "GetMaterial(RigidMeta.Load(int3(second, 0))) != material" in components and
          "id + uint2(1u, 0u)" in components and "id + uint2(0u, 1u)" in components,
          "rigid bodies must be GPU-labelled four-neighbour same-material connected components")
    check('ShaderBytecode.Load("SandRigidComponents")' in gpu and "BuildRigidComponents(ref constants)" in gpu,
          "host must build connected rigid-body labels without CPU readback")
    check("EmptyRigidOwner = 0xffffffffu" in grid and "EmptyRigidOwner = 0xffffffffu" in step,
          "rigid occupancy sentinel mismatch")
    check("RigidOccupancy : register(t2)" in step, "cellular solver must consume rigid occupancy")
    check(re.search(r"\bCell\s+\w+\s*=\s*[^;?]*\?", step) is None,
          "FXC does not accept conditional-operator selection of Cell structs")
    check("StoreResolvedCell" in step and "CopyCell(position);" in step,
          "CA cells hidden by rigid occupancy must be preserved rather than destroyed")
    check("RigidOccupancy : register(t2)" in render and "RigidColor : register(t3)" in render,
          "renderer must composite rigid cells")
    check("BuildRigidOccupancy(ref constants, resolveConflicts: true)" in gpu,
          "host must resolve/rasterize rigid occupancy after XPBD")
    check("CSSetShaderResource(2, _rigidOccupancySrv" in gpu,
          "cellular pass must bind rigid occupancy when XPBD is enabled")
    check("CSSetShaderResource(2, cellularMetaSrv)" in gpu,
          "rigid collision pass must bind current CA metadata")
    check("ShaderBytecode.Load(\"SandRigidReact\")" in gpu and "ReactRigid(ref constants" in gpu,
          "host must execute the GPU rigid/CA reaction bridge")
    check("ConvertRigidToCell" in react and "MaterialOxidizedCopper" in react and "AcidProbability" in react,
          "rigid solids must keep CA melting/oxidation/corrosion reactions")
    environment = extract_hlsl_function(react, "void ReadEnvironment(")
    check("ConsiderEnvironment(ReadPreviousMaterial(p)," in environment,
          "rigid chemistry must include the CA material overlapped by the rigid cell")
    convert = extract_hlsl_function(react, "void ConvertRigidToCell(")
    check("CellularColor[target] = color;" in convert and "CellularMeta[target] = MakeMeta" in convert,
          "rigid phase changes must write their CA product even when a hidden fluid occupied the cell")
    check("GetMaterial(CellularMeta[target]) == MaterialEmpty" not in convert,
          "rigid phase-change products must not be dropped behind an empty-cell guard")
    check("ReactionSalt" in react and "StepIndex * 0x9e3779b9u" in react,
          "rigid reaction randomness must vary deterministically per CA iteration")
    check("Promote fixed materials created by CA reactions" in react and "IsRigidPhysicsMaterial(cellMaterial)" in react,
          "CA-created fixed materials must be promoted back into XPBD when a slot is free")
    check("GetData" not in gpu and "CopyResource" not in gpu and "Map(_rigid" not in gpu,
          "GPU solid physics must not add CPU readback")

    for name, text in (
        ("rigid initialize", rigid_initialize),
        ("rigid integrate", integrate),
        ("rigid solve", solve),
        ("rigid grid", grid),
        ("rigid components", components),
        ("rigid react", react),
    ):
        check(text.count("{") == text.count("}"), f"{name}: unbalanced braces")



def test_explosion_and_lighting_contract() -> None:
    core = (SHADERS / "SandCore.hlsli").read_text(encoding="utf-8")
    behavior = (SHADERS / "SandBehavior.hlsli").read_text(encoding="utf-8")
    step = (SHADERS / "SandStep.hlsl").read_text(encoding="utf-8")
    integrate = (SHADERS / "SandRigidIntegrate.hlsl").read_text(encoding="utf-8")
    explosion = (SHADERS / "SandExplosionUpdate.hlsl").read_text(encoding="utf-8")
    light_common = (SHADERS / "SandLighting.hlsli").read_text(encoding="utf-8")
    light_seed = (SHADERS / "SandLightSeed.hlsl").read_text(encoding="utf-8")
    light_propagate = (SHADERS / "SandLightPropagate.hlsl").read_text(encoding="utf-8")
    render = (SHADERS / "SandRenderPS.hlsl").read_text(encoding="utf-8")
    gpu = (PRODUCT / "SandSimulationGpu.cs").read_text(encoding="utf-8")
    effect = (PRODUCT / "SandSimulationEffect.cs").read_text(encoding="utf-8")
    processor = (PRODUCT / "SandSimulationEffectProcessor.cs").read_text(encoding="utf-8")

    check("ExplosionEventFlag = 0x04000000u" in core, "explosion must use one reserved metadata bit")
    check("ClearExplosionEvent" in explosion and "CellularMeta[id] = meta" in explosion,
          "explosion trigger must be consumed exactly once")
    check("second.Meta |= ExplosionEventFlag" in step and "first.Meta |= ExplosionEventFlag" in step,
          "gunpowder ignition must seed explosion events in either pair order")
    check("HasPendingExplosion" in step and
          "HasPendingExplosion(upper) || HasPendingExplosion(lower)" in step and
          "HasPendingExplosion(upper) || HasPendingExplosion(diagonal)" in step and
          "HasPendingExplosion(lower) || HasPendingExplosion(diagonal)" in step and
          "HasPendingExplosion(destination) || HasPendingExplosion(moverCell)" in step and
          "HasPendingExplosion(first) || HasPendingExplosion(second)" in step,
          "new explosion events must remain chemically and spatially fixed until the pressure pass consumes them")
    check("MaterialSeaWater" in step and "firstIsDissolvingSalt" in step and "secondIsDissolvingSalt" in step,
          "salt dissolved into ordinary water must produce sea water instead of disappearing without changing the solvent")
    check("TriggerGunpowderFromBlast" in step and "blastEnergy" in step and "cell.Meta |= ExplosionEventFlag" in step,
          "strong pressure waves must be able to chain-detonate gunpowder without a CPU event list")
    check("ExplosionPressure : register(t3)" in step and "TryBlastPair" in step,
          "CA motion must consume the GPU pressure field")
    check("ExplosionPressure : register(t2)" in integrate and "ExplosionImpulseAt" in integrate,
          "XPBD integration must consume the same pressure field")
    check("frontMask * (0.55f + strengthScale * 0.65f) * densityScale" in integrate,
          "controller explosion impulses must scale with rigid material density")
    check("BrokenRigidBondMarker" in integrate and "fractureThreshold" in integrate,
          "explosion impulse must be able to fracture XPBD bonds")
    check("PreviousPressure : register(t0)" in explosion and "ExplosionFalloff" in explosion and "ExplosionDecay" in explosion,
          "pressure wave must propagate and decay on GPU")
    check("ExplosionPressureTransmission" in behavior and "RigidProperties" in behavior,
          "explosion pressure must use material-specific transmission")
    pressure_body = extract_hlsl_function(behavior, "float ExplosionPressureTransmission(")
    check(pressure_body.find("MaterialPinkWax") < pressure_body.find("IsOrganic(material)"),
          "pink wax blast transmission must not be shadowed by the generic organic branch")
    check('RigidOccupancy : register(t1)' in explosion and 'RigidMeta : register(t2)' in explosion and
          "MaterialAt((uint2)sourcePosition)" in explosion,
          "explosion pressure tile load must account for XPBD occupancy/material shielding")
    check('CSSetShaderResource(1, _rigidOccupancySrv' in gpu and 'CSSetShaderResource(2, _rigidMetaSrv' in gpu,
          "host must bind rigid occupancy/materials while propagating explosion pressure")
    check("UpdateExplosion(ref constants)" in gpu and "ResetExplosionPressure(ref constants)" in gpu and
          "ClearExplosionState(ref constants)" in gpu,
          "host must update/reset pressure and consume pending events when explosions are disabled")
    check("PhysicsPass = 2u" in gpu and "PhysicsPass == 2u" in explosion,
          "explosion disable transition needs a one-shot event-consume/clear pass")
    check("Format.R32_Float" in gpu and "_explosionPressureTextures" in gpu,
          "pressure field must remain GPU resident without readback")

    effect_source = (PRODUCT / "SandSimulationEffect.cs").read_text(encoding="utf-8")
    check(re.search(r"public Animation AmbientLight[\s\S]*?=\s*new\(\s*100,", effect_source) is not None,
          "Ambient light must default to 100% so lighting adds emission without globally darkening the image.")

    for token in ("ExplosionStrength", "ExplosionRadius", "LightingStrength", "LightingRadius", "AmbientLight", "ShadowStrength"):
        check(f"public Animation {token}" in effect, f"missing UI parameter: {token}")
        check(f"{token}:" in processor, f"processor does not forward UI parameter: {token}")
    for token in ("ExplosionX", "ExplosionY", "ExplosionTriggerFrame"):
        check(f"public Animation {token}" in effect, f"missing explosion-controller UI parameter: {token}")
        check(f"{token}:" in processor, f"processor does not forward explosion-controller parameter: {token}")
    check("public bool ExplosionControllerEnabled" in effect and "[ToggleSlider]" in effect,
          "manual explosion controller needs an explicit enable toggle")
    check("new VideoEffectController(" in processor and processor.count("new ControllerPoint(") >= 2 and
          "new Vector3(parameters.ExplosionX, parameters.ExplosionY, 0f)" in processor and
          "_item.ExplosionX.AddToEachValues(args.Delta.X)" in processor and
          "_item.ExplosionY.AddToEachValues(args.Delta.Y)" in processor,
          "YMM4 preview controller must drag the item-local manual explosion center")
    check("var radiusPixels = (float)parameters.ExplosionRadius" in processor and
          "_item.ExplosionRadius.AddToEachValues(args.Delta.X)" in processor and
          "VideoControllerPointConnection.Line" in processor,
          "YMM4 preview controller must expose a connected radius handle in pixel units")
    check("(parameters.ExplosionRadius + parameters.ParticleSize - 1) / parameters.ParticleSize" in processor,
          "pixel explosion radius must convert to cell radius only at the GPU boundary")
    check("SandExplosionTriggerPolicy.ShouldTrigger(" in processor,
          "manual explosion trigger timing must use the deterministic trigger policy")
    check("gpuParameters with { ManualExplosion = false }" in processor and
          processor.count("Step(in warmupGpuParameters, parameters.WarmupIterations)") == 3,
          "warmup must never seed the manual explosion before the displayed frame step")
    check("ManualExplosionEnabled" in core and "manualExplosion" not in explosion and
          "eventSeed = explosion ? 1.0f : 0.0f" in explosion,
          "controller explosions must not seed the slow CA pressure field")
    check("ManualExplosionPropagationFrames = 6u" in gpu and
          "PrepareManualExplosionWaveForStep(ref constants, i == 0)" in gpu and
          "Math.Min(GetManualExplosionWaveAdvance(constants.ExplosionRadius), visibleRadius)" in gpu and
          "GetManualExplosionWaveAdvance" in gpu,
          "controller shockwave must advance once per output frame independently of simulation iterations")
    check("ExplosionStrength == other.ExplosionStrength" in processor and "ExplosionRadius == other.ExplosionRadius" in processor,
          "explosion physics changes must reset/rebuild timeline state")
    check("_parameters.LightingStrength != parameters.LightingStrength" in processor,
          "lighting-only edits must rerender the current frame without simulation advance")

    for material in ("MaterialFire", "MaterialEmber", "MaterialLava", "MaterialSeaLantern"):
        check(material in light_common, f"missing emissive light material: {material}")
    check("MaterialLightTransmission" in light_common and "MaterialSmoke" in light_common and "MaterialInk" in light_common,
          "light propagation must account for material-specific occlusion")
    check("ExplosionPressure : register(t3)" in light_seed, "explosions must emit synchronized light flashes")
    check("LightTransmissionAt" in light_propagate and "UnpackLightTransmission" in light_propagate,
          "light transport must use transmission packed by the seed pass")
    check("CellularMeta" not in light_propagate and "RigidOccupancy" not in light_propagate and "RigidMeta" not in light_propagate,
          "light propagation must not re-read material/occupancy textures on every radius pass")
    check("ReadDiagonalPressure" in explosion and "TransmissionAt(sideA)" in explosion and "TransmissionAt(sideB)" in explosion,
          "diagonal explosion pressure must not leak through a fully closed corner")
    check("offset.x != 0 && offset.y != 0" in light_propagate and "sideA" in light_propagate and "sideB" in light_propagate,
          "diagonal light propagation must not leak through a fully closed corner")
    check("groupshared uint LightTile[100]" in light_propagate and "GroupMemoryBarrierWithGroupSync" in light_propagate,
          "light propagation must stage its 10x10 halo in group-shared memory")
    check("groupshared float PressureTile[100]" in explosion and "groupshared float TransmissionTile[100]" in explosion and
          "GroupMemoryBarrierWithGroupSync" in explosion,
          "explosion propagation must stage pressure/material transmission per 8x8 group")
    for material in ("MaterialCobaltGlass", "MaterialIce", "MaterialQuartz", "MaterialPinkWax"):
        check(material in light_common, f"translucent rigid material missing explicit light transmission: {material}")
    check("LightField : register(t5)" in render and "AmbientLight" in render and "LightingStrength" in render,
          "renderer must preserve ambient brightness while applying propagated emissive light")
    check("overdrive" in render and "LightingStrength - 1.0f" in render,
          "lighting values above 100 percent must strengthen emission rather than only darken shadows")
    check("if (constants.LightingStrength <= 0.0f)" in gpu,
          "disabled lighting must skip render-time light compute dispatches")
    check("BuildLighting(ref constants" in gpu and 'ShaderBytecode.Load("SandLightSeed")' in gpu and 'ShaderBytecode.Load("SandLightPropagate")' in gpu,
          "host must build GPU light field before render")
    check("Map(_explosion" not in gpu and "Map(_light" not in gpu,
          "explosion and lighting must not add GPU-to-CPU readback")

    for name, text in (("explosion", explosion), ("light seed", light_seed), ("light propagate", light_propagate), ("lighting include", light_common)):
        check(text.count("{") == text.count("}"), f"{name}: unbalanced braces")


def test_xpbd_phase_schedule() -> None:
    def validate(logical_width: int, logical_height: int) -> None:
        state_width = logical_width + (logical_width & 1)
        state_height = logical_height + (logical_height & 1)
        counts: dict[tuple[tuple[int, int], tuple[int, int]], int] = {}

        def real(point: tuple[int, int]) -> bool:
            return point[0] < logical_width and point[1] < logical_height

        def edge(a: tuple[int, int], b: tuple[int, int]) -> tuple[tuple[int, int], tuple[int, int]]:
            return (a, b) if a <= b else (b, a)

        def add(a: tuple[int, int], b: tuple[int, int]) -> None:
            # Shader calls SolveDistance for padded neighbours too, but their
            # metadata is empty. Count only active logical-cell pairs.
            if not real(a) or not real(b):
                return
            key = edge(a, b)
            counts[key] = counts.get(key, 0) + 1

        for phase in range(4):
            ox = phase & 1
            oy = (phase >> 1) & 1
            touched: set[tuple[int, int]] = set()
            for by in range(state_height // 2):
                for bx in range(state_width // 2):
                    x = bx * 2 + ox
                    y = by * 2 + oy
                    if x + 1 >= state_width or y + 1 >= state_height:
                        continue
                    points = ((x, y), (x + 1, y), (x, y + 1), (x + 1, y + 1))
                    check(not any(point in touched for point in points),
                          f"XPBD phase {phase} contains overlapping 2x2 writes")
                    touched.update(points)
                    a, b, c, d = points
                    if (phase & 2) == 0:
                        add(a, b)
                        add(c, d)
                    if (phase & 1) == 0:
                        add(a, c)
                        add(b, d)
                    add(a, d)
                    add(b, c)

        expected: set[tuple[tuple[int, int], tuple[int, int]]] = set()
        for y in range(logical_height):
            for x in range(logical_width):
                for dx, dy in ((1, 0), (0, 1), (1, 1), (-1, 1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < logical_width and 0 <= ny < logical_height:
                        expected.add(edge((x, y), (nx, ny)))

        check(set(counts) == expected,
              f"XPBD phases must cover every 8-neighbour edge for {logical_width}x{logical_height}")
        duplicates = [edge_key for edge_key, count in counts.items() if count != 1]
        check(not duplicates,
              f"XPBD neighbour edges must be solved exactly once for {logical_width}x{logical_height}: {duplicates[:4]}")

    # Even and odd logical grids exercise both ordinary blocks and the padded
    # final row/column used by the D3D11 textures.
    for logical_width in range(1, 10):
        for logical_height in range(1, 10):
            validate(logical_width, logical_height)

def test_ca_odd_boundary_schedule() -> None:
    # SandStep uses two Margolus phases shifted by (0,0)/(1,1). Backing
    # dimensions are even, while logical dimensions may be odd. The padded wall
    # must not freeze the final real row/column: all axial neighbour pairs along
    # those odd boundaries must still occur in at least one real-real 2x2 pair.
    def covered_edges(logical_width: int, logical_height: int) -> set[tuple[tuple[int, int], tuple[int, int]]]:
        state_width = logical_width + (logical_width & 1)
        state_height = logical_height + (logical_height & 1)
        result: set[tuple[tuple[int, int], tuple[int, int]]] = set()

        def real(point: tuple[int, int]) -> bool:
            return point[0] < logical_width and point[1] < logical_height

        def add(a: tuple[int, int], b: tuple[int, int]) -> None:
            if real(a) and real(b):
                result.add((a, b) if a <= b else (b, a))

        for phase in (0, 1):
            if logical_width == 1 and logical_height > 1:
                for by in range(state_height // 2):
                    y = by * 2 + phase
                    if y + 1 < logical_height:
                        add((0, y), (0, y + 1))
                continue
            if logical_height == 1 and logical_width > 1:
                for bx in range(state_width // 2):
                    x = bx * 2 + phase
                    if x + 1 < logical_width:
                        add((x, 0), (x + 1, 0))
                continue

            for by in range(state_height // 2):
                for bx in range(state_width // 2):
                    x = bx * 2 + phase
                    y = by * 2 + phase
                    if x + 1 >= state_width or y + 1 >= state_height:
                        continue
                    a = (x, y)
                    b = (x + 1, y)
                    c = (x, y + 1)
                    d = (x + 1, y + 1)
                    add(a, b)
                    add(c, d)
                    add(a, c)
                    add(b, d)
        return result

    def written_cells(logical_width: int, logical_height: int, phase: int) -> list[tuple[int, int]]:
        state_width = logical_width + (logical_width & 1)
        state_height = logical_height + (logical_height & 1)
        block_width = state_width // 2
        block_height = state_height // 2
        writes: list[tuple[int, int]] = []

        def write(x: int, y: int) -> None:
            if 0 <= x < logical_width and 0 <= y < logical_height:
                writes.append((x, y))

        if logical_width == 1 and logical_height == 1:
            write(0, 0)
            return writes
        if logical_width == 1:
            for by in range(block_height):
                y = by * 2 + phase
                if phase and by == 0:
                    write(0, 0)
                if y >= logical_height:
                    continue
                if y + 1 >= logical_height:
                    write(0, y)
                else:
                    write(0, y)
                    write(0, y + 1)
            return writes
        if logical_height == 1:
            for bx in range(block_width):
                x = bx * 2 + phase
                if phase and bx == 0:
                    write(0, 0)
                if x >= logical_width:
                    continue
                if x + 1 >= logical_width:
                    write(x, 0)
                else:
                    write(x, 0)
                    write(x + 1, 0)
            return writes

        for by in range(block_height):
            for bx in range(block_width):
                if phase:
                    y = by * 2
                    if bx == 0:
                        write(0, y)
                        write(0, y + 1)
                    if bx + 1 == block_width:
                        write(state_width - 1, y)
                        write(state_width - 1, y + 1)
                    x = bx * 2 + 1
                    if x + 1 < state_width - 1:
                        if by == 0:
                            write(x, 0)
                            write(x + 1, 0)
                        if by + 1 == block_height:
                            write(x, state_height - 1)
                            write(x + 1, state_height - 1)

                x = bx * 2 + phase
                y = by * 2 + phase
                if x + 1 >= state_width or y + 1 >= state_height:
                    continue
                write(x, y)
                write(x + 1, y)
                write(x, y + 1)
                write(x + 1, y + 1)
        return writes

    for logical_width in range(1, 10):
        for logical_height in range(1, 10):
            for phase in (0, 1):
                writes = written_cells(logical_width, logical_height, phase)
                expected_cells = {(x, y) for y in range(logical_height) for x in range(logical_width)}
                check(set(writes) == expected_cells,
                      f"CA phase {phase} must write every real cell for {logical_width}x{logical_height}")
                check(len(writes) == len(expected_cells),
                      f"CA phase {phase} must not write any real cell twice for {logical_width}x{logical_height}")

            edges = covered_edges(logical_width, logical_height)
            if logical_width & 1 and logical_width > 0:
                x = logical_width - 1
                for y in range(max(logical_height - 1, 0)):
                    edge = tuple(sorted(((x, y), (x, y + 1))))
                    check(edge in edges,
                          f"CA odd final column must keep vertical motion for {logical_width}x{logical_height}: {edge}")
            if logical_height & 1 and logical_height > 0:
                y = logical_height - 1
                for x in range(max(logical_width - 1, 0)):
                    edge = tuple(sorted(((x, y), (x + 1, y))))
                    check(edge in edges,
                          f"CA odd final row must keep horizontal motion for {logical_width}x{logical_height}: {edge}")



def test_fxc_definite_assignment_contract() -> None:
    for shader_name in ("SandExplosionUpdate.hlsl", "SandLightSeed.hlsl"):
        text = (SHADERS / shader_name).read_text(encoding="utf-8")
        body = extract_hlsl_function(text, "uint MaterialAt(")
        check("uint material = GetMaterial(" in body,
              f"{shader_name}: MaterialAt must initialize its return value before conditional rigid override")
        check("return GetMaterial(" not in body and body.count("return material;") == 1,
              f"{shader_name}: MaterialAt must use one definite-assignment return for FXC /WX")

    # RWTexture2D has no mip coordinate. FXC accepts an int3 by truncating it to int2,
    # but /WX promotes X3206 to a build error. Require indexing/int2 loads for UAVs.
    for shader_path in SHADERS.glob("*.hlsl"):
        text = shader_path.read_text(encoding="utf-8")
        rw_names = re.findall(r"RWTexture2D<[^>]+>\s+(\w+)\s*:", text)
        for rw_name in rw_names:
            check(re.search(rf"\b{re.escape(rw_name)}\.Load\(\s*int3\(", text) is None,
                  f"{shader_path.name}: {rw_name}.Load must use an int2 coordinate or [] indexing for FXC /WX")

def test_gpu_memory_guard() -> None:
    settings = (PRODUCT / "SandSimulationSettings.cs").read_text(encoding="utf-8")
    processor = (PRODUCT / "SandSimulationEffectProcessor.cs").read_text(encoding="utf-8")
    gpu = (PRODUCT / "SandSimulationGpu.cs").read_text(encoding="utf-8")
    translations = read_translations()
    check("MaximumSimulationStateBytes = 318_767_104" in settings,
          "GPU simulation state budget must remain capped at ~304 MiB")
    for name, value in (("CellularStateBytesPerCell", 16), ("RigidStateBytesPerCell", 52),
                        ("ExplosionStateBytesPerCell", 8), ("LightingStateBytesPerCell", 8)):
        check(f"{name} = {value}" in settings, f"missing per-feature memory cost: {name}")
    check("GetSimulationStateBytesPerCell" in settings and
          "stateWidth * stateHeight * bytesPerCell <= MaximumSimulationStateBytes" in settings,
          "simulation-size guard must charge only enabled feature buffers")
    check("solidPhysicsEnabled" in processor and "explosionEnabled" in processor and "lightingEnabled" in processor and
          "IsSimulationSizeSupported(" in processor,
          "processor must compute feature-aware memory requirements before allocation")
    check("solidPhysicsEnabled" in gpu and "explosionEnabled" in gpu and "lightingEnabled" in gpu and
          "IsSimulationSizeSupported(" in gpu,
          "GPU allocator must defensively repeat the feature-aware byte-budget guard")
    particle_description = translations["ParticleSize_Desc"]["ja-jp"]
    check("状態予算は約304 MiB" in particle_description and "CAのみ約32 MiB" in particle_description,
          "particle-size UI must explain the feature-aware memory budget")

def test_parameter_range_contract() -> None:
    settings = (PRODUCT / "SandSimulationSettings.cs").read_text(encoding="utf-8")
    effect = (PRODUCT / "SandSimulationEffect.cs").read_text(encoding="utf-8")
    expected_constants = {
        "PositionSliderMinimum = -500.0": "position slider minimum",
        "PositionSliderMaximum = 500.0": "position slider maximum",
        "PercentMultiplierSliderMinimum = 0.0": "percent multiplier slider minimum",
        "PercentMultiplierSliderMaximum = 400.0": "percent multiplier slider maximum",
        "PositiveAnimationMinimum = 0.0": "non-negative animation minimum",
        "SignedAnimationMinimum = -100_000.0": "signed animation minimum",
        "AnimationMaximum = 100_000.0": "shared animation maximum",
    }
    for token, label in expected_constants.items():
        check(token in settings, f"missing VTuberKit-compatible {label}")

    slider_contract = (
        'AnimationSlider("F1", "px", SandSimulationSettings.PositionSliderMinimum, '
        "SandSimulationSettings.PositionSliderMaximum)"
    )
    check(effect.count(slider_contract) == 2,
          "ExplosionX/Y must share the VTuberKit-compatible position slider range")
    check(effect.count("SandSimulationSettings.SignedAnimationMinimum") == 2,
          "the two signed ExplosionX/Y parameters must use the -100000 animation minimum")
    check(effect.count("SandSimulationSettings.PositiveAnimationMinimum") == 17,
          "all 17 non-negative parameters must use the zero animation minimum")
    check(effect.count("SandSimulationSettings.AnimationMaximum") == 19,
          "all 19 animation parameters must use the shared 100000 maximum")
    check("YMM4Constants.VerySmallValue" not in effect and "YMM4Constants.VeryLargeValue" not in effect,
          "position animations must not drift back to unrelated YMM4 sentinel ranges")
    check(re.search(r"new\([^\n]*,\s*-?\d", effect) is None,
          "animation constructors must not use ad-hoc literal storage ranges")

    percent_slider_contract = (
        'AnimationSlider("F1", "%", SandSimulationSettings.PercentMultiplierSliderMinimum, '
        "SandSimulationSettings.PercentMultiplierSliderMaximum)"
    )
    check(effect.count(percent_slider_contract) == 6,
          "all six multiplier controls must share the 0..400 percent initial range")
    check("25, SandSimulationSettings.PercentMultiplierSliderMaximum" not in effect,
          "stiffness and break strength must expose a real 0 percent value instead of a hidden 25 percent floor")
    processor = (PRODUCT / "SandSimulationEffectProcessor.cs").read_text(encoding="utf-8")
    check(processor.count("ClampFiniteAtLeast(") >= 6 and
          "MaximumNormalizedPercentMultiplier" not in processor,
          "percentage multipliers must keep their semantic minimum without a hidden runtime upper clamp")
    check("ExplosionRadius: RoundAtLeast(" in processor and "MaximumExplosionRadius" not in processor,
          "explosion radius must preserve typed pixel values without a hidden runtime upper clamp")
    check("ExplosionX: FiniteOrZero(" in processor and "ExplosionY: FiniteOrZero(" in processor and
          "MaximumCanvasSize" not in processor[processor.find("ExplosionX:"):processor.find("ExplosionTriggerFrame:")],
          "explosion center must remain signed/off-screen instead of clamping to the canvas edge")

def test_ymm4_ui_terminology_contract() -> None:
    effect = (PRODUCT / "SandSimulationEffect.cs").read_text(encoding="utf-8")
    mask_mode = (PRODUCT / "SandMaskMode.cs").read_text(encoding="utf-8")
    translation_text = TRANSLATIONS.read_text(encoding="utf-8")
    translations = read_translations()
    required_japanese = {
        "Group_Basic": "基本",
        "Group_Explosion": "爆発",
        "Group_Lighting": "照明",
        "ScreenSize_Name": "画面サイズ",
        "ParticleSize_Name": "粒サイズ",
        "Iterations_Name": "更新回数",
        "Warmup_Name": "初期更新回数",
        "ReactionStrength_Name": "反応の強さ",
        "BreakStrength_Name": "破断の強さ",
        "SolverIterations_Name": "反復回数",
        "ExplosionController_Name": "制御点",
        "ExplosionX_Name": "中心X",
        "ExplosionY_Name": "中心Y",
        "ExplosionStrength_Name": "強さ",
        "ExplosionRadius_Name": "半径",
        "LightingStrength_Name": "光の強さ",
        "LightingRadius_Name": "半径",
        "AmbientLight_Name": "環境光",
        "AlphaThreshold_Name": "不透明度の閾値",
        "LuminanceThreshold_Name": "輝度の閾値",
    }
    for key, expected in required_japanese.items():
        check(translations[key]["ja-jp"] == expected, f"YMM4 UI terminology drifted: {key}")
        check(f"nameof(Translate.{key})" in effect,
              f"effect metadata must resolve {key} through generated localization")
    check('AnimationSlider("F0", "フ", 0, 36000)' in effect,
          "frame slider must retain YMM4's short Japanese frame unit")
    check("nameof(Translate.Plugin_Name)" in effect and
          "[VideoEffectCategories.Filtering]" in effect and
          "ResourceType = typeof(Translate)" in effect,
          "video effect name and YMM4 processing category must use their multilingual resource keys")
    for obsolete in ("適用量", "爆心コントローラ", 'Name = "爆心X"', 'Name = "爆心Y"',
                     'GroupName = "ライティング"', 'Name = "アルファ閾値"', 'Name = "輝度閾値"'):
        check(obsolete not in effect and obsolete not in translation_text,
              f"obsolete non-YMM4 UI term remains: {obsolete}")
    check("nameof(Translate.MaskMode_Alpha)" in mask_mode and
          "nameof(Translate.MaskMode_Both)" in mask_mode,
          "alpha extraction labels must use YMM4's user-facing opacity terminology")
    check("Order =" not in effect,
          "effect parameter UI order must follow source declaration order without Display.Order")
    check(re.search(r"public bool IsScreenSize[\s\S]*?private bool _isScreenSize;", effect) is not None and
          "nameof(Translate.ScreenSize_Name)" in effect and "[ToggleSlider]" in effect,
          "screen-size rendering must be a localized toggle that defaults off")
    processor = (PRODUCT / "SandSimulationEffectProcessor.cs").read_text(encoding="utf-8")
    check("effectDescription.ScreenSize.Width" in processor and
          "effectDescription.ScreenSize.Height" in processor and
          "var left = -width / 2f;" in processor and
          "var top = -height / 2f;" in processor and
          "new Vector2(left, top)" in processor and
          "new Vortice.RawRectF(left, top, left + width, top + height)" in processor and
          "IsScreenSize == other.IsScreenSize" in processor,
          "screen-size mode must center the screen canvas on YMM4's item-local origin and invalidate state when toggled")

def test_release_and_localization_contract() -> None:
    targets = (ROOT / "Directory.Build.targets").read_text(encoding="utf-8")
    csproj = (PRODUCT / "YMM4SandSim.csproj").read_text(encoding="utf-8")
    plugin_log = (PRODUCT / "Diagnostics" / "PluginLog.cs").read_text(encoding="utf-8")
    workflow = (ROOT / ".github" / "workflows" / "build.yml").read_text(encoding="utf-8")
    package_script = (ROOT / "scripts" / "dev.ps1").read_text(encoding="utf-8")
    translations = read_translations()

    check(targets.count("<YMM4SandSimVersion>") == 1 and
          "<Version>$(YMM4SandSimVersion)</Version>" in targets,
          "release version must have one source in Directory.Build.targets")
    check("<Version>" not in csproj,
          "project file must not duplicate the release version")
    check("bypassMinimumLevel: true" in plugin_log and
          "Environment.GetEnvironmentVariable(LogLevelEnvironmentVariable)" in plugin_log and
          "#else\n        return PluginLogLevel.Error;\n#endif" in plugin_log,
          "Release logging must keep errors by default while allowing explicit support/performance opt-in")
    check("YMM4SandSimVersion" in workflow and "Tag/version mismatch" in workflow,
          "release workflow must read and validate the shared version")
    check("submodules: recursive" in workflow,
          "release checkout must initialize the localization generator submodule")
    check(".\\scripts\\dev.ps1 test" not in workflow and ".\\scripts\\dev.ps1 publish" in workflow,
          "release workflow must package through the unified script without rerunning local-only tests")
    check('$baseName = "YMM4SandSim-v$version"' in package_script and
          "YMM4SandSim/YMM4SandSim.dll" in package_script and
          "CreateFromDirectory" in package_script,
          "package script must create and validate the ymme-in-ZIP distribution")
    check((ROOT / "packaging" / "Readme.txt").is_file() and
          'Join-Path $root "packaging\\Readme.txt"' in package_script and
          'Join-Path $packageRoot "Readme.txt"' in package_script,
          "repository must put the shared packaging readme in the ymme")
    check("Unexpected files were found in ymme" in package_script and
          r"YMM4SandSim\.resources\.dll" in package_script and
          r"YMM4SandSim/LICENSES/[^/]+\.txt" in package_script,
          "ymme validation must reject files other than the plugin, translations, readme, and licenses")
    check("YukkuriMovieMaker.Generator.csproj" in csproj and
          'AdditionalFiles Include="Localization\\**\\*.csv"' in csproj,
          "localization generator must consume the translation CSV")
    for key, row in translations.items():
        check(row["ja-jp"].strip() and row["en-us"].strip(),
              f"translation row must contain Japanese and English: {key}")

def test_local_build_configuration_contract() -> None:
    gitignore = (ROOT / ".gitignore").read_text(encoding="utf-8")
    sample = (ROOT / "Directory.Build.props.sample").read_text(encoding="utf-8")
    build_script = (ROOT / "scripts" / "dev.ps1").read_text(encoding="utf-8")

    check("/Directory.Build.props" in gitignore,
          "machine-local Directory.Build.props must be ignored at repository root")
    check("<YMM4DirPath>PATH_TO_YMM4\\</YMM4DirPath>" in sample,
          "Directory.Build.props.sample must document a non-machine-specific YMM4 path")
    check("<FxcPath>PATH_TO_FXC_EXE</FxcPath>" in sample and
          "<DotnetPath>PATH_TO_DOTNET_EXE</DotnetPath>" in sample and
          "<PythonPath>PATH_TO_PYTHON_EXE</PythonPath>" in sample,
          "Directory.Build.props.sample must expose all local tool-path properties without real machine paths")
    check(re.search(r"[A-Za-z]:\\", sample) is None,
          "Directory.Build.props.sample must not contain an absolute drive path")
    for token in ("Get-BuildProperty", '"YMM4DirPath"', '"FxcPath"', '"DotnetPath"', '"PythonPath"'):
        check(token in build_script, f"portable build settings missing from dev.ps1: {token}")
    check("dotnet" in build_script and "MSBuild.exe" not in build_script,
          "repository build must not depend on a machine-specific MSBuild.exe location")
    check('"-p:FxcPath=$fxc"' in build_script,
          "resolved FXC path must be forwarded to the plugin build")
    check('"-p:YMM4SandSimShaderOptimization=$Optimization"' in build_script and
          build_script.count('Invoke-PluginBuild -Deploy -Optimization Release') >= 2,
          "normal and publish builds must use final shader optimization")
    check("$null = $process.Handle" in build_script,
          "Windows PowerShell must retain the FXC process handle so ExitCode is available")
    check('-p:SkipShaderCompilation=true' in build_script,
          "xUnit test builds must skip shader compilation")

    test_project = (ROOT / "YMM4SandSim.Tests" / "YMM4SandSim.Tests.csproj").read_text(encoding="utf-8")
    plugin_project = (PRODUCT / "YMM4SandSim.csproj").read_text(encoding="utf-8")
    check("SkipShaderCompilation" in plugin_project and
          "Condition=\"'$(SkipShaderCompilation)' != 'true'\"" in plugin_project,
          "plugin project must omit shader generation and embedding only for C#-only tests")
    check('Compile Remove="ShaderBytecodeTests.cs"' in test_project and
          "'$(SkipShaderCompilation)' == 'true'" in test_project,
          "bytecode-dependent tests must be excluded when shaders are intentionally absent")
    lint_function = re.search(r"function Invoke-Lint\s*\{(.*?)\r?\n\}", build_script, re.DOTALL)
    check(lint_function is not None and "dotnet build" not in lint_function.group(1),
          "lint must remain a non-build style/analyzer check")

    public_ci = (ROOT / ".github" / "workflows" / "public-ci.yml").read_text(encoding="utf-8")
    check(".\\scripts\\dev.ps1 fmt -Verify" in public_ci and ".\\scripts\\dev.ps1 lint" in public_ci,
          "public CI must run formatting and lint checks")
    check("dotnet build" not in public_ci and ".\\scripts\\dev.ps1 test" not in public_ci and
          ".\\scripts\\dev.ps1 publish" not in public_ci,
          "public CI must not build, test, compile shaders, or publish")


def test_optimization_contract() -> None:
    gpu = (PRODUCT / "SandSimulationGpu.cs").read_text(encoding="utf-8")
    processor = (PRODUCT / "SandSimulationEffectProcessor.cs").read_text(encoding="utf-8")
    propagate = (SHADERS / "SandLightPropagate.hlsl").read_text(encoding="utf-8")
    common = (SHADERS / "SandCommon.hlsli").read_text(encoding="utf-8")

    check("float4 MaterialColor(uint material)" in common,
          "material color lookup must not carry dead age/variant parameters")
    check("_explosionPressureDirty" in gpu and "else if (_explosionPressureDirty)" in gpu,
          "disabled explosions must stop full-grid pressure dispatches after one transition clear")
    check("parameters.ReactionStrength > 0.0f" in gpu,
          "reaction-disabled XPBD must skip the rigid chemistry/promote pass and occupancy rebuild")
    check("_gpu.Render(in gpuParameters);" in processor and "parameters.Amount" not in processor,
          "simulation output must render directly without a source-blend amount")
    check("Texture2D<uint> SourceLight : register(t0);" in propagate and "register(t1)" not in propagate,
          "light propagation hot path must consume only the packed light/transmission texture")
    check("EnsureRigidResources();" in gpu and "ReleaseRigidResources();" in gpu and
          "EnsureExplosionResources()" in gpu and "ReleaseExplosionResources();" in gpu and
          "EnsureLightResources();" in gpu and "ReleaseLightResources();" in gpu,
          "optional XPBD/explosion/light resources must be allocated and released independently")
    check("_rigidSolveConstantBuffers" in gpu and
          "UpdateConstants(_rigidSolveConstantBuffers[phase], in constants);" in gpu and
          "_context.CSSetConstantBuffer(0, _rigidSolveConstantBuffers[phase]);" in gpu,
          "XPBD phases must reuse precomputed constants across solver iterations")
    check("solidPhysicsEnabled" in gpu and "explosionEnabled" in gpu and "lightingEnabled" in gpu,
          "resource policy must follow the enabled feature set instead of allocating worst-case state unconditionally")
    check("CreatePhysicsTexture(Format.R32G32B32A32_Float, _stateWidth, _stateHeight)" in gpu and
          "CreatePhysicsTexture(Format.R32_Float, _stateWidth, _stateHeight)" in gpu and
          "CreatePhysicsTexture(Format.R32_UInt, _stateWidth, _stateHeight)" in gpu,
          "optional resource helpers must keep the established D3D11-compatible formats")
    components_start = gpu.find("private void BuildRigidComponents(")
    components_end = gpu.find("private void BuildRigidOccupancy(", components_start)
    check(components_start >= 0 and components_end > components_start, "BuildRigidComponents method missing")
    components_body = gpu[components_start:components_end]
    check(components_body.count("CSSetShader(_rigidComponentsShader)") == 1 and
          components_body.count("CSSetShaderResource(0, rigidMetaSrv)") == 1 and
          components_body.count("CSSetUnorderedAccessView(0, rigidBodyLabelUav)") == 1 and
          components_body.count("UnbindComputeViews()") == 1,
          "connected-component rounds must keep invariant D3D11 state bound instead of rebinding every dispatch")
    check("DiagnosticSampleWindow = 120" in gpu and "avgDispatches=" in gpu and
          "CPU submit time is not GPU execution time" in gpu and "_context.Dispatch(" in gpu,
          "performance diagnostics must report dispatch counts/CPU submit time without pretending to measure GPU time")
    start = gpu.find("private void BuildLighting(")
    end = gpu.find("private void ReactRigid(", start)
    check(start >= 0 and end > start, "BuildLighting method missing")
    body = gpu[start:end]
    check("ResetExplosionPressure(ref constants)" not in body,
          "lighting must never clear the stateful explosion pressure field")
    loop = body[body.find("for (var pass"):]
    check("CSSetShaderResource(1" not in loop and "CSSetShaderResource(2" not in loop and "CSSetShaderResource(3" not in loop,
          "host must not bind material/occupancy SRVs during repeated light propagation passes")



def test_documentation_contract() -> None:
    readme = (ROOT / "README.md").read_text(encoding="utf-8")
    design = (ROOT / "docs" / "GPU_SOLID_PHYSICS.md").read_text(encoding="utf-8")
    for heading in ("## インストール方法", "## 使い方", "## 動作環境", "## 開発者向け", "## ライセンス", "## 謝辞"):
        check(heading in readme, f"README missing user/developer structure: {heading}")
    check(readme.index("## 使い方") < readme.index("## 開発者向け"),
          "README must present user documentation before developer internals")
    check("主な変更" not in readme and "アップデート" not in readme,
          "initial v1.0.0 README must not contain an update-history section")
    check("GPU Connected Components" in design and "異素材間にはXPBD bondを張りません" in design and
          "timestamp query" in design and "84 byte/cell" in design,
          "GPU solid-physics design must match connected bodies, material separation, profiling, and memory layout")
    check("YMM4SANDSIM_LOG_LEVEL=Information" in design and "cpuSubmitMs" in design and
          "GPU実行時間ではありません" in design,
          "performance diagnostics belong in the technical design document")
    for stale in ("XPBDは44 byte/cell", "全機能有効時は76 byte/cell", "約150.3 MiB"):
        check(stale not in readme and stale not in design, f"stale documentation remains: {stale}")

def main() -> None:
    entries = test_manifest()
    test_material_enum(entries)
    test_shader_material_contract(entries)
    test_behavior_class_masks(entries)
    test_material_behavior_parameters(entries)
    test_initialize_and_step()
    test_shader_build_list()
    test_timeline_policy_contract()
    test_constant_buffer_layout()
    test_multi_instance_graph_and_context_contract()
    test_gpu_memory_guard()
    test_parameter_range_contract()
    test_ymm4_ui_terminology_contract()
    test_release_and_localization_contract()
    test_local_build_configuration_contract()
    test_fxc_definite_assignment_contract()
    test_gpu_xpbd_contract()
    test_explosion_and_lighting_contract()
    test_optimization_contract()
    test_documentation_contract()
    test_xpbd_phase_schedule()
    test_ca_odd_boundary_schedule()
    print("YMM4-SandSim static contract tests passed.")

if __name__ == "__main__":
    main()
