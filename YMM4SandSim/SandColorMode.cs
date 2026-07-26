using System.ComponentModel.DataAnnotations;
using YMM4SandSim.Localization;

namespace YMM4SandSim;

public enum SandColorMode
{
    [Display(Name = nameof(Translate.ColorMode_MaterialPalette), ResourceType = typeof(Translate))]
    MaterialPalette = 0,

    [Display(Name = nameof(Translate.ColorMode_PreserveInput), ResourceType = typeof(Translate))]
    PreserveInput = 1,
}
