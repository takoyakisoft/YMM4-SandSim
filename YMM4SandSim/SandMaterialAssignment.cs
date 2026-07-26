using System.ComponentModel.DataAnnotations;
using YMM4SandSim.Localization;

namespace YMM4SandSim;

public enum SandMaterialAssignment
{
    [Display(Name = nameof(Translate.Assignment_ClosestColor), ResourceType = typeof(Translate))]
    ClosestColor = 0,

    [Display(Name = nameof(Translate.Assignment_SingleMaterial), ResourceType = typeof(Translate))]
    SingleMaterial = 1,
}
