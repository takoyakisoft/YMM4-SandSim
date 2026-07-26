using System.ComponentModel.DataAnnotations;
using YMM4SandSim.Localization;

namespace YMM4SandSim;

public enum SandSourceMode
{
    [Display(Name = nameof(Translate.SourceMode_Snapshot), ResourceType = typeof(Translate))]
    Snapshot = 0,

    [Display(Name = nameof(Translate.SourceMode_Continuous), ResourceType = typeof(Translate))]
    ContinuousEmitter = 1,

    [Display(Name = nameof(Translate.SourceMode_Stamp), ResourceType = typeof(Translate))]
    AddEveryFrame = 2,
}
