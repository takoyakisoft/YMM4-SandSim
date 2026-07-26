using System.ComponentModel.DataAnnotations;
using YMM4SandSim.Localization;

namespace YMM4SandSim;

public enum SandMaterial
{
    [Display(Name = nameof(Translate.Material_Sand), ResourceType = typeof(Translate))]
    Sand = 1,

    [Display(Name = nameof(Translate.Material_Water), ResourceType = typeof(Translate))]
    Water = 2,

    [Display(Name = nameof(Translate.Material_Salt), ResourceType = typeof(Translate))]
    Salt = 3,

    [Display(Name = nameof(Translate.Material_Wood), ResourceType = typeof(Translate))]
    Wood = 4,

    [Display(Name = nameof(Translate.Material_Fire), ResourceType = typeof(Translate))]
    Fire = 5,

    [Display(Name = nameof(Translate.Material_Smoke), ResourceType = typeof(Translate))]
    Smoke = 6,

    [Display(Name = nameof(Translate.Material_Ember), ResourceType = typeof(Translate))]
    Ember = 7,

    [Display(Name = nameof(Translate.Material_Steam), ResourceType = typeof(Translate))]
    Steam = 8,

    [Display(Name = nameof(Translate.Material_Gunpowder), ResourceType = typeof(Translate))]
    Gunpowder = 9,

    [Display(Name = nameof(Translate.Material_Oil), ResourceType = typeof(Translate))]
    Oil = 10,

    [Display(Name = nameof(Translate.Material_Lava), ResourceType = typeof(Translate))]
    Lava = 11,

    [Display(Name = nameof(Translate.Material_Stone), ResourceType = typeof(Translate))]
    Stone = 12,

    [Display(Name = nameof(Translate.Material_Acid), ResourceType = typeof(Translate))]
    Acid = 13,

    [Display(Name = nameof(Translate.Material_Sandstone), ResourceType = typeof(Translate))]
    Sandstone = 14,

    [Display(Name = nameof(Translate.Material_Snow), ResourceType = typeof(Translate))]
    Snow = 15,

    [Display(Name = nameof(Translate.Material_Coal), ResourceType = typeof(Translate))]
    Coal = 16,

    [Display(Name = nameof(Translate.Material_Metal), ResourceType = typeof(Translate))]
    Metal = 17,

    [Display(Name = nameof(Translate.Material_Brick), ResourceType = typeof(Translate))]
    Brick = 18,

    [Display(Name = nameof(Translate.Material_Amethyst), ResourceType = typeof(Translate))]
    Amethyst = 19,

    [Display(Name = nameof(Translate.Material_Plant), ResourceType = typeof(Translate))]
    Plant = 20,

    [Display(Name = nameof(Translate.Material_Slime), ResourceType = typeof(Translate))]
    Slime = 21,

    [Display(Name = nameof(Translate.Material_Soil), ResourceType = typeof(Translate))]
    Soil = 22,

    [Display(Name = nameof(Translate.Material_Ink), ResourceType = typeof(Translate))]
    Ink = 23,

    [Display(Name = nameof(Translate.Material_OxidizedCopper), ResourceType = typeof(Translate))]
    OxidizedCopper = 24,

    [Display(Name = nameof(Translate.Material_Ice), ResourceType = typeof(Translate))]
    Ice = 25,

    [Display(Name = nameof(Translate.Material_LiquidNitrogen), ResourceType = typeof(Translate))]
    LiquidNitrogen = 26,

    [Display(Name = nameof(Translate.Material_LapisLazuli), ResourceType = typeof(Translate))]
    LapisLazuli = 27,

    [Display(Name = nameof(Translate.Material_Permafrost), ResourceType = typeof(Translate))]
    Permafrost = 28,

    [Display(Name = nameof(Translate.Material_CobaltGlass), ResourceType = typeof(Translate))]
    CobaltGlass = 29,

    [Display(Name = nameof(Translate.Material_Azurite), ResourceType = typeof(Translate))]
    Azurite = 30,

    [Display(Name = nameof(Translate.Material_Fluorite), ResourceType = typeof(Translate))]
    Fluorite = 31,

    [Display(Name = nameof(Translate.Material_Purpur), ResourceType = typeof(Translate))]
    Purpur = 32,

    [Display(Name = nameof(Translate.Material_Charoite), ResourceType = typeof(Translate))]
    Charoite = 33,

    [Display(Name = nameof(Translate.Material_RoseQuartz), ResourceType = typeof(Translate))]
    RoseQuartz = 34,

    [Display(Name = nameof(Translate.Material_PinkWax), ResourceType = typeof(Translate))]
    PinkWax = 35,

    [Display(Name = nameof(Translate.Material_PotassiumPermanganate), ResourceType = typeof(Translate))]
    PotassiumPermanganate = 36,

    [Display(Name = nameof(Translate.Material_Coral), ResourceType = typeof(Translate))]
    Coral = 37,

    [Display(Name = nameof(Translate.Material_PinkSalt), ResourceType = typeof(Translate))]
    PinkSalt = 38,

    [Display(Name = nameof(Translate.Material_Ruby), ResourceType = typeof(Translate))]
    Ruby = 39,

    [Display(Name = nameof(Translate.Material_Copper), ResourceType = typeof(Translate))]
    Copper = 40,

    [Display(Name = nameof(Translate.Material_Rust), ResourceType = typeof(Translate))]
    Rust = 41,

    [Display(Name = nameof(Translate.Material_Calcite), ResourceType = typeof(Translate))]
    Calcite = 42,

    [Display(Name = nameof(Translate.Material_Amber), ResourceType = typeof(Translate))]
    Amber = 43,

    [Display(Name = nameof(Translate.Material_Sulfur), ResourceType = typeof(Translate))]
    Sulfur = 44,

    [Display(Name = nameof(Translate.Material_Gold), ResourceType = typeof(Translate))]
    Gold = 45,

    [Display(Name = nameof(Translate.Material_EndStone), ResourceType = typeof(Translate))]
    EndStone = 46,

    [Display(Name = nameof(Translate.Material_Moss), ResourceType = typeof(Translate))]
    Moss = 47,

    [Display(Name = nameof(Translate.Material_Jade), ResourceType = typeof(Translate))]
    Jade = 48,

    [Display(Name = nameof(Translate.Material_Grass), ResourceType = typeof(Translate))]
    Grass = 49,

    [Display(Name = nameof(Translate.Material_Algae), ResourceType = typeof(Translate))]
    Algae = 50,

    [Display(Name = nameof(Translate.Material_Leaf), ResourceType = typeof(Translate))]
    Leaf = 51,

    [Display(Name = nameof(Translate.Material_SeaLantern), ResourceType = typeof(Translate))]
    SeaLantern = 52,

    [Display(Name = nameof(Translate.Material_Verdigris), ResourceType = typeof(Translate))]
    Verdigris = 53,

    [Display(Name = nameof(Translate.Material_PineNeedles), ResourceType = typeof(Translate))]
    PineNeedles = 54,

    [Display(Name = nameof(Translate.Material_Prismarine), ResourceType = typeof(Translate))]
    Prismarine = 55,

    [Display(Name = nameof(Translate.Material_SeaWater), ResourceType = typeof(Translate))]
    SeaWater = 56,

    [Display(Name = nameof(Translate.Material_Quartz), ResourceType = typeof(Translate))]
    Quartz = 57,
}
