#ifndef YMM4_SAND_COMMON_HLSLI
#define YMM4_SAND_COMMON_HLSLI

#include "SandCore.hlsli"

float4 MaterialColor(uint material)
{
    if (material == MaterialSand) return float4(0.972549020f, 0.847058824f, 0.470588235f, 1.0f); // #f8d878
    if (material == MaterialWater) return float4(0.000000000f, 0.470588235f, 0.972549020f, 1.0f); // #0078f8
    if (material == MaterialSalt) return float4(0.972549020f, 0.972549020f, 0.972549020f, 1.0f); // #f8f8f8
    if (material == MaterialWood) return float4(0.533333333f, 0.078431373f, 0.000000000f, 1.0f); // #881400
    if (material == MaterialFire) return float4(0.894117647f, 0.360784314f, 0.062745098f, 1.0f); // #e45c10
    if (material == MaterialSmoke) return float4(0.470588235f, 0.470588235f, 0.470588235f, 1.0f); // #787878
    if (material == MaterialSteam) return float4(0.643137255f, 0.894117647f, 0.988235294f, 1.0f); // #a4e4fc
    if (material == MaterialOil) return float4(0.000000000f, 0.250980392f, 0.345098039f, 1.0f); // #004058
    if (material == MaterialLava) return float4(0.972549020f, 0.219607843f, 0.000000000f, 1.0f); // #f83800
    if (material == MaterialStone) return float4(0.486274510f, 0.486274510f, 0.486274510f, 1.0f); // #7c7c7c
    if (material == MaterialAcid) return float4(0.847058824f, 0.000000000f, 0.800000000f, 1.0f); // #d800cc
    if (material == MaterialSandstone) return float4(0.941176471f, 0.815686275f, 0.690196078f, 1.0f); // #f0d0b0
    if (material == MaterialSnow) return float4(0.988235294f, 0.988235294f, 0.988235294f, 1.0f); // #fcfcfc
    if (material == MaterialCoal) return float4(0.000000000f, 0.000000000f, 0.000000000f, 1.0f); // #000000
    if (material == MaterialMetal) return float4(0.737254902f, 0.737254902f, 0.737254902f, 1.0f); // #bcbcbc
    if (material == MaterialBrick) return float4(0.658823529f, 0.000000000f, 0.125490196f, 1.0f); // #a80020
    if (material == MaterialAmethyst) return float4(0.596078431f, 0.470588235f, 0.972549020f, 1.0f); // #9878f8
    if (material == MaterialPlant) return float4(0.000000000f, 0.721568627f, 0.000000000f, 1.0f); // #00b800
    if (material == MaterialSlime) return float4(0.721568627f, 0.972549020f, 0.094117647f, 1.0f); // #b8f818
    if (material == MaterialSoil) return float4(0.313725490f, 0.188235294f, 0.000000000f, 1.0f); // #503000
    if (material == MaterialInk) return float4(0.000000000f, 0.000000000f, 0.737254902f, 1.0f); // #0000bc
    if (material == MaterialOxidizedCopper) return float4(0.000000000f, 0.658823529f, 0.266666667f, 1.0f); // #00a844
    if (material == MaterialIce) return float4(0.000000000f, 0.988235294f, 0.988235294f, 1.0f); // #00fcfc
    if (material == MaterialLiquidNitrogen) return float4(0.235294118f, 0.737254902f, 0.988235294f, 1.0f); // #3cbcfc
    if (material == MaterialLapisLazuli) return float4(0.000000000f, 0.000000000f, 0.988235294f, 1.0f); // #0000fc
    if (material == MaterialPermafrost) return float4(0.721568627f, 0.721568627f, 0.972549020f, 1.0f); // #b8b8f8
    if (material == MaterialCobaltGlass) return float4(0.407843137f, 0.533333333f, 0.988235294f, 1.0f); // #6888fc
    if (material == MaterialAzurite) return float4(0.000000000f, 0.345098039f, 0.972549020f, 1.0f); // #0058f8
    if (material == MaterialFluorite) return float4(0.847058824f, 0.721568627f, 0.972549020f, 1.0f); // #d8b8f8
    if (material == MaterialPurpur) return float4(0.407843137f, 0.266666667f, 0.988235294f, 1.0f); // #6844fc
    if (material == MaterialCharoite) return float4(0.266666667f, 0.156862745f, 0.737254902f, 1.0f); // #4428bc
    if (material == MaterialRoseQuartz) return float4(0.972549020f, 0.721568627f, 0.972549020f, 1.0f); // #f8b8f8
    if (material == MaterialPinkWax) return float4(0.972549020f, 0.470588235f, 0.972549020f, 1.0f); // #f878f8
    if (material == MaterialPotassiumPermanganate) return float4(0.580392157f, 0.000000000f, 0.517647059f, 1.0f); // #940084
    if (material == MaterialCoral) return float4(0.972549020f, 0.643137255f, 0.752941176f, 1.0f); // #f8a4c0
    if (material == MaterialPinkSalt) return float4(0.972549020f, 0.345098039f, 0.596078431f, 1.0f); // #f85898
    if (material == MaterialRuby) return float4(0.894117647f, 0.000000000f, 0.345098039f, 1.0f); // #e40058
    if (material == MaterialCopper) return float4(0.972549020f, 0.470588235f, 0.345098039f, 1.0f); // #f87858
    if (material == MaterialRust) return float4(0.658823529f, 0.062745098f, 0.000000000f, 1.0f); // #a81000
    if (material == MaterialCalcite) return float4(0.988235294f, 0.878431373f, 0.658823529f, 1.0f); // #fce0a8
    if (material == MaterialAmber) return float4(0.988235294f, 0.627450980f, 0.266666667f, 1.0f); // #fca044
    if (material == MaterialSulfur) return float4(0.972549020f, 0.721568627f, 0.000000000f, 1.0f); // #f8b800
    if (material == MaterialGold) return float4(0.674509804f, 0.486274510f, 0.000000000f, 1.0f); // #ac7c00
    if (material == MaterialEndStone) return float4(0.847058824f, 0.972549020f, 0.470588235f, 1.0f); // #d8f878
    if (material == MaterialMoss) return float4(0.000000000f, 0.470588235f, 0.000000000f, 1.0f); // #007800
    if (material == MaterialJade) return float4(0.721568627f, 0.972549020f, 0.721568627f, 1.0f); // #b8f8b8
    if (material == MaterialGrass) return float4(0.345098039f, 0.847058824f, 0.329411765f, 1.0f); // #58d854
    if (material == MaterialAlgae) return float4(0.000000000f, 0.658823529f, 0.000000000f, 1.0f); // #00a800
    if (material == MaterialLeaf) return float4(0.000000000f, 0.407843137f, 0.000000000f, 1.0f); // #006800
    if (material == MaterialSeaLantern) return float4(0.721568627f, 0.972549020f, 0.847058824f, 1.0f); // #b8f8d8
    if (material == MaterialVerdigris) return float4(0.345098039f, 0.972549020f, 0.596078431f, 1.0f); // #58f898
    if (material == MaterialPineNeedles) return float4(0.000000000f, 0.345098039f, 0.000000000f, 1.0f); // #005800
    if (material == MaterialPrismarine) return float4(0.000000000f, 0.909803922f, 0.847058824f, 1.0f); // #00e8d8
    if (material == MaterialSeaWater) return float4(0.000000000f, 0.533333333f, 0.533333333f, 1.0f); // #008888
    if (material == MaterialQuartz) return float4(0.972549020f, 0.847058824f, 0.972549020f, 1.0f); // #f8d8f8
    if (material == MaterialEmber) return float4(0.784313725f, 0.470588235f, 0.078431373f, 1.0f);
    if (material == MaterialGunpowder) return float4(0.235294118f, 0.235294118f, 0.235294118f, 1.0f);
    return 0.0f;
}

