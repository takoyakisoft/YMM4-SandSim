using System.ComponentModel.DataAnnotations;
using YMM4SandSim.Localization;

namespace YMM4SandSim;

public enum SandSolidPhysicsMode
{
    [Display(Name = nameof(Translate.SolidMode_Disabled), ResourceType = typeof(Translate))]
    Disabled = 0,

    [Display(Name = nameof(Translate.SolidMode_Xpbd), ResourceType = typeof(Translate))]
    Xpbd = 1,
}
