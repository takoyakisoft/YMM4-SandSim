using System.ComponentModel.DataAnnotations;
using YMM4SandSim.Localization;

namespace YMM4SandSim;

public enum SandParticleSize
{
    [Display(Name = nameof(Translate.ParticleSize_One), ResourceType = typeof(Translate))]
    One = 1,

    [Display(Name = nameof(Translate.ParticleSize_Two), ResourceType = typeof(Translate))]
    Two = 2,

    [Display(Name = nameof(Translate.ParticleSize_Three), ResourceType = typeof(Translate))]
    Three = 3,

    [Display(Name = nameof(Translate.ParticleSize_Four), ResourceType = typeof(Translate))]
    Four = 4,

    [Display(Name = nameof(Translate.ParticleSize_Six), ResourceType = typeof(Translate))]
    Six = 6,

    [Display(Name = nameof(Translate.ParticleSize_Eight), ResourceType = typeof(Translate))]
    Eight = 8,
}