float3 SrgbToLinear(float3 color)
{
    const float3 low = color / 12.92f;
    const float3 high = pow((color + 0.055f) / 1.055f, 2.4f);
    return lerp(low, high, step(float3(0.04045f, 0.04045f, 0.04045f), color));
}

float3 LinearRgbToOklab(float3 color)
{
    const float3 lms = mul(float3x3(
        0.4122214708f, 0.5363325363f, 0.0514459929f,
        0.2119034982f, 0.6806995451f, 0.1073969566f,
        0.0883024619f, 0.2817188376f, 0.6299787005f), color);
    const float3 root = sign(lms) * pow(abs(lms), 1.0f / 3.0f);
    return mul(float3x3(
        0.2104542553f, 0.7936177850f, -0.0040720468f,
        1.9779984951f, -2.4285922050f, 0.4505937099f,
        0.0259040371f, 0.7827717662f, -0.8086757660f), root);
}

float3 SrgbToOklab(float3 color)
{
    return LinearRgbToOklab(SrgbToLinear(saturate(color)));
}

void ConsiderPaletteMaterial(float3 sourceLab, float3 referenceLab, uint candidate, inout float bestDistance, inout uint bestMaterial)
{
    const float3 difference = sourceLab - referenceLab;
    const float distance = dot(difference, difference);
    if (distance < bestDistance)
    {
        bestDistance = distance;
        bestMaterial = candidate;
    }
}

