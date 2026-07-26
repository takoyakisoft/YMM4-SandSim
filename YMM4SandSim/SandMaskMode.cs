using System.ComponentModel.DataAnnotations;
using YMM4SandSim.Localization;

namespace YMM4SandSim;

public enum SandMaskMode
{
    [Display(Name = nameof(Translate.MaskMode_Alpha), ResourceType = typeof(Translate))]
    Alpha = 0,

    [Display(Name = nameof(Translate.MaskMode_Luminance), ResourceType = typeof(Translate))]
    Luminance = 1,

    [Display(Name = nameof(Translate.MaskMode_Both), ResourceType = typeof(Translate))]
    AlphaAndLuminance = 2,
}