uint ClosestMaterialFromColor(float3 color)
{
    const float3 lab = SrgbToOklab(color);
    float bestDistance = 1e20f;
    uint bestMaterial = MaterialCoal;

    // User-specified 55-color Famicom palette. Every anchor maps to one
    // distinct primitive material. Ember and gunpowder remain support-only.
    ConsiderPaletteMaterial(lab, float3(0.000000000f, 0.000000000f, 0.000000000f), MaterialCoal, bestDistance, bestMaterial); // #000000
    ConsiderPaletteMaterial(lab, float3(0.991068897f, 0.000000000f, 0.000000037f), MaterialSnow, bestDistance, bestMaterial); // #fcfcfc
    ConsiderPaletteMaterial(lab, float3(0.979129350f, 0.000000000f, 0.000000036f), MaterialSalt, bestDistance, bestMaterial); // #f8f8f8
    ConsiderPaletteMaterial(lab, float3(0.795224913f, 0.000000000f, 0.000000030f), MaterialMetal, bestDistance, bestMaterial); // #bcbcbc
    ConsiderPaletteMaterial(lab, float3(0.586316464f, 0.000000000f, 0.000000022f), MaterialStone, bestDistance, bestMaterial); // #7c7c7c
    ConsiderPaletteMaterial(lab, float3(0.883931661f, -0.052722539f, -0.049562751f), MaterialSteam, bestDistance, bestMaterial); // #a4e4fc
    ConsiderPaletteMaterial(lab, float3(0.753987036f, -0.080465184f, -0.116886775f), MaterialLiquidNitrogen, bestDistance, bestMaterial); // #3cbcfc
    ConsiderPaletteMaterial(lab, float3(0.593359639f, -0.047228989f, -0.206040151f), MaterialWater, bestDistance, bestMaterial); // #0078f8
    ConsiderPaletteMaterial(lab, float3(0.447976740f, -0.032167108f, -0.308745860f), MaterialLapisLazuli, bestDistance, bestMaterial); // #0000fc
    ConsiderPaletteMaterial(lab, float3(0.805340581f, 0.022075120f, -0.087254972f), MaterialPermafrost, bestDistance, bestMaterial); // #b8b8f8
    ConsiderPaletteMaterial(lab, float3(0.659171364f, -0.001494568f, -0.175308880f), MaterialCobaltGlass, bestDistance, bestMaterial); // #6888fc
    ConsiderPaletteMaterial(lab, float3(0.531663748f, -0.034020166f, -0.245812789f), MaterialAzurite, bestDistance, bestMaterial); // #0058f8
    ConsiderPaletteMaterial(lab, float3(0.359452572f, -0.025810603f, -0.247734946f), MaterialInk, bestDistance, bestMaterial); // #0000bc
    ConsiderPaletteMaterial(lab, float3(0.831609618f, 0.056856228f, -0.074912482f), MaterialFluorite, bestDistance, bestMaterial); // #d8b8f8
    ConsiderPaletteMaterial(lab, float3(0.662285482f, 0.069272976f, -0.170201735f), MaterialAmethyst, bestDistance, bestMaterial); // #9878f8
    ConsiderPaletteMaterial(lab, float3(0.547683439f, 0.057371617f, -0.247786621f), MaterialPurpur, bestDistance, bestMaterial); // #6844fc
    ConsiderPaletteMaterial(lab, float3(0.423029808f, 0.040197387f, -0.209164931f), MaterialCharoite, bestDistance, bestMaterial); // #4428bc
    ConsiderPaletteMaterial(lab, float3(0.861275786f, 0.092205281f, -0.061066245f), MaterialRoseQuartz, bestDistance, bestMaterial); // #f8b8f8
    ConsiderPaletteMaterial(lab, float3(0.765170099f, 0.182304327f, -0.116441457f), MaterialPinkWax, bestDistance, bestMaterial); // #f878f8
    ConsiderPaletteMaterial(lab, float3(0.611953414f, 0.243233975f, -0.132404253f), MaterialAcid, bestDistance, bestMaterial); // #d800cc
    ConsiderPaletteMaterial(lab, float3(0.457790343f, 0.184084223f, -0.088490781f), MaterialPotassiumPermanganate, bestDistance, bestMaterial); // #940084
    ConsiderPaletteMaterial(lab, float3(0.808848943f, 0.104580674f, -0.003421999f), MaterialCoral, bestDistance, bestMaterial); // #f8a4c0
    ConsiderPaletteMaterial(lab, float3(0.689888073f, 0.202123338f, -0.002838954f), MaterialPinkSalt, bestDistance, bestMaterial); // #f85898
    ConsiderPaletteMaterial(lab, float3(0.586410989f, 0.229850088f, 0.045902880f), MaterialRuby, bestDistance, bestMaterial); // #e40058
    ConsiderPaletteMaterial(lab, float3(0.461620893f, 0.171486806f, 0.072868846f), MaterialBrick, bestDistance, bestMaterial); // #a80020
    ConsiderPaletteMaterial(lab, float3(0.876509110f, 0.021779789f, 0.051287384f), MaterialSandstone, bestDistance, bestMaterial); // #f0d0b0
    ConsiderPaletteMaterial(lab, float3(0.716256071f, 0.134124070f, 0.094553842f), MaterialCopper, bestDistance, bestMaterial); // #f87858
    ConsiderPaletteMaterial(lab, float3(0.637546315f, 0.193207148f, 0.128167698f), MaterialLava, bestDistance, bestMaterial); // #f83800
    ConsiderPaletteMaterial(lab, float3(0.464881137f, 0.157890546f, 0.093263173f), MaterialRust, bestDistance, bestMaterial); // #a81000
    ConsiderPaletteMaterial(lab, float3(0.916638252f, 0.007694661f, 0.077664369f), MaterialCalcite, bestDistance, bestMaterial); // #fce0a8
    ConsiderPaletteMaterial(lab, float3(0.783280718f, 0.070696524f, 0.133171538f), MaterialAmber, bestDistance, bestMaterial); // #fca044
    ConsiderPaletteMaterial(lab, float3(0.641878979f, 0.135367768f, 0.125942164f), MaterialFire, bestDistance, bestMaterial); // #e45c10
    ConsiderPaletteMaterial(lab, float3(0.403495674f, 0.129047358f, 0.081039145f), MaterialWood, bestDistance, bestMaterial); // #881400
    ConsiderPaletteMaterial(lab, float3(0.889581419f, -0.002941500f, 0.121046406f), MaterialSand, bestDistance, bestMaterial); // #f8d878
    ConsiderPaletteMaterial(lab, float3(0.819590146f, 0.019897132f, 0.167276772f), MaterialSulfur, bestDistance, bestMaterial); // #f8b800
    ConsiderPaletteMaterial(lab, float3(0.617954815f, 0.019211295f, 0.126078316f), MaterialGold, bestDistance, bestMaterial); // #ac7c00
    ConsiderPaletteMaterial(lab, float3(0.340689032f, 0.025427693f, 0.069349513f), MaterialSoil, bestDistance, bestMaterial); // #503000
    ConsiderPaletteMaterial(lab, float3(0.930104298f, -0.081980296f, 0.135420115f), MaterialEndStone, bestDistance, bestMaterial); // #d8f878
    ConsiderPaletteMaterial(lab, float3(0.902553160f, -0.134855970f, 0.182733972f), MaterialSlime, bestDistance, bestMaterial); // #b8f818
    ConsiderPaletteMaterial(lab, float3(0.678078859f, -0.183041285f, 0.140476177f), MaterialPlant, bestDistance, bestMaterial); // #00b800
    ConsiderPaletteMaterial(lab, float3(0.496195521f, -0.133943515f, 0.102795787f), MaterialMoss, bestDistance, bestMaterial); // #007800
    ConsiderPaletteMaterial(lab, float3(0.919939512f, -0.087591798f, 0.062155578f), MaterialJade, bestDistance, bestMaterial); // #b8f8b8
    ConsiderPaletteMaterial(lab, float3(0.783040820f, -0.164579908f, 0.124835979f), MaterialGrass, bestDistance, bestMaterial); // #58d854
    ConsiderPaletteMaterial(lab, float3(0.633882875f, -0.171110976f, 0.131320188f), MaterialAlgae, bestDistance, bestMaterial); // #00a800
    ConsiderPaletteMaterial(lab, float3(0.448211912f, -0.120990771f, 0.092855123f), MaterialLeaf, bestDistance, bestMaterial); // #006800
    ConsiderPaletteMaterial(lab, float3(0.927449423f, -0.074222876f, 0.023108862f), MaterialSeaLantern, bestDistance, bestMaterial); // #b8f8d8
    ConsiderPaletteMaterial(lab, float3(0.872705208f, -0.168755983f, 0.085041161f), MaterialVerdigris, bestDistance, bestMaterial); // #58f898
    ConsiderPaletteMaterial(lab, float3(0.638210627f, -0.156071021f, 0.096584294f), MaterialOxidizedCopper, bestDistance, bestMaterial); // #00a844
    ConsiderPaletteMaterial(lab, float3(0.398904991f, -0.107680812f, 0.082640312f), MaterialPineNeedles, bestDistance, bestMaterial); // #005800
    ConsiderPaletteMaterial(lab, float3(0.897313022f, -0.148109241f, -0.039046289f), MaterialIce, bestDistance, bestMaterial); // #00fcfc
    ConsiderPaletteMaterial(lab, float3(0.837687897f, -0.146105825f, -0.015382459f), MaterialPrismarine, bestDistance, bestMaterial); // #00e8d8
    ConsiderPaletteMaterial(lab, float3(0.567462173f, -0.093664518f, -0.024692935f), MaterialSeaWater, bestDistance, bestMaterial); // #008888
    ConsiderPaletteMaterial(lab, float3(0.348522432f, -0.044103744f, -0.054950265f), MaterialOil, bestDistance, bestMaterial); // #004058
    ConsiderPaletteMaterial(lab, float3(0.918275411f, 0.045468323f, -0.030653652f), MaterialQuartz, bestDistance, bestMaterial); // #f8d8f8
    ConsiderPaletteMaterial(lab, float3(0.572683325f, 0.000000000f, 0.000000021f), MaterialSmoke, bestDistance, bestMaterial); // #787878

    return bestMaterial;
}

#endif
